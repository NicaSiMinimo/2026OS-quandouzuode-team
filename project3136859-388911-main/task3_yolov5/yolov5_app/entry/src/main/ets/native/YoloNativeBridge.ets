import * as yoloNapi from 'libyolo_napi.so'

const MODEL_RAWFILE: string = 'yolov5s_ascend310b.om'

export interface YoloModelInfo {
  initialized: boolean
  deviceId: number
  runMode: number
  runtimePath: string
  lastError: string
  inputByteSizes: number[]
  outputByteSizes: number[]
}

export interface NativeTensor {
  index: number
  byteLength: number
  data: Uint8Array
}

export interface NativeInferenceResult {
  success: boolean
  latencyMs: number
  outputs: NativeTensor[]
}

export interface NativeDetection {
  x: number
  y: number
  width: number
  height: number
  score: number
  classId: number
}

export interface NativeLiveInferenceResult {
  success: boolean
  inferenceMs: number
  totalMs: number
  detections: NativeDetection[]
  preview?: object
}

/** Initialize the Ascend 310B OM model bundled in rawfile. */
export function initializeYolo(resourceManager: object, deviceId: number = 0): YoloModelInfo {
  const initialized: boolean = yoloNapi.initModel(resourceManager, MODEL_RAWFILE, deviceId)
  const info: YoloModelInfo = yoloNapi.getModelInfo() as YoloModelInfo
  if (!initialized) {
    throw new Error(info.lastError.length > 0 ? info.lastError : 'YOLOv5 AscendCL initialization failed')
  }
  return info
}

/** Initialize the bundled OM model on a native worker to keep ArkUI responsive. */
export async function initializeYoloAsync(resourceManager: object, deviceId: number = 0): Promise<YoloModelInfo> {
  const initialized: boolean = await yoloNapi.initModelAsync(resourceManager, MODEL_RAWFILE, deviceId)
  const info: YoloModelInfo = yoloNapi.getModelInfo() as YoloModelInfo
  if (!initialized) {
    throw new Error(info.lastError.length > 0 ? info.lastError : 'YOLOv5 AscendCL initialization failed')
  }
  return info
}

/** Query runtime loading, run mode, IO byte sizes, and the latest native error. */
export function getYoloModelInfo(): YoloModelInfo {
  return yoloNapi.getModelInfo() as YoloModelInfo
}

/** Run one asynchronous NPU inference on preprocessed float32 NCHW input. */
export async function inferYolo(input: Float32Array): Promise<NativeInferenceResult> {
  return await yoloNapi.infer(input) as NativeInferenceResult
}

/** Run native RGBA letterbox, service-side NPU inference and NMS for a camera PixelMap. */
export async function inferYoloPixelMap(
  pixelMap: object,
  confidence: number = 0.25,
  iou: number = 0.45
): Promise<NativeLiveInferenceResult> {
  return await yoloNapi.inferPixelMap(pixelMap, confidence, iou) as NativeLiveInferenceResult
}

/** Run live detection directly on camera YUV420 planes without JPEG encode/decode. */
export async function inferYoloYuv420(
  yPlane: Uint8Array,
  uPlane: Uint8Array,
  vPlane: Uint8Array,
  width: number,
  height: number,
  yRowStride: number,
  uRowStride: number,
  vRowStride: number,
  uPixelStride: number,
  vPixelStride: number,
  confidence: number = 0.25,
  iou: number = 0.45
): Promise<NativeLiveInferenceResult> {
  return await yoloNapi.inferYuv420(
    yPlane, uPlane, vPlane, width, height,
    yRowStride, uRowStride, vRowStride, uPixelStride, vPixelStride,
    confidence, iou
  ) as NativeLiveInferenceResult
}

/** Release all AscendCL and model resources. */
export function releaseYolo(): void {
  yoloNapi.releaseModel()
}
