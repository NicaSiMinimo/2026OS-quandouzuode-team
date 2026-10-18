#!/system/bin/sh
set -eu

SERVICE_DIR=/data/yolov5_napi
SERVICE_SCRIPT=/vendor/etc/yolo_acl_service.py
ENV_SCRIPT=/vendor/etc/yolo_cann_env.sh
PYTHON_BIN=/usr/local/Python/bin/python3.10
SUPERVISOR_LOG=$SERVICE_DIR/yolo_acl_supervisor.log
SERVICE_LOG=$SERVICE_DIR/yolo_acl_service.log

mkdir -p "$SERVICE_DIR" || {
    echo "yolo_acl_service: cannot create $SERVICE_DIR" >&2
    exit 73
}

log()
{
    message="yolo_acl_service: $*"
    echo "$message" >&2
    echo "$message" >>"$SUPERVISOR_LOG"
}

missing=0
for required_file in \
    "$SERVICE_SCRIPT" \
    "$ENV_SCRIPT" \
    /libaarch64/aarch64-linux-gnu/libm.so.6 \
    /usr/local/Ascend/driver/lib64/libascend_hal.so; do
    if [ ! -r "$required_file" ]; then
        log "missing readable dependency: $required_file"
        missing=1
    fi
done
if [ ! -x "$PYTHON_BIN" ]; then
    log "missing executable dependency: $PYTHON_BIN"
    missing=1
fi
if [ "$missing" -ne 0 ]; then
    log "static runtime validation failed; stopping this launch"
    exit 78
fi

. "$ENV_SCRIPT" || {
    log "failed to load runtime environment: $ENV_SCRIPT"
    exit 78
}
if [ -z "${ASCENDCL_LIBRARY:-}" ] || [ ! -r "$ASCENDCL_LIBRARY" ]; then
    log "missing CANN runtime library; checked $ASCEND_TOOLKIT_HOME/lib64/libascendcl.so and supported fallback layouts"
    exit 78
fi

waited=0
while [ ! -e /dev/davinci0 ] || \
      [ ! -e /dev/davinci_manager ] || \
      [ ! -e /dev/ascend_manager ]; do
    if [ "$waited" -ge 30 ]; then
        for node in /dev/davinci0 /dev/davinci_manager /dev/ascend_manager; do
            [ -e "$node" ] || log "missing NPU device node after ${waited}s: $node"
        done
        exit 75
    fi
    sleep 1
    waited=$((waited + 1))
done

if ! "$PYTHON_BIN" -c \
    'import ctypes, importlib.util, os, numpy; assert importlib.util.find_spec("ais_bench.infer.interface"); ctypes.CDLL(os.environ["ASCENDCL_LIBRARY"])' \
    >>"$SUPERVISOR_LOG" 2>&1; then
    log "Python/CANN preflight failed: $PYTHON_BIN, ais_bench, numpy or $ASCENDCL_LIBRARY is unusable"
    exit 70
fi

log "starting listener on 127.0.0.1:5001 with Python=$PYTHON_BIN CANN=$ASCEND_TOOLKIT_HOME ACL=$ASCENDCL_LIBRARY"
exec "$PYTHON_BIN" "$SERVICE_SCRIPT" >>"$SERVICE_LOG" 2>&1
