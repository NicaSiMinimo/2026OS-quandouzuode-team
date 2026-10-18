#include "yolo_engine.h"

#include <hilog/log.h>

#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <limits>
#include <sstream>

#undef LOG_TAG
#undef LOG_DOMAIN
#define LOG_TAG "YoloNapiEngine"
#define LOG_DOMAIN 0xFF00

namespace {
constexpr uint16_t REMOTE_PROTOCOL_VERSION = 1;
constexpr uint16_t REMOTE_CMD_INIT = 1;
constexpr uint16_t REMOTE_CMD_INFER = 2;
constexpr uint16_t REMOTE_CMD_RELEASE = 4;
constexpr uint16_t REMOTE_CMD_DETECT = 6;
constexpr uint16_t REMOTE_CMD_DETECT_U8 = 8;
constexpr size_t REMOTE_HEADER_SIZE = 16;
constexpr size_t REMOTE_MAX_RESPONSE = 128 * 1024 * 1024;
constexpr uint16_t REMOTE_PORT = 5001;

template<typename T>
void AppendScalar(std::vector<uint8_t> &buffer, T value)
{
    const auto *bytes = reinterpret_cast<const uint8_t *>(&value);
    buffer.insert(buffer.end(), bytes, bytes + sizeof(T));
}

template<typename T>
bool ReadScalar(const std::vector<uint8_t> &buffer, size_t &offset, T &value)
{
    if (offset > buffer.size() || sizeof(T) > buffer.size() - offset) {
        return false;
    }
    std::memcpy(&value, buffer.data() + offset, sizeof(T));
    offset += sizeof(T);
    return true;
}

bool SendAll(int socketFd, const uint8_t *data, size_t size)
{
    size_t offset = 0;
    while (offset < size) {
        ssize_t count = send(socketFd, data + offset, size - offset, 0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return false;
        offset += static_cast<size_t>(count);
    }
    return true;
}

bool ReceiveAll(int socketFd, uint8_t *data, size_t size)
{
    size_t offset = 0;
    while (offset < size) {
        ssize_t count = recv(socketFd, data + offset, size - offset, 0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return false;
        offset += static_cast<size_t>(count);
    }
    return true;
}
} // namespace

YoloEngine &YoloEngine::Instance()
{
    static YoloEngine engine;
    return engine;
}

YoloEngine::~YoloEngine()
{
    Release();
}

void YoloEngine::SetErrorLocked(const std::string &message)
{
    lastError_ = message;
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "%{public}s", message.c_str());
}

bool YoloEngine::CheckAclLocked(aclError code, const char *operation)
{
    if (code == ACL_SUCCESS) {
        return true;
    }
    std::ostringstream stream;
    stream << operation << " failed, ACL error=" << code;
    std::string recent = api_.RecentAclError();
    if (!recent.empty()) {
        stream << ", detail=" << recent;
    }
    SetErrorLocked(stream.str());
    return false;
}

bool YoloEngine::RemoteRequestLocked(uint16_t command, const uint8_t *payload, size_t payloadSize,
                                     std::vector<uint8_t> &response, std::string &error) const
{
    response.clear();
    error.clear();

    int socketFd = socket(AF_INET, SOCK_STREAM, 0);
    if (socketFd < 0) {
        error = std::string("socket failed: ") + std::strerror(errno);
        return false;
    }
    auto closeSocket = [&socketFd]() {
        if (socketFd >= 0) close(socketFd);
        socketFd = -1;
    };

    timeval timeout {};
    timeout.tv_sec = 180;
    setsockopt(socketFd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    setsockopt(socketFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

    sockaddr_in address {};
    address.sin_family = AF_INET;
    address.sin_port = htons(REMOTE_PORT);
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    if (connect(socketFd, reinterpret_cast<sockaddr *>(&address), sizeof(address)) != 0) {
        error = std::string("connect 127.0.0.1:5001 failed: ") + std::strerror(errno);
        closeSocket();
        return false;
    }

    std::array<uint8_t, REMOTE_HEADER_SIZE> header {};
    header[0] = 'Y';
    header[1] = 'N';
    header[2] = 'A';
    header[3] = 'P';
    std::memcpy(header.data() + 4, &REMOTE_PROTOCOL_VERSION, sizeof(REMOTE_PROTOCOL_VERSION));
    std::memcpy(header.data() + 6, &command, sizeof(command));
    uint64_t wirePayloadSize = static_cast<uint64_t>(payloadSize);
    std::memcpy(header.data() + 8, &wirePayloadSize, sizeof(wirePayloadSize));
    if (!SendAll(socketFd, header.data(), header.size()) ||
        (payloadSize > 0 && !SendAll(socketFd, payload, payloadSize))) {
        error = std::string("send to CANN service failed: ") + std::strerror(errno);
        closeSocket();
        return false;
    }

    if (!ReceiveAll(socketFd, header.data(), header.size())) {
        error = std::string("receive CANN service header failed: ") + std::strerror(errno);
        closeSocket();
        return false;
    }
    if (header[0] != 'Y' || header[1] != 'N' || header[2] != 'A' || header[3] != 'P') {
        error = "CANN service returned invalid protocol magic";
        closeSocket();
        return false;
    }
    uint16_t responseVersion = 0;
    uint16_t status = 0;
    uint64_t responseSize = 0;
    std::memcpy(&responseVersion, header.data() + 4, sizeof(responseVersion));
    std::memcpy(&status, header.data() + 6, sizeof(status));
    std::memcpy(&responseSize, header.data() + 8, sizeof(responseSize));
    if (responseVersion != REMOTE_PROTOCOL_VERSION || responseSize > REMOTE_MAX_RESPONSE) {
        error = "CANN service returned an unsupported or oversized response";
        closeSocket();
        return false;
    }

    response.resize(static_cast<size_t>(responseSize));
    if (!response.empty() && !ReceiveAll(socketFd, response.data(), response.size())) {
        error = std::string("receive CANN service payload failed: ") + std::strerror(errno);
        response.clear();
        closeSocket();
        return false;
    }
    closeSocket();
    if (status != 0) {
        error.assign(response.begin(), response.end());
        if (error.empty()) error = "CANN service request failed";
        response.clear();
        return false;
    }
    return true;
}

bool YoloEngine::ParseRemoteInfoLocked(const std::vector<uint8_t> &payload)
{
    size_t offset = 0;
    uint32_t initialized = 0;
    int32_t deviceId = 0;
    int32_t runMode = -1;
    uint32_t inputCount = 0;
    uint32_t outputCount = 0;
    if (!ReadScalar(payload, offset, initialized) || !ReadScalar(payload, offset, deviceId) ||
        !ReadScalar(payload, offset, runMode) || !ReadScalar(payload, offset, inputCount) ||
        !ReadScalar(payload, offset, outputCount) || inputCount > 16 || outputCount > 64) {
        SetErrorLocked("CANN service returned malformed model information");
        return false;
    }

    std::vector<size_t> inputSizes;
    std::vector<size_t> outputSizes;
    for (uint32_t i = 0; i < inputCount; ++i) {
        uint64_t size = 0;
        if (!ReadScalar(payload, offset, size) || size > std::numeric_limits<size_t>::max()) {
            SetErrorLocked("CANN service returned an invalid input size");
            return false;
        }
        inputSizes.push_back(static_cast<size_t>(size));
    }
    for (uint32_t i = 0; i < outputCount; ++i) {
        uint64_t size = 0;
        if (!ReadScalar(payload, offset, size) || size > std::numeric_limits<size_t>::max()) {
            SetErrorLocked("CANN service returned an invalid output size");
            return false;
        }
        outputSizes.push_back(static_cast<size_t>(size));
    }
    uint32_t pathLength = 0;
    if (!ReadScalar(payload, offset, pathLength) || pathLength > payload.size() - offset) {
        SetErrorLocked("CANN service returned an invalid runtime path");
        return false;
    }
    std::string runtimePath(reinterpret_cast<const char *>(payload.data() + offset), pathLength);
    offset += pathLength;
    if (offset != payload.size() || initialized == 0 || inputSizes.size() != 1 || outputSizes.empty()) {
        SetErrorLocked("CANN service did not initialize a usable YOLO model");
        return false;
    }

    deviceId_ = deviceId;
    runMode_ = static_cast<aclrtRunMode>(runMode);
    inputSizes_ = std::move(inputSizes);
    outputSizes_ = std::move(outputSizes);
    runtimePath_ = std::move(runtimePath);
    modelLoaded_ = true;
    remoteMode_ = true;
    lastError_.clear();
    return true;
}

bool YoloEngine::InitializeRemoteLocked(const uint8_t *modelData, size_t modelSize, int32_t deviceId)
{
    if (modelSize > std::numeric_limits<uint64_t>::max() - sizeof(int32_t) - sizeof(uint64_t)) {
        SetErrorLocked("OM model is too large for the CANN service protocol");
        return false;
    }
    std::vector<uint8_t> request;
    request.reserve(sizeof(int32_t) + sizeof(uint64_t) + modelSize);
    AppendScalar(request, deviceId);
    AppendScalar(request, static_cast<uint64_t>(modelSize));
    request.insert(request.end(), modelData, modelData + modelSize);

    std::vector<uint8_t> response;
    std::string error;
    if (!RemoteRequestLocked(REMOTE_CMD_INIT, request.data(), request.size(), response, error)) {
        SetErrorLocked(std::string("CANN inference service unavailable: ") + error);
        return false;
    }
    if (!ParseRemoteInfoLocked(response)) return false;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                 "YOLO OM initialized through CANN service: device=%{public}d, inputs=%{public}zu, outputs=%{public}zu",
                 deviceId_, inputSizes_.size(), outputSizes_.size());
    return true;
}

bool YoloEngine::InferRemoteLocked(const uint8_t *inputData, size_t inputSize,
                                   std::vector<std::vector<uint8_t>> &outputs, double &latencyMs)
{
    std::vector<uint8_t> response;
    std::string error;
    if (!RemoteRequestLocked(REMOTE_CMD_INFER, inputData, inputSize, response, error)) {
        SetErrorLocked(std::string("CANN service inference failed: ") + error);
        return false;
    }

    size_t offset = 0;
    uint32_t outputCount = 0;
    if (!ReadScalar(response, offset, latencyMs) || !ReadScalar(response, offset, outputCount) ||
        outputCount != outputSizes_.size()) {
        SetErrorLocked("CANN service returned malformed inference metadata");
        return false;
    }
    outputs.clear();
    outputs.reserve(outputCount);
    for (uint32_t i = 0; i < outputCount; ++i) {
        uint64_t size = 0;
        if (!ReadScalar(response, offset, size) || size != outputSizes_[i] ||
            size > response.size() - offset) {
            outputs.clear();
            SetErrorLocked("CANN service returned an invalid output tensor");
            return false;
        }
        outputs.emplace_back(response.begin() + static_cast<std::ptrdiff_t>(offset),
                             response.begin() + static_cast<std::ptrdiff_t>(offset + size));
        offset += static_cast<size_t>(size);
    }
    if (offset != response.size()) {
        outputs.clear();
        SetErrorLocked("CANN service response has trailing data");
        return false;
    }
    return true;
}

bool YoloEngine::InferRemoteDetectionsLocked(const uint8_t *inputData, size_t inputSize,
                                             float confidenceThreshold, float iouThreshold,
                                             std::vector<YoloDetectionBox> &detections,
                                             double &latencyMs)
{
    return InferRemoteDetectionCommandLocked(REMOTE_CMD_DETECT, inputData, inputSize,
                                              confidenceThreshold, iouThreshold,
                                              detections, latencyMs);
}

bool YoloEngine::InferRemoteDetectionCommandLocked(uint16_t command,
                                                   const uint8_t *inputData, size_t inputSize,
                                                   float confidenceThreshold, float iouThreshold,
                                                   std::vector<YoloDetectionBox> &detections,
                                                   double &latencyMs)
{
    std::vector<uint8_t> request;
    request.reserve(sizeof(float) * 2U + inputSize);
    AppendScalar(request, confidenceThreshold);
    AppendScalar(request, iouThreshold);
    request.insert(request.end(), inputData, inputData + inputSize);

    std::vector<uint8_t> response;
    std::string error;
    if (!RemoteRequestLocked(command, request.data(), request.size(), response, error)) {
        SetErrorLocked(std::string("compact CANN detection failed: ") + error);
        return false;
    }

    size_t offset = 0;
    uint32_t detectionCount = 0;
    if (!ReadScalar(response, offset, latencyMs) ||
        !ReadScalar(response, offset, detectionCount) || detectionCount > 100) {
        SetErrorLocked("CANN service returned malformed compact detection metadata");
        return false;
    }

    detections.clear();
    detections.reserve(detectionCount);
    for (uint32_t index = 0; index < detectionCount; ++index) {
        YoloDetectionBox detection;
        if (!ReadScalar(response, offset, detection.x1) ||
            !ReadScalar(response, offset, detection.y1) ||
            !ReadScalar(response, offset, detection.x2) ||
            !ReadScalar(response, offset, detection.y2) ||
            !ReadScalar(response, offset, detection.score) ||
            !ReadScalar(response, offset, detection.classId)) {
            detections.clear();
            SetErrorLocked("CANN service returned a truncated compact detection");
            return false;
        }
        detections.push_back(detection);
    }
    if (offset != response.size()) {
        detections.clear();
        SetErrorLocked("CANN compact detection response has trailing data");
        return false;
    }
    return true;
}

bool YoloEngine::Initialize(const uint8_t *modelData, size_t modelSize, int32_t deviceId)
{
    std::lock_guard<std::mutex> lock(mutex_);
    CleanupLocked();
    lastError_.clear();

    if (modelData == nullptr || modelSize == 0) {
        SetErrorLocked("OM model data is empty");
        return false;
    }
    if (InitializeRemoteLocked(modelData, modelSize, deviceId)) {
        return true;
    }
    const std::string remoteError = lastError_;
    lastError_.clear();

#if YOLO_ENABLE_DIRECT_ACL
    if (!api_.Load()) {
        SetErrorLocked(remoteError + "; direct AscendCL fallback failed: " + api_.LastError());
        return false;
    }
    if (!CheckAclLocked(api_.aclInit(nullptr), "aclInit")) {
        CleanupLocked();
        return false;
    }
    aclInitialized_ = true;
    deviceId_ = deviceId;

    if (!CheckAclLocked(api_.aclrtSetDevice(deviceId_), "aclrtSetDevice")) {
        CleanupLocked();
        return false;
    }
    deviceSet_ = true;
    if (!CheckAclLocked(api_.aclrtCreateContext(&context_, deviceId_), "aclrtCreateContext")) {
        CleanupLocked();
        return false;
    }
    if (!CheckAclLocked(api_.aclrtSetCurrentContext(context_), "aclrtSetCurrentContext")) {
        CleanupLocked();
        return false;
    }
    if (!CheckAclLocked(api_.aclrtGetRunMode(&runMode_), "aclrtGetRunMode")) {
        CleanupLocked();
        return false;
    }

    void *modelAddress = const_cast<uint8_t *>(modelData);
    void *deviceModelAddress = nullptr;
    if (runMode_ == ACL_DEVICE) {
        if (!CheckAclLocked(api_.aclrtMalloc(&deviceModelAddress, modelSize,
                                             ACL_MEM_MALLOC_NORMAL_ONLY),
                            "aclrtMalloc(model)")) {
            CleanupLocked();
            return false;
        }
        // In ACL_DEVICE mode the application runs on the board Control CPU and
        // aclrtMalloc memory is directly addressable by that process.
        std::memcpy(deviceModelAddress, modelData, modelSize);
        modelAddress = deviceModelAddress;
    }

    aclError loadResult = api_.aclmdlLoadFromMem(modelAddress, modelSize, &modelId_);
    if (deviceModelAddress != nullptr) {
        api_.aclrtFree(deviceModelAddress);
    }
    if (!CheckAclLocked(loadResult, "aclmdlLoadFromMem")) {
        CleanupLocked();
        return false;
    }
    modelLoaded_ = true;

    modelDesc_ = api_.aclmdlCreateDesc();
    if (modelDesc_ == nullptr) {
        SetErrorLocked("aclmdlCreateDesc returned null");
        CleanupLocked();
        return false;
    }
    if (!CheckAclLocked(api_.aclmdlGetDesc(modelDesc_, modelId_), "aclmdlGetDesc")) {
        CleanupLocked();
        return false;
    }
    if (!AllocateDatasetsLocked()) {
        CleanupLocked();
        return false;
    }

    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                 "YOLO OM initialized: device=%{public}d, runMode=%{public}d, inputs=%{public}zu, outputs=%{public}zu",
                 deviceId_, static_cast<int32_t>(runMode_), inputSizes_.size(), outputSizes_.size());
    return true;
#else
    SetErrorLocked(remoteError);
    return false;
#endif
}

bool YoloEngine::AddBufferLocked(aclmdlDataset *dataset, size_t size, bool input)
{
    if (size == 0) {
        SetErrorLocked(input ? "model input size is zero" : "model output size is zero");
        return false;
    }

    void *deviceBuffer = nullptr;
    if (!CheckAclLocked(api_.aclrtMalloc(&deviceBuffer, size, ACL_MEM_MALLOC_NORMAL_ONLY),
                        input ? "aclrtMalloc(input)" : "aclrtMalloc(output)")) {
        return false;
    }
    aclDataBuffer *dataBuffer = api_.aclCreateDataBuffer(deviceBuffer, size);
    if (dataBuffer == nullptr) {
        api_.aclrtFree(deviceBuffer);
        SetErrorLocked("aclCreateDataBuffer returned null");
        return false;
    }
    if (!CheckAclLocked(api_.aclmdlAddDatasetBuffer(dataset, dataBuffer),
                        "aclmdlAddDatasetBuffer")) {
        api_.aclDestroyDataBuffer(dataBuffer);
        api_.aclrtFree(deviceBuffer);
        return false;
    }

    if (input) {
        inputDeviceBuffers_.push_back(deviceBuffer);
        inputDataBuffers_.push_back(dataBuffer);
    } else {
        outputDeviceBuffers_.push_back(deviceBuffer);
        outputDataBuffers_.push_back(dataBuffer);
    }
    return true;
}

bool YoloEngine::AllocateDatasetsLocked()
{
    const size_t inputCount = api_.aclmdlGetNumInputs(modelDesc_);
    const size_t outputCount = api_.aclmdlGetNumOutputs(modelDesc_);
    if (inputCount != 1 || outputCount == 0) {
        std::ostringstream stream;
        stream << "expected one model input and at least one output, got inputs="
               << inputCount << ", outputs=" << outputCount;
        SetErrorLocked(stream.str());
        return false;
    }

    inputDataset_ = api_.aclmdlCreateDataset();
    outputDataset_ = api_.aclmdlCreateDataset();
    if (inputDataset_ == nullptr || outputDataset_ == nullptr) {
        SetErrorLocked("aclmdlCreateDataset returned null");
        return false;
    }

    inputSizes_.reserve(inputCount);
    for (size_t i = 0; i < inputCount; ++i) {
        size_t size = api_.aclmdlGetInputSizeByIndex(modelDesc_, i);
        inputSizes_.push_back(size);
        if (!AddBufferLocked(inputDataset_, size, true)) return false;
    }

    outputSizes_.reserve(outputCount);
    for (size_t i = 0; i < outputCount; ++i) {
        size_t size = api_.aclmdlGetOutputSizeByIndex(modelDesc_, i);
        outputSizes_.push_back(size);
        if (!AddBufferLocked(outputDataset_, size, false)) return false;
    }
    return true;
}

bool YoloEngine::Infer(const uint8_t *inputData, size_t inputSize,
                       std::vector<std::vector<uint8_t>> &outputs, double &latencyMs)
{
    std::lock_guard<std::mutex> lock(mutex_);
    lastError_.clear();
    latencyMs = 0.0;

    if (!modelLoaded_ || (!remoteMode_ && modelDesc_ == nullptr) || inputSizes_.empty()) {
        SetErrorLocked("model is not initialized");
        return false;
    }
    if (inputData == nullptr || inputSize != inputSizes_[0]) {
        std::ostringstream stream;
        stream << "input byte length mismatch: expected " << inputSizes_[0]
               << ", got " << inputSize;
        SetErrorLocked(stream.str());
        return false;
    }
    if (remoteMode_) {
        return InferRemoteLocked(inputData, inputSize, outputs, latencyMs);
    }
    if (!CheckAclLocked(api_.aclrtSetCurrentContext(context_), "aclrtSetCurrentContext(infer)")) {
        return false;
    }

    if (runMode_ == ACL_DEVICE) {
        std::memcpy(inputDeviceBuffers_[0], inputData, inputSize);
    } else if (!CheckAclLocked(
                   api_.aclrtMemcpy(inputDeviceBuffers_[0], inputSizes_[0], inputData, inputSize,
                                    ACL_MEMCPY_HOST_TO_DEVICE),
                   "aclrtMemcpy(input)")) {
        return false;
    }

    const auto start = std::chrono::steady_clock::now();
    if (!CheckAclLocked(api_.aclmdlExecute(modelId_, inputDataset_, outputDataset_),
                        "aclmdlExecute")) {
        return false;
    }
    const auto end = std::chrono::steady_clock::now();
    latencyMs = std::chrono::duration<double, std::milli>(end - start).count();

    outputs.clear();
    outputs.resize(outputSizes_.size());
    for (size_t i = 0; i < outputSizes_.size(); ++i) {
        outputs[i].resize(outputSizes_[i]);
        if (runMode_ == ACL_DEVICE) {
            std::memcpy(outputs[i].data(), outputDeviceBuffers_[i], outputSizes_[i]);
        } else if (!CheckAclLocked(
                       api_.aclrtMemcpy(outputs[i].data(), outputs[i].size(),
                                        outputDeviceBuffers_[i], outputSizes_[i],
                                        ACL_MEMCPY_DEVICE_TO_HOST),
                       "aclrtMemcpy(output)")) {
            outputs.clear();
            return false;
        }
    }
    return true;
}

bool YoloEngine::InferRemoteDetections(const uint8_t *inputData, size_t inputSize,
                                       float confidenceThreshold, float iouThreshold,
                                       std::vector<YoloDetectionBox> &detections,
                                       double &latencyMs)
{
    std::lock_guard<std::mutex> lock(mutex_);
    lastError_.clear();
    latencyMs = 0.0;
    detections.clear();

    if (!modelLoaded_ || !remoteMode_ || inputSizes_.empty()) {
        return false;
    }
    if (inputData == nullptr || inputSize != inputSizes_[0]) {
        std::ostringstream stream;
        stream << "input byte length mismatch: expected " << inputSizes_[0]
               << ", got " << inputSize;
        SetErrorLocked(stream.str());
        return false;
    }
    return InferRemoteDetectionsLocked(inputData, inputSize, confidenceThreshold,
                                       iouThreshold, detections, latencyMs);
}

bool YoloEngine::InferRemoteDetectionsUint8(const uint8_t *inputData, size_t inputSize,
                                            float confidenceThreshold, float iouThreshold,
                                            std::vector<YoloDetectionBox> &detections,
                                            double &latencyMs)
{
    std::lock_guard<std::mutex> lock(mutex_);
    lastError_.clear();
    latencyMs = 0.0;
    detections.clear();

    if (!modelLoaded_ || !remoteMode_ || inputSizes_.empty() ||
        inputSizes_[0] % sizeof(float) != 0) {
        return false;
    }
    const size_t expected = inputSizes_[0] / sizeof(float);
    if (inputData == nullptr || inputSize != expected) {
        std::ostringstream stream;
        stream << "uint8 input byte length mismatch: expected " << expected
               << ", got " << inputSize;
        SetErrorLocked(stream.str());
        return false;
    }
    return InferRemoteDetectionCommandLocked(REMOTE_CMD_DETECT_U8, inputData, inputSize,
                                              confidenceThreshold, iouThreshold,
                                              detections, latencyMs);
}

void YoloEngine::CleanupLocked()
{
    if (remoteMode_) {
        std::vector<uint8_t> response;
        std::string error;
        if (!RemoteRequestLocked(REMOTE_CMD_RELEASE, nullptr, 0, response, error)) {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG,
                         "CANN service RELEASE failed during cleanup: %{public}s", error.c_str());
        }
    }

