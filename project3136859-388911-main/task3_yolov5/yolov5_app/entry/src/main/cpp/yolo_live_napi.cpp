#include "yolo_live_napi.h"

#include "yolo_engine.h"

#include <multimedia/image_framework/image_pixel_map_mdk.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <limits>
#include <string>
#include <vector>

namespace {
constexpr int MODEL_WIDTH = 640;
constexpr int MODEL_HEIGHT = 640;
constexpr int RGBA_8888 = 3;

struct LiveDetection {
    float x = 0.0F;
    float y = 0.0F;
    float width = 0.0F;
    float height = 0.0F;
    float score = 0.0F;
    int32_t classId = 0;
};

struct LiveInferTask {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::vector<uint8_t> pixels;
    std::vector<uint8_t> yPlane;
    std::vector<uint8_t> uPlane;
    std::vector<uint8_t> vPlane;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t rowSize = 0;
    uint32_t yRowStride = 0;
    uint32_t uRowStride = 0;
    uint32_t vRowStride = 0;
    uint32_t uPixelStride = 0;
    uint32_t vPixelStride = 0;
    bool isYuv = false;
    float confidenceThreshold = 0.25F;
    float iouThreshold = 0.45F;
    std::vector<LiveDetection> detections;
    double inferenceMs = 0.0;
    double totalMs = 0.0;
    std::string error;
};

napi_value MakeString(napi_env env, const std::string &value)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.size(), &result);
    return result;
}

void SetNamed(napi_env env, napi_value object, const char *name, napi_value value)
{
    napi_set_named_property(env, object, name, value);
}

float Clamp(float value, float minimum, float maximum)
{
    return std::max(minimum, std::min(value, maximum));
}

bool BuildRgbaLetterboxInputUint8(const LiveInferTask &task, std::vector<uint8_t> &input,
                                  float &scale, float &padX, float &padY, std::string &error)
{
    if (task.width == 0 || task.height == 0 || task.rowSize < task.width * 4U) {
        error = "invalid RGBA PixelMap dimensions";
        return false;
    }
    const size_t required = static_cast<size_t>(task.rowSize) * task.height;
    if (required > task.pixels.size()) {
        error = "PixelMap buffer is smaller than its row stride";
        return false;
    }

    scale = std::min(static_cast<float>(MODEL_WIDTH) / static_cast<float>(task.width),
                     static_cast<float>(MODEL_HEIGHT) / static_cast<float>(task.height));
    const int resizedWidth = std::max(1, static_cast<int>(std::lround(task.width * scale)));
    const int resizedHeight = std::max(1, static_cast<int>(std::lround(task.height * scale)));
    const int padLeft = (MODEL_WIDTH - resizedWidth) / 2;
    const int padTop = (MODEL_HEIGHT - resizedHeight) / 2;
    padX = static_cast<float>(padLeft);
    padY = static_cast<float>(padTop);

    input.assign(3U * MODEL_WIDTH * MODEL_HEIGHT, 114U);
    const size_t planeSize = static_cast<size_t>(MODEL_WIDTH) * MODEL_HEIGHT;
    for (int dy = 0; dy < resizedHeight; ++dy) {
        const uint32_t sourceY = std::min(task.height - 1U,
            static_cast<uint32_t>((static_cast<float>(dy) + 0.5F) / scale));
        for (int dx = 0; dx < resizedWidth; ++dx) {
            const uint32_t sourceX = std::min(task.width - 1U,
                static_cast<uint32_t>((static_cast<float>(dx) + 0.5F) / scale));
            const uint8_t *pixel = task.pixels.data() +
                static_cast<size_t>(sourceY) * task.rowSize + sourceX * 4U;
            const size_t outputIndex = static_cast<size_t>(dy + padTop) * MODEL_WIDTH + dx + padLeft;
            input[outputIndex] = pixel[0];
            input[planeSize + outputIndex] = pixel[1];
            input[planeSize * 2U + outputIndex] = pixel[2];
        }
    }
    return true;
}

