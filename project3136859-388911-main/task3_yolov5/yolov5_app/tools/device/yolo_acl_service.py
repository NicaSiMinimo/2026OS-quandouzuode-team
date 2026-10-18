#!/usr/bin/env python3.10
"""Local tensor RPC service for OpenHarmony NAPI -> glibc CANN bridging."""

import gc
import hashlib
import os
import socket
import struct
import sys
import tempfile
import threading
import time
import traceback

import numpy as np


# The first-stage protocol is intentionally loopback-only.  Do not make the
# listener address configurable through the application/service environment.
HOST = "127.0.0.1"
PORT = 5001
MODEL_PATH = os.environ.get(
    "YOLO_NAPI_MODEL", "/data/yolov5_napi/yolov5s_ascend310b.om"
)
# The HAP ships this exact 310B OM. Reject a different blob before loading it
# into the persistent service.
EXPECTED_MODEL_SHA256 = "6cf1b0635521fe961091329de366a0c78aab1faed297a66143e5e034754dde58"

MAGIC = b"YNAP"
VERSION = 1
CMD_INIT = 1
CMD_INFER = 2
CMD_INFO = 3
CMD_RELEASE = 4
CMD_PING = 5
CMD_DETECT = 6
CMD_DETECT_U8 = 8

HEADER = struct.Struct("<4sHHQ")
INIT_PREFIX = struct.Struct("<iQ")
INFER_PREFIX = struct.Struct("<dI")
DETECT_PREFIX = struct.Struct("<ff")
DETECTION_ITEM = struct.Struct("<fffffi")
MAX_PAYLOAD = 128 * 1024 * 1024
YOLO_STRIDE = 85
MAX_DETECTIONS = 100
_INFER_SESSION_TYPE = None


def log(message):
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {message}", flush=True)


def get_infer_session_type():
    """Import CANN only after OpenHarmony has finished bringing up the NPU."""
    global _INFER_SESSION_TYPE
    if _INFER_SESSION_TYPE is not None:
        return _INFER_SESSION_TYPE
    required_nodes = ("/dev/davinci0", "/dev/davinci_manager", "/dev/ascend_manager")
    missing = [path for path in required_nodes if not os.path.exists(path)]
    if missing:
        raise RuntimeError("NPU device nodes are not ready: " + ", ".join(missing))
    from ais_bench.infer.interface import InferSession
    _INFER_SESSION_TYPE = InferSession
    return _INFER_SESSION_TYPE


def recv_exact(sock, size):
    chunks = bytearray(size)
    view = memoryview(chunks)
    offset = 0
    while offset < size:
        count = sock.recv_into(view[offset:])
        if count == 0:
            raise ConnectionError("client disconnected before request completed")
        offset += count
    return bytes(chunks)


def send_response(sock, status, payload=b""):
    sock.sendall(HEADER.pack(MAGIC, VERSION, status, len(payload)))
    if payload:
        sock.sendall(payload)