    if (api_.IsLoaded() && context_ != nullptr && api_.aclrtSetCurrentContext != nullptr) {
        api_.aclrtSetCurrentContext(context_);
    }

    for (aclDataBuffer *buffer : inputDataBuffers_) {
        if (buffer != nullptr && api_.aclDestroyDataBuffer != nullptr) api_.aclDestroyDataBuffer(buffer);
    }
    for (aclDataBuffer *buffer : outputDataBuffers_) {
        if (buffer != nullptr && api_.aclDestroyDataBuffer != nullptr) api_.aclDestroyDataBuffer(buffer);
    }
    inputDataBuffers_.clear();
    outputDataBuffers_.clear();

    if (inputDataset_ != nullptr && api_.aclmdlDestroyDataset != nullptr) {
        api_.aclmdlDestroyDataset(inputDataset_);
    }
    if (outputDataset_ != nullptr && api_.aclmdlDestroyDataset != nullptr) {
        api_.aclmdlDestroyDataset(outputDataset_);
    }
    inputDataset_ = nullptr;
    outputDataset_ = nullptr;

    for (void *buffer : inputDeviceBuffers_) {
        if (buffer != nullptr && api_.aclrtFree != nullptr) api_.aclrtFree(buffer);
    }
    for (void *buffer : outputDeviceBuffers_) {
        if (buffer != nullptr && api_.aclrtFree != nullptr) api_.aclrtFree(buffer);
    }
    inputDeviceBuffers_.clear();
    outputDeviceBuffers_.clear();