bool BuildYuvLetterboxInputUint8(const LiveInferTask &task, std::vector<uint8_t> &input,
                                 float &scale, float &padX, float &padY, std::string &error)
{
    if (task.width == 0 || task.height == 0 || task.yRowStride < task.width ||
        task.uRowStride == 0 || task.vRowStride == 0 ||
        task.uPixelStride == 0 || task.vPixelStride == 0) {
        error = "invalid YUV420 image dimensions or strides";
        return false;
    }
    const uint32_t chromaWidth = (task.width + 1U) / 2U;
    const uint32_t chromaHeight = (task.height + 1U) / 2U;
    const size_t requiredY = static_cast<size_t>(task.yRowStride) * (task.height - 1U) + task.width;
    const size_t requiredU = static_cast<size_t>(task.uRowStride) * (chromaHeight - 1U) +
        static_cast<size_t>(chromaWidth - 1U) * task.uPixelStride + 1U;
    const size_t requiredV = static_cast<size_t>(task.vRowStride) * (chromaHeight - 1U) +
        static_cast<size_t>(chromaWidth - 1U) * task.vPixelStride + 1U;
    if (requiredY > task.yPlane.size() || requiredU > task.uPlane.size() ||
        requiredV > task.vPlane.size()) {
        error = "YUV420 component buffer is smaller than its stride metadata";
        return false;
    }

    scale = std::min(static_cast<float>(MODEL_WIDTH) / static_cast<float>(task.width),
                     static_cast<float>(MODEL_HEIGHT) / static_cast<float>(task.height));
    const int resizedWidth = std::max(1, static_cast<int>(std::lround(task.width * scale)));
    const int resizedHeight = std::max(1, static_cast<int>(std::lround(task.height * scale)));
    const int padLeft = (MODEL_WIDTH - resizedWidth) / 2;
    const int padTop = (MODEL_HEIGHT - resizedHeight) / 2;
    padX = static_cast<float>(padLeft);
    padY = static_cast<float>(padTop);

    input.assign(3U * MODEL_WIDTH * MODEL_HEIGHT, 114U);
    const size_t planeSize = static_cast<size_t>(MODEL_WIDTH) * MODEL_HEIGHT;

    // Camera analysis frames arrive continuously, so use center-sampled nearest
    // resize here. It avoids JPEG decode and is substantially cheaper than four
    // YUV-to-RGB conversions per output pixel while preserving YOLO accuracy.
    for (int dy = 0; dy < resizedHeight; ++dy) {
        const uint32_t sourceY = std::min(task.height - 1U,
            static_cast<uint32_t>((static_cast<float>(dy) + 0.5F) / scale));
        for (int dx = 0; dx < resizedWidth; ++dx) {
            const uint32_t sourceX = std::min(task.width - 1U,
                static_cast<uint32_t>((static_cast<float>(dx) + 0.5F) / scale));
            const int yValue = task.yPlane[static_cast<size_t>(sourceY) * task.yRowStride + sourceX];
            const size_t chromaX = sourceX / 2U;
            const size_t chromaY = sourceY / 2U;
            const int uValue = task.uPlane[chromaY * task.uRowStride + chromaX * task.uPixelStride];
            const int vValue = task.vPlane[chromaY * task.vRowStride + chromaX * task.vPixelStride];

            const int c = std::max(0, yValue - 16);
            const int d = uValue - 128;
            const int e = vValue - 128;
            const uint8_t red = static_cast<uint8_t>(Clamp(
                static_cast<float>((298 * c + 409 * e + 128) >> 8), 0.0F, 255.0F));
            const uint8_t green = static_cast<uint8_t>(Clamp(
                static_cast<float>((298 * c - 100 * d - 208 * e + 128) >> 8), 0.0F, 255.0F));
            const uint8_t blue = static_cast<uint8_t>(Clamp(
                static_cast<float>((298 * c + 516 * d + 128) >> 8), 0.0F, 255.0F));
            const size_t outputIndex = static_cast<size_t>(dy + padTop) * MODEL_WIDTH + dx + padLeft;
            input[outputIndex] = red;
            input[planeSize + outputIndex] = green;
            input[planeSize * 2U + outputIndex] = blue;
        }
    }
    return true;
}