class ModelRuntime:
    def __init__(self):
        self.lock = threading.RLock()
        self.session = None
        self.device_id = 0
        self.model_hash = ""
        self.input_sizes = []
        self.output_sizes = []
        self.input_shape = ()
        self.last_error = ""
        self.detect_count = 0

    def _model_info_payload(self):
        initialized = 1 if self.session is not None else 0
        toolkit_home = os.environ.get("ASCEND_TOOLKIT_HOME", "unknown")
        runtime_path = (
            f"service://127.0.0.1:5001/CANN@{toolkit_home}"
        ).encode("utf-8", errors="replace")
        payload = bytearray(struct.pack(
            "<IiiII", initialized, self.device_id, 0,
            len(self.input_sizes), len(self.output_sizes)
        ))
        for size in self.input_sizes:
            payload.extend(struct.pack("<Q", size))
        for size in self.output_sizes:
            payload.extend(struct.pack("<Q", size))
        payload.extend(struct.pack("<I", len(runtime_path)))
        payload.extend(runtime_path)
        return bytes(payload)

    def initialize(self, payload):
        if len(payload) < INIT_PREFIX.size:
            raise ValueError("INIT payload is too short")
        device_id, model_size = INIT_PREFIX.unpack_from(payload)
        model_data = payload[INIT_PREFIX.size:]
        if model_size != len(model_data):
            raise ValueError(
                f"model size mismatch: header={model_size}, received={len(model_data)}"
            )
        if model_size == 0 or model_size > 64 * 1024 * 1024:
            raise ValueError(f"invalid OM model size: {model_size}")

        digest = hashlib.sha256(model_data).hexdigest()
        if digest != EXPECTED_MODEL_SHA256:
            raise ValueError("OM model SHA-256 does not match the bundled YOLOv5 310B model")
        with self.lock:
            if (self.session is not None and self.device_id == device_id
                    and self.model_hash == digest):
                return self._model_info_payload()

            os.makedirs(os.path.dirname(MODEL_PATH), exist_ok=True)
            fd, temp_path = tempfile.mkstemp(
                prefix="yolov5-napi-", suffix=".om", dir=os.path.dirname(MODEL_PATH)
            )
            try:
                with os.fdopen(fd, "wb") as stream:
                    stream.write(model_data)
                    stream.flush()
                    os.fsync(stream.fileno())
                os.replace(temp_path, MODEL_PATH)
            finally:
                if os.path.exists(temp_path):
                    os.unlink(temp_path)

            self.session = None
            gc.collect()
            started = time.perf_counter()
            session_type = get_infer_session_type()
            session = session_type(device_id, MODEL_PATH)
            inputs = session.get_inputs()
            outputs = session.get_outputs()
            if len(inputs) != 1:
                raise RuntimeError(f"expected one model input, got {len(inputs)}")
            input_sizes = [int(item.size) for item in inputs]
            output_sizes = [int(item.size) for item in outputs]
            input_shape = tuple(int(value) for value in inputs[0].shape)
            input_elements = int(np.prod(input_shape, dtype=np.int64))
            if input_elements <= 0 or input_sizes[0] != input_elements * np.dtype(np.float32).itemsize:
                descriptor_dtype = getattr(inputs[0], "datatype", "unknown")
                raise RuntimeError(
                    "compact uint8 frontend requires a float32 OM input; "
                    f"descriptor shape={input_shape}, bytes={input_sizes[0]}, "
                    f"dtype={descriptor_dtype}"
                )

            self.session = session
            self.device_id = device_id
            self.model_hash = digest
            self.input_sizes = input_sizes
            self.output_sizes = output_sizes
            self.input_shape = input_shape
            self.last_error = ""
            log(
                "model ready: device=%d input=%s input_bytes=%d outputs=%s "
                "load_ms=%.3f sha256=%s"
                % (device_id, self.input_shape, self.input_sizes[0], self.output_sizes,
                   (time.perf_counter() - started) * 1000.0, digest[:12])
            )
            return self._model_info_payload()

    def _run_inference(self, input_data):
        if self.session is None:
            raise RuntimeError("model is not initialized")
        expected = self.input_sizes[0]
        if len(input_data) != expected:
            raise ValueError(
                f"input byte length mismatch: expected {expected}, got {len(input_data)}"
            )
        tensor = np.frombuffer(input_data, dtype=np.float32).reshape(self.input_shape)
        started = time.perf_counter()
        outputs = self.session.infer([tensor])
        latency_ms = (time.perf_counter() - started) * 1000.0
        return outputs, latency_ms

    def _run_inference_u8(self, input_data):
        if self.session is None:
            raise RuntimeError("model is not initialized")
        expected = int(np.prod(self.input_shape))
        if len(input_data) != expected:
            raise ValueError(
                f"uint8 input byte length mismatch: expected {expected}, got {len(input_data)}"
            )
        tensor = np.frombuffer(input_data, dtype=np.uint8).astype(np.float32)
        tensor = (tensor / np.float32(255.0)).reshape(self.input_shape)
        started = time.perf_counter()
        outputs = self.session.infer([tensor])
        latency_ms = (time.perf_counter() - started) * 1000.0
        return outputs, latency_ms

    @staticmethod
    def _iou(box_a, box_b):
        x1 = max(float(box_a[0]), float(box_b[0]))
        y1 = max(float(box_a[1]), float(box_b[1]))
        x2 = min(float(box_a[2]), float(box_b[2]))
        y2 = min(float(box_a[3]), float(box_b[3]))
        intersection = max(0.0, x2 - x1) * max(0.0, y2 - y1)
        area_a = max(0.0, float(box_a[2] - box_a[0])) * max(
            0.0, float(box_a[3] - box_a[1])
        )
        area_b = max(0.0, float(box_b[2] - box_b[0])) * max(
            0.0, float(box_b[3] - box_b[1])
        )
        denominator = area_a + area_b - intersection
        return intersection / denominator if denominator > 0.0 else 0.0

    def infer(self, payload):
        with self.lock:
            outputs, latency_ms = self._run_inference(payload)
            result = bytearray(INFER_PREFIX.pack(latency_ms, len(outputs)))
            actual_sizes = []
            for output in outputs:
                contiguous = np.ascontiguousarray(output)
                data = contiguous.tobytes(order="C")
                actual_sizes.append(len(data))
                result.extend(struct.pack("<Q", len(data)))
                result.extend(data)
            log(f"inference complete: latency_ms={latency_ms:.3f} outputs={actual_sizes}")
            return bytes(result)

    def detect(self, payload, uint8_input=False):
        if len(payload) < DETECT_PREFIX.size:
            raise ValueError("DETECT payload is too short")
        confidence, iou_threshold = DETECT_PREFIX.unpack_from(payload)
        if not 0.0 < confidence < 1.0 or not 0.0 < iou_threshold < 1.0:
            raise ValueError("DETECT thresholds must be between zero and one")

        with self.lock:
            input_data = memoryview(payload)[DETECT_PREFIX.size:]
            if uint8_input:
                outputs, latency_ms = self._run_inference_u8(input_data)
            else:
                outputs, latency_ms = self._run_inference(input_data)
            if not outputs:
                raise RuntimeError("model returned no output tensors")

            prediction = np.asarray(outputs[0], dtype=np.float32)
            if prediction.size == 0 or prediction.size % YOLO_STRIDE != 0:
                raise RuntimeError(
                    f"unexpected YOLO output shape: {prediction.shape}"
                )
            prediction = prediction.reshape((-1, YOLO_STRIDE))
            objectness = prediction[:, 4]
            class_values = prediction[:, 5:]
            class_ids = np.argmax(class_values, axis=1).astype(np.int32)
            row_ids = np.arange(prediction.shape[0])
            scores = objectness * class_values[row_ids, class_ids]
            mask = (
                np.isfinite(scores)
                & (objectness >= confidence)
                & (scores >= confidence)
                & np.all(np.isfinite(prediction[:, :4]), axis=1)
            )

            selected = prediction[mask, :4]
            selected_scores = scores[mask]
            selected_classes = class_ids[mask]
            if selected.shape[0] == 0:
                kept = []
            else:
                half_width = selected[:, 2] * 0.5
                half_height = selected[:, 3] * 0.5
                boxes = np.column_stack((
                    selected[:, 0] - half_width,
                    selected[:, 1] - half_height,
                    selected[:, 0] + half_width,
                    selected[:, 1] + half_height,
                ))
                order = np.argsort(selected_scores)[::-1]
                kept = []
                for index in order:
                    class_id = int(selected_classes[index])
                    suppressed = any(
                        class_id == kept_class
                        and self._iou(boxes[index], kept_box) > iou_threshold
                        for kept_box, _kept_score, kept_class in kept
                    )
                    if not suppressed:
                        kept.append((boxes[index], float(selected_scores[index]), class_id))
                        if len(kept) >= MAX_DETECTIONS:
                            break

            result = bytearray(INFER_PREFIX.pack(latency_ms, len(kept)))
            for box, score, class_id in kept:
                result.extend(DETECTION_ITEM.pack(
                    float(box[0]), float(box[1]), float(box[2]), float(box[3]),
                    score, class_id
                ))

            self.detect_count += 1
            if self.detect_count == 1 or self.detect_count % 30 == 0:
                log(
                    "compact detection: latency_ms=%.3f boxes=%d response_bytes=%d"
                    % (latency_ms, len(kept), len(result))
                )
            return bytes(result)

    def info(self):
        with self.lock:
            return self._model_info_payload()

    def release(self):
        with self.lock:
            self.session = None
            self.input_sizes = []
            self.output_sizes = []
            self.input_shape = ()
            self.model_hash = ""
            self.detect_count = 0
            gc.collect()
            log("model released")
            return self._model_info_payload()