    if (modelDesc_ != nullptr && api_.aclmdlDestroyDesc != nullptr) {
        api_.aclmdlDestroyDesc(modelDesc_);
    }
    modelDesc_ = nullptr;
    if (modelLoaded_ && api_.aclmdlUnload != nullptr) {
        api_.aclmdlUnload(modelId_);
    }
    modelLoaded_ = false;
    modelId_ = 0;

    if (context_ != nullptr && api_.aclrtDestroyContext != nullptr) {
        api_.aclrtDestroyContext(context_);
    }
    context_ = nullptr;
    if (deviceSet_ && api_.aclrtResetDevice != nullptr) {
        api_.aclrtResetDevice(deviceId_);
    }
    deviceSet_ = false;
    if (aclInitialized_ && api_.aclFinalize != nullptr) {
        api_.aclFinalize();
    }
    aclInitialized_ = false;

    inputSizes_.clear();
    outputSizes_.clear();
    runMode_ = ACL_HOST;
    remoteMode_ = false;
    runtimePath_.clear();
    api_.Unload();
}

void YoloEngine::Release()
{
    std::lock_guard<std::mutex> lock(mutex_);
    CleanupLocked();
}

YoloModelInfo YoloEngine::GetInfo() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    YoloModelInfo info;
    info.initialized = modelLoaded_ && (remoteMode_ || modelDesc_ != nullptr);
    info.deviceId = deviceId_;
    info.runMode = info.initialized ? static_cast<int32_t>(runMode_) : -1;
    info.runtimePath = remoteMode_ ? runtimePath_ : api_.LibraryPath();
    info.lastError = lastError_.empty() ? api_.LastError() : lastError_;
    info.inputSizes = inputSizes_;
    info.outputSizes = outputSizes_;
    return info;
}