bool MapRemoteDetections(const std::vector<YoloDetectionBox> &remoteDetections,
                         float scale, float padX, float padY,
                         uint32_t sourceWidth, uint32_t sourceHeight,
                         std::vector<LiveDetection> &detections)
{
    detections.clear();
    detections.reserve(remoteDetections.size());
    for (const YoloDetectionBox &candidate : remoteDetections) {
        if (!std::isfinite(candidate.x1) || !std::isfinite(candidate.y1) ||
            !std::isfinite(candidate.x2) || !std::isfinite(candidate.y2) ||
            !std::isfinite(candidate.score)) {
            continue;
        }
        const float sourceX1 = Clamp((candidate.x1 - padX) / scale, 0.0F,
                                     static_cast<float>(sourceWidth));
        const float sourceY1 = Clamp((candidate.y1 - padY) / scale, 0.0F,
                                     static_cast<float>(sourceHeight));
        const float sourceX2 = Clamp((candidate.x2 - padX) / scale, 0.0F,
                                     static_cast<float>(sourceWidth));
        const float sourceY2 = Clamp((candidate.y2 - padY) / scale, 0.0F,
                                     static_cast<float>(sourceHeight));
        if (sourceX2 <= sourceX1 || sourceY2 <= sourceY1) continue;

        LiveDetection detection;
        detection.x = sourceX1 / sourceWidth;
        detection.y = sourceY1 / sourceHeight;
        detection.width = (sourceX2 - sourceX1) / sourceWidth;
        detection.height = (sourceY2 - sourceY1) / sourceHeight;
        detection.score = candidate.score;
        detection.classId = candidate.classId;
        detections.push_back(detection);
    }
    return true;
}

void ExecuteLiveInfer(napi_env env, void *data)
{
    (void)env;
    auto *task = static_cast<LiveInferTask *>(data);
    const auto totalStart = std::chrono::steady_clock::now();

    std::vector<uint8_t> uint8Input;
    float scale = 1.0F;
    float padX = 0.0F;
    float padY = 0.0F;
    const bool uint8Ready = task->isYuv
        ? BuildYuvLetterboxInputUint8(*task, uint8Input, scale, padX, padY, task->error)
        : BuildRgbaLetterboxInputUint8(*task, uint8Input, scale, padX, padY, task->error);
    if (!uint8Ready) return;

    const YoloModelInfo info = YoloEngine::Instance().GetInfo();
    const size_t inputBytes = uint8Input.size();
    if (info.inputSizes.empty() ||
        info.inputSizes[0] % sizeof(float) != 0 ||
        info.inputSizes[0] / sizeof(float) != inputBytes) {
        task->error = "model input does not match the live NCHW tensor size";
        return;
    }

    std::vector<YoloDetectionBox> compactDetections;
    if (!YoloEngine::Instance().InferRemoteDetectionsUint8(
            uint8Input.data(), inputBytes, task->confidenceThreshold,
            task->iouThreshold, compactDetections, task->inferenceMs)) {
        // The production ABI is service-only.  Do not fall back to a raw
        // tensor response (or in-process ACL) after a compact request fails:
        // that would violate the bounded IPC contract and hide service errors.
        task->error = YoloEngine::Instance().GetInfo().lastError;
        if (task->error.empty()) task->error = "compact CANN detection request failed";
        return;
    }
    if (!MapRemoteDetections(compactDetections, scale, padX, padY,
                             task->width, task->height, task->detections)) {
        task->error = "failed to map compact CANN detections";
        return;
    }
    task->totalMs = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - totalStart).count();
}

