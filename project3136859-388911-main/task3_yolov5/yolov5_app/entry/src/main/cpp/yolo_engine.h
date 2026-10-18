#ifndef YOLO_NAPI_YOLO_ENGINE_H
#define YOLO_NAPI_YOLO_ENGINE_H

#include "ascend_cl_api.h"

#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

struct YoloModelInfo {
    bool initialized = false;
    int32_t deviceId = 0;
    int32_t runMode = -1;
    std::string runtimePath;
    std::string lastError;
    std::vector<size_t> inputSizes;
    std::vector<size_t> outputSizes;
};

struct YoloDetectionBox {
    float x1 = 0.0F;
    float y1 = 0.0F;
    float x2 = 0.0F;
    float y2 = 0.0F;
    float score = 0.0F;
    int32_t classId = 0;
};

class YoloEngine {
public:
    static YoloEngine &Instance();

    bool Initialize(const uint8_t *modelData, size_t modelSize, int32_t deviceId);
    bool Infer(const uint8_t *inputData, size_t inputSize,
               std::vector<std::vector<uint8_t>> &outputs, double &latencyMs);
    bool InferRemoteDetections(const uint8_t *inputData, size_t inputSize,
                               float confidenceThreshold, float iouThreshold,
                               std::vector<YoloDetectionBox> &detections,
                               double &latencyMs);
    bool InferRemoteDetectionsUint8(const uint8_t *inputData, size_t inputSize,
                                    float confidenceThreshold, float iouThreshold,
                                    std::vector<YoloDetectionBox> &detections,
                                    double &latencyMs);
    void Release();
    YoloModelInfo GetInfo() const;

private:
    YoloEngine() = default;
    ~YoloEngine();
    YoloEngine(const YoloEngine &) = delete;
    YoloEngine &operator=(const YoloEngine &) = delete;

    bool AllocateDatasetsLocked();
    bool AddBufferLocked(aclmdlDataset *dataset, size_t size, bool input);
    bool InitializeRemoteLocked(const uint8_t *modelData, size_t modelSize, int32_t deviceId);
    bool InferRemoteLocked(const uint8_t *inputData, size_t inputSize,
                           std::vector<std::vector<uint8_t>> &outputs, double &latencyMs);
    bool InferRemoteDetectionsLocked(const uint8_t *inputData, size_t inputSize,
                                     float confidenceThreshold, float iouThreshold,
                                     std::vector<YoloDetectionBox> &detections,
                                     double &latencyMs);
    bool InferRemoteDetectionCommandLocked(uint16_t command,
                                           const uint8_t *inputData, size_t inputSize,
                                           float confidenceThreshold, float iouThreshold,
                                           std::vector<YoloDetectionBox> &detections,
                                           double &latencyMs);
    bool RemoteRequestLocked(uint16_t command, const uint8_t *payload, size_t payloadSize,
                             std::vector<uint8_t> &response, std::string &error) const;
    bool ParseRemoteInfoLocked(const std::vector<uint8_t> &payload);
    void CleanupLocked();
    bool CheckAclLocked(aclError code, const char *operation);
    void SetErrorLocked(const std::string &message);

    mutable std::mutex mutex_;
    AscendClApi api_;
    bool aclInitialized_ = false;
    bool deviceSet_ = false;
    bool modelLoaded_ = false;
    int32_t deviceId_ = 0;
    aclrtRunMode runMode_ = ACL_HOST;
    aclrtContext context_ = nullptr;
    uint32_t modelId_ = 0;
    aclmdlDesc *modelDesc_ = nullptr;
    aclmdlDataset *inputDataset_ = nullptr;
    aclmdlDataset *outputDataset_ = nullptr;
    std::vector<void *> inputDeviceBuffers_;
    std::vector<void *> outputDeviceBuffers_;
    std::vector<aclDataBuffer *> inputDataBuffers_;
    std::vector<aclDataBuffer *> outputDataBuffers_;
    std::vector<size_t> inputSizes_;
    std::vector<size_t> outputSizes_;
    bool remoteMode_ = false;
    std::string runtimePath_;
    std::string lastError_;
};

#endif // YOLO_NAPI_YOLO_ENGINE_H
