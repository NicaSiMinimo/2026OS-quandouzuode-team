export interface YoloModelInfo {
  initialized: boolean
  deviceId: number
  /** -1: unavailable, 0: ACL_HOST, 1: ACL_DEVICE */
  runMode: number
  runtimePath: string
  lastError: string
  inputByteSizes: number[]
  outputByteSizes: number[]
}

export interface NativeTensor {
  index: number
  byteLength: number
  /** Raw output bytes. Interpret the dtype/shape after board-side model inspection. */
  data: Uint8Array
}

export interface NativeInferenceResult {
  success: boolean
  latencyMs: number
  outputs: NativeTensor[]
}

export interface NativeDetection {
  /** Normalized coordinates in the original PixelMap, all in the range [0, 1]. */
  x: number
  y: number
  width: number
  height: number
  score: number
  classId: number
}

export interface NativeLiveInferenceResult {
  success: boolean
  /** Time spent in aclmdlExecute/ais_bench inference. */
  inferenceMs: number
  /** Native letterbox + inference + NMS time. */
  totalMs: number
  detections: NativeDetection[]
  /** Present for the single-stream YUV camera path. */
  preview?: object
}

/** Load an OM model from entry/src/main/resources/rawfile and initialize device context. */
export const initModel: (
  resourceManager: object,
  rawfileName: string,
  deviceId?: number
) => boolean

/** Load an OM model without blocking the ArkUI thread. */
export const initModelAsync: (
  resourceManager: object,
  rawfileName: string,
  deviceId?: number
) => Promise<boolean>

/** Return runtime path, run mode, model IO byte sizes, and the latest native error. */
export const getModelInfo: () => YoloModelInfo

/**
 * Run one model inference asynchronously.
 * The input must already be float32 NCHW data matching the model input byte size.
 */
export const infer: (input: Float32Array) => Promise<NativeInferenceResult>

/**
 * Convert an RGBA_8888 PixelMap to YOLOv5 input, run NPU inference and class-aware NMS.
 * Detection coordinates are normalized against the source PixelMap.
 */
export const inferPixelMap: (
  pixelMap: object,
  confidence?: number,
  iou?: number
) => Promise<NativeLiveInferenceResult>

/** Convert camera YUV420 planes to YOLO input and run compact live detection. */
export const inferYuv420: (
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
  confidence?: number,
  iou?: number
) => Promise<NativeLiveInferenceResult>

/** Release model, datasets, device buffers, context, device, and AscendCL runtime. */
export const releaseModel: () => void