void CompleteLiveInfer(napi_env env, napi_status status, void *data)
{
    auto *task = static_cast<LiveInferTask *>(data);
    if (status != napi_ok || !task->error.empty()) {
        const std::string message = task->error.empty() ? "live inference work failed" : task->error;
        napi_value errorObject = nullptr;
        napi_value errorMessage = MakeString(env, message);
        napi_create_error(env, nullptr, errorMessage, &errorObject);
        napi_reject_deferred(env, task->deferred, errorObject);
    } else {
        napi_value result = nullptr;
        napi_create_object(env, &result);

        napi_value success = nullptr;
        napi_get_boolean(env, true, &success);
        SetNamed(env, result, "success", success);

        napi_value inferenceMs = nullptr;
        napi_create_double(env, task->inferenceMs, &inferenceMs);
        SetNamed(env, result, "inferenceMs", inferenceMs);

        napi_value totalMs = nullptr;
        napi_create_double(env, task->totalMs, &totalMs);
        SetNamed(env, result, "totalMs", totalMs);

        napi_value detections = nullptr;
        napi_create_array_with_length(env, task->detections.size(), &detections);
        for (size_t index = 0; index < task->detections.size(); ++index) {
            const LiveDetection &item = task->detections[index];
            napi_value detection = nullptr;
            napi_create_object(env, &detection);

            napi_value value = nullptr;
            napi_create_double(env, item.x, &value);
            SetNamed(env, detection, "x", value);
            napi_create_double(env, item.y, &value);
            SetNamed(env, detection, "y", value);
            napi_create_double(env, item.width, &value);
            SetNamed(env, detection, "width", value);
            napi_create_double(env, item.height, &value);
            SetNamed(env, detection, "height", value);
            napi_create_double(env, item.score, &value);
            SetNamed(env, detection, "score", value);
            napi_create_int32(env, item.classId, &value);
            SetNamed(env, detection, "classId", value);
            napi_set_element(env, detections, index, detection);
        }
        SetNamed(env, result, "detections", detections);

        napi_resolve_deferred(env, task->deferred, result);
    }

    napi_delete_async_work(env, task->work);
    delete task;
}
} // namespace

napi_value InferPixelMap(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        napi_throw_type_error(env, nullptr, "inferPixelMap(pixelMap, confidence?, iou?) requires a PixelMap");
        return nullptr;
    }

    auto *task = new LiveInferTask();
    if (argc >= 2) {
        double confidence = task->confidenceThreshold;
        if (napi_get_value_double(env, args[1], &confidence) != napi_ok ||
            confidence <= 0.0 || confidence >= 1.0) {
            delete task;
            napi_throw_range_error(env, nullptr, "confidence must be between 0 and 1");
            return nullptr;
        }
        task->confidenceThreshold = static_cast<float>(confidence);
    }
    if (argc >= 3) {
        double iou = task->iouThreshold;
        if (napi_get_value_double(env, args[2], &iou) != napi_ok || iou <= 0.0 || iou >= 1.0) {
            delete task;
            napi_throw_range_error(env, nullptr, "iou must be between 0 and 1");
            return nullptr;
        }
        task->iouThreshold = static_cast<float>(iou);
    }

    NativePixelMap *pixelMap = OH_PixelMap_InitNativePixelMap(env, args[0]);
    OhosPixelMapInfos pixelInfo {};
    void *pixelAddress = nullptr;
    if (pixelMap == nullptr || OH_PixelMap_GetImageInfo(pixelMap, &pixelInfo) != 0 ||
        pixelInfo.pixelFormat != RGBA_8888 || pixelInfo.width == 0 || pixelInfo.height == 0 ||
        OH_PixelMap_AccessPixels(pixelMap, &pixelAddress) != 0 || pixelAddress == nullptr) {
        delete task;
        napi_throw_type_error(env, nullptr, "pixelMap must be a readable RGBA_8888 PixelMap");
        return nullptr;
    }

    const size_t pixelBytes = static_cast<size_t>(pixelInfo.rowSize) * pixelInfo.height;
    if (pixelInfo.rowSize < pixelInfo.width * 4U ||
        pixelBytes > 64U * 1024U * 1024U) {
        OH_PixelMap_UnAccessPixels(pixelMap);
        delete task;
        napi_throw_range_error(env, nullptr, "PixelMap dimensions are unsupported");
        return nullptr;
    }
    task->width = pixelInfo.width;
    task->height = pixelInfo.height;
    task->rowSize = pixelInfo.rowSize;
    task->pixels.resize(pixelBytes);
    std::memcpy(task->pixels.data(), pixelAddress, pixelBytes);
    OH_PixelMap_UnAccessPixels(pixelMap);

    napi_value promise = nullptr;
    napi_create_promise(env, &task->deferred, &promise);
    napi_value resourceName = MakeString(env, "YoloLivePixelMapInference");
    if (napi_create_async_work(env, nullptr, resourceName, ExecuteLiveInfer,
                               CompleteLiveInfer, task, &task->work) != napi_ok ||
        napi_queue_async_work(env, task->work) != napi_ok) {
        napi_value errorObject = nullptr;
        napi_value errorMessage = MakeString(env, "failed to queue live inference work");
        napi_create_error(env, nullptr, errorMessage, &errorObject);
        napi_reject_deferred(env, task->deferred, errorObject);
        if (task->work != nullptr) napi_delete_async_work(env, task->work);
        delete task;
    }
    return promise;
}

