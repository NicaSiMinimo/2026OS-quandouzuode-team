#ifndef YOLO_NAPI_ASCEND_CL_API_H
#define YOLO_NAPI_ASCEND_CL_API_H

#include <cstddef>
#include <cstdint>
#include <string>

// The CANN SDK is installed on the target board, not on the DevEco Studio host.
// Keep the build independent from proprietary headers and resolve the small ACL
// ABI surface used by this module at runtime.
using aclError = int32_t;
using aclrtContext = void *;

struct aclmdlDesc;
struct aclmdlDataset;
struct aclDataBuffer;

enum aclrtRunMode : int32_t {
    ACL_HOST = 0,
    ACL_DEVICE = 1,
};

enum aclrtMemMallocPolicy : int32_t {
    ACL_MEM_MALLOC_HUGE_FIRST = 0,
    ACL_MEM_MALLOC_HUGE_ONLY = 1,
    ACL_MEM_MALLOC_NORMAL_ONLY = 2,
};

enum aclrtMemcpyKind : int32_t {
    ACL_MEMCPY_HOST_TO_HOST = 0,
    ACL_MEMCPY_HOST_TO_DEVICE = 1,
    ACL_MEMCPY_DEVICE_TO_HOST = 2,
    ACL_MEMCPY_DEVICE_TO_DEVICE = 3,
};

constexpr aclError ACL_SUCCESS = 0;

class AscendClApi {
public:
    bool Load();
    void Unload();
    bool IsLoaded() const { return handle_ != nullptr; }
    const std::string &LibraryPath() const { return libraryPath_; }
    const std::string &LastError() const { return lastError_; }
    std::string RecentAclError() const;

    aclError (*aclInit)(const char *configPath) = nullptr;
    aclError (*aclFinalize)() = nullptr;
    const char *(*aclGetRecentErrMsg)() = nullptr;

    aclError (*aclrtSetDevice)(int32_t deviceId) = nullptr;
    aclError (*aclrtResetDevice)(int32_t deviceId) = nullptr;
    aclError (*aclrtCreateContext)(aclrtContext *context, int32_t deviceId) = nullptr;
    aclError (*aclrtDestroyContext)(aclrtContext context) = nullptr;
    aclError (*aclrtSetCurrentContext)(aclrtContext context) = nullptr;
    aclError (*aclrtGetRunMode)(aclrtRunMode *runMode) = nullptr;
    aclError (*aclrtMalloc)(void **devicePtr, size_t size, aclrtMemMallocPolicy policy) = nullptr;
    aclError (*aclrtFree)(void *devicePtr) = nullptr;
    aclError (*aclrtMemcpy)(void *dst, size_t dstMax, const void *src, size_t count,
                            aclrtMemcpyKind kind) = nullptr;

    aclError (*aclmdlLoadFromMem)(const void *model, size_t modelSize, uint32_t *modelId) = nullptr;
    aclError (*aclmdlUnload)(uint32_t modelId) = nullptr;
    aclmdlDesc *(*aclmdlCreateDesc)() = nullptr;
    aclError (*aclmdlDestroyDesc)(aclmdlDesc *modelDesc) = nullptr;
    aclError (*aclmdlGetDesc)(aclmdlDesc *modelDesc, uint32_t modelId) = nullptr;
    size_t (*aclmdlGetNumInputs)(const aclmdlDesc *modelDesc) = nullptr;
    size_t (*aclmdlGetNumOutputs)(const aclmdlDesc *modelDesc) = nullptr;
    size_t (*aclmdlGetInputSizeByIndex)(const aclmdlDesc *modelDesc, size_t index) = nullptr;
    size_t (*aclmdlGetOutputSizeByIndex)(const aclmdlDesc *modelDesc, size_t index) = nullptr;
    aclmdlDataset *(*aclmdlCreateDataset)() = nullptr;
    aclError (*aclmdlDestroyDataset)(const aclmdlDataset *dataset) = nullptr;
    aclError (*aclmdlAddDatasetBuffer)(aclmdlDataset *dataset, aclDataBuffer *dataBuffer) = nullptr;
    aclError (*aclmdlExecute)(uint32_t modelId, const aclmdlDataset *input, aclmdlDataset *output) = nullptr;
    aclDataBuffer *(*aclCreateDataBuffer)(void *data, size_t size) = nullptr;
    aclError (*aclDestroyDataBuffer)(const aclDataBuffer *dataBuffer) = nullptr;

private:
    template<typename T>
    bool Resolve(T &target, const char *symbolName);

    void *handle_ = nullptr;
    std::string libraryPath_;
    std::string lastError_;
};

#endif // YOLO_NAPI_ASCEND_CL_API_H