RUNTIME = ModelRuntime()


def handle_client(client, address):
    del address
    client.settimeout(180.0)
    try:
        header = recv_exact(client, HEADER.size)
        magic, version, command, payload_size = HEADER.unpack(header)
        if magic != MAGIC or version != VERSION:
            raise ValueError("invalid protocol header")
        if payload_size > MAX_PAYLOAD:
            raise ValueError(f"payload too large: {payload_size}")
        payload = recv_exact(client, payload_size) if payload_size else b""
        if command == CMD_INIT:
            response = RUNTIME.initialize(payload)
        elif command == CMD_INFER:
            response = RUNTIME.infer(payload)
        elif command == CMD_INFO:
            response = RUNTIME.info()
        elif command == CMD_RELEASE:
            response = RUNTIME.release()
        elif command == CMD_PING:
            response = b"pong"
        elif command == CMD_DETECT:
            response = RUNTIME.detect(payload)
        elif command == CMD_DETECT_U8:
            response = RUNTIME.detect(payload, uint8_input=True)
        else:
            raise ValueError(f"unknown command: {command}")
        send_response(client, 0, response)
    except Exception as exc:
        RUNTIME.last_error = str(exc)
        log(f"request failed: {exc}\n{traceback.format_exc()}")
        try:
            send_response(client, 1, str(exc).encode("utf-8", errors="replace"))
        except Exception:
            pass
    finally:
        client.close()


def main():
    log(
        "runtime ready: python=%s numpy=%s toolkit=%s ascendcl=%s"
        % (
            sys.version.split()[0],
            np.__version__,
            os.environ.get("ASCEND_TOOLKIT_HOME", "missing"),
            os.environ.get("ASCENDCL_LIBRARY", "missing"),
        )
    )
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(4)
    log(f"YOLO NAPI ACL service listening on {HOST}:{PORT}")
    while True:
        client, address = server.accept()
        handle_client(client, address)


if __name__ == "__main__":
    main()