namespace {
bool CopyUint8Array(napi_env env, napi_value value, std::vector<uint8_t> &destination)
{
    napi_typedarray_type type = napi_uint8_array;
    size_t length = 0;
    void *data = nullptr;
    napi_value arrayBuffer = nullptr;
    size_t byteOffset = 0;
    if (napi_get_typedarray_info(env, value, &type, &length, &data,
                                 &arrayBuffer, &byteOffset) != napi_ok ||
        type != napi_uint8_array || data == nullptr || length == 0 ||
        length > 64U * 1024U * 1024U) {
        return false;
    }
    const auto *bytes = static_cast<const uint8_t *>(data);
    destination.assign(bytes, bytes + length);
    return true;
}

bool GetUint32(napi_env env, napi_value value, uint32_t &result)
{
    return napi_get_value_uint32(env, value, &result) == napi_ok && result > 0;
}
} // namespace

napi_value InferYuv420(napi_env env, napi_callback_info info)
{
    size_t argc = 12;
    napi_value args[12] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 10) {
        napi_throw_type_error(env, nullptr,
            "inferYuv420 requires Y/U/V planes, dimensions, row strides and pixel strides");
        return nullptr;
    }

    auto *task = new LiveInferTask();
    task->isYuv = true;
    if (!CopyUint8Array(env, args[0], task->yPlane) ||
        !CopyUint8Array(env, args[1], task->uPlane) ||
        !CopyUint8Array(env, args[2], task->vPlane)) {
        delete task;
        napi_throw_type_error(env, nullptr, "YUV components must be non-empty Uint8Array values");
        return nullptr;
    }
    if (!GetUint32(env, args[3], task->width) ||
        !GetUint32(env, args[4], task->height) ||
        !GetUint32(env, args[5], task->yRowStride) ||
        !GetUint32(env, args[6], task->uRowStride) ||
        !GetUint32(env, args[7], task->vRowStride) ||
        !GetUint32(env, args[8], task->uPixelStride) ||
        !GetUint32(env, args[9], task->vPixelStride)) {
        delete task;
        napi_throw_range_error(env, nullptr, "YUV dimensions and strides must be positive integers");
        return nullptr;
    }

    if (argc >= 11) {
        double confidence = task->confidenceThreshold;
        if (napi_get_value_double(env, args[10], &confidence) != napi_ok ||
            confidence <= 0.0 || confidence >= 1.0) {
            delete task;
            napi_throw_range_error(env, nullptr, "confidence must be between zero and one");
            return nullptr;
        }
        task->confidenceThreshold = static_cast<float>(confidence);
    }
    if (argc >= 12) {
        double iou = task->iouThreshold;
        if (napi_get_value_double(env, args[11], &iou) != napi_ok || iou <= 0.0 || iou >= 1.0) {
            delete task;
            napi_throw_range_error(env, nullptr, "iou must be between zero and one");
            return nullptr;
        }
        task->iouThreshold = static_cast<float>(iou);
    }

    napi_value promise = nullptr;
    napi_create_promise(env, &task->deferred, &promise);
    napi_value resourceName = MakeString(env, "YoloLiveYuv420Inference");
    if (napi_create_async_work(env, nullptr, resourceName, ExecuteLiveInfer,
                               CompleteLiveInfer, task, &task->work) != napi_ok ||
        napi_queue_async_work(env, task->work) != napi_ok) {
        napi_value errorObject = nullptr;
        napi_value errorMessage = MakeString(env, "failed to queue YUV inference work");
        napi_create_error(env, nullptr, errorMessage, &errorObject);
        napi_reject_deferred(env, task->deferred, errorObject);
        if (task->work != nullptr) napi_delete_async_work(env, task->work);
        delete task;
    }
    return promise;
}
