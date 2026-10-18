#include "yolo_engine.h"
#include "yolo_live_napi.h"

#include <hilog/log.h>
#include <napi/native_api.h>
#include <rawfile/raw_file.h>
#include <rawfile/raw_file_manager.h>

#include <chrono>
#include <cstring>
#include <limits>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#undef LOG_TAG
#undef LOG_DOMAIN
#define LOG_TAG "YoloNapi"
#define LOG_DOMAIN 0xFF00

namespace {

std::vector<uint8_t> ReadRawFile(napi_env env, napi_value resourceManager,
                                 const std::string &fileName, std::string &error)
{
    NativeResourceManager *manager = OH_ResourceManager_InitNativeResourceManager(env, resourceManager);
    if (manager == nullptr) {
        error = "failed to initialize NativeResourceManager";
        return {};
    }

    RawFile *rawFile = OH_ResourceManager_OpenRawFile(manager, fileName.c_str());
    if (rawFile == nullptr) {
        error = "rawfile not found: " + fileName;
        OH_ResourceManager_ReleaseNativeResourceManager(manager);
        return {};
    }

    const int64_t fileSize = OH_ResourceManager_GetRawFileSize(rawFile);
    if (fileSize <= 0) {
        error = "rawfile is empty: " + fileName;
        OH_ResourceManager_CloseRawFile(rawFile);
        OH_ResourceManager_ReleaseNativeResourceManager(manager);
        return {};
    }

    std::vector<uint8_t> bytes(static_cast<size_t>(fileSize));
    const int64_t readSize = OH_ResourceManager_ReadRawFile(rawFile, bytes.data(), bytes.size());
    OH_ResourceManager_CloseRawFile(rawFile);
    OH_ResourceManager_ReleaseNativeResourceManager(manager);
    if (readSize != fileSize) {
        error = "failed to read complete rawfile: " + fileName;
        return {};
    }
    return bytes;
}

bool GetString(napi_env env, napi_value value, std::string &result)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) return false;
    std::vector<char> buffer(length + 1, '\0');
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &length) != napi_ok) return false;
    result.assign(buffer.data(), length);
    return true;
}

napi_value MakeBoolean(napi_env env, bool value)
{
    napi_value result = nullptr;
    napi_get_boolean(env, value, &result);
    return result;
}

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

napi_value SizeVectorToArray(napi_env env, const std::vector<size_t> &sizes)
{
    napi_value result = nullptr;
    napi_create_array_with_length(env, sizes.size(), &result);
    for (size_t i = 0; i < sizes.size(); ++i) {
        napi_value value = nullptr;
        napi_create_double(env, static_cast<double>(sizes[i]), &value);
        napi_set_element(env, result, i, value);
    }
    return result;
}

napi_value InitModel(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        napi_throw_type_error(env, nullptr, "initModel(resourceManager, rawfileName, deviceId?) requires two arguments");
        return nullptr;
    }

    std::string rawfileName;
    if (!GetString(env, args[1], rawfileName)) {
        napi_throw_type_error(env, nullptr, "rawfileName must be a string");
        return nullptr;
    }
    int32_t deviceId = 0;
    if (argc >= 3 && napi_get_value_int32(env, args[2], &deviceId) != napi_ok) {
        napi_throw_type_error(env, nullptr, "deviceId must be an integer");
        return nullptr;
    }

    std::string readError;
    std::vector<uint8_t> model = ReadRawFile(env, args[0], rawfileName, readError);
    if (model.empty()) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "%{public}s", readError.c_str());
        return MakeBoolean(env, false);
    }
    return MakeBoolean(env, YoloEngine::Instance().Initialize(model.data(), model.size(), deviceId));
}

struct InitTask {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::vector<uint8_t> model;
    int32_t deviceId = 0;
    bool initialized = false;
    std::string error;
};

std::mutex g_initMutex;

void ExecuteInit(napi_env env, void *data)
{
    (void)env;
    auto *task = static_cast<InitTask *>(data);
    std::lock_guard<std::mutex> lock(g_initMutex);

    // The home page and live-camera page can request initialization at almost
    // the same time. Reuse the model loaded by the first background task.
    if (YoloEngine::Instance().GetInfo().initialized) {
        task->initialized = true;
        return;
    }

    task->initialized = YoloEngine::Instance().Initialize(
        task->model.data(), task->model.size(), task->deviceId);
    if (!task->initialized) {
        task->error = YoloEngine::Instance().GetInfo().lastError;
        if (task->error.empty()) task->error = "YOLO model initialization failed";
    }
}

void CompleteInit(napi_env env, napi_status status, void *data)
{
    auto *task = static_cast<InitTask *>(data);
    if (status != napi_ok || !task->error.empty()) {
        const std::string message = task->error.empty()
            ? "NAPI async model initialization failed" : task->error;
        napi_value errorMessage = MakeString(env, message);
        napi_value errorObject = nullptr;
        napi_create_error(env, nullptr, errorMessage, &errorObject);
        napi_reject_deferred(env, task->deferred, errorObject);
    } else {
        napi_resolve_deferred(env, task->deferred, MakeBoolean(env, task->initialized));
    }

    napi_delete_async_work(env, task->work);
    delete task;
}

napi_value InitModelAsync(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        napi_throw_type_error(env, nullptr,
            "initModelAsync(resourceManager, rawfileName, deviceId?) requires two arguments");
        return nullptr;
    }

    std::string rawfileName;
    if (!GetString(env, args[1], rawfileName)) {
        napi_throw_type_error(env, nullptr, "rawfileName must be a string");
        return nullptr;
    }

    int32_t deviceId = 0;
    if (argc >= 3 && napi_get_value_int32(env, args[2], &deviceId) != napi_ok) {
        napi_throw_type_error(env, nullptr, "deviceId must be an integer");
        return nullptr;
    }

    std::string readError;
    std::vector<uint8_t> model = ReadRawFile(env, args[0], rawfileName, readError);
    if (model.empty()) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "%{public}s", readError.c_str());
        napi_throw_error(env, nullptr, readError.c_str());
        return nullptr;
    }

    auto *task = new InitTask();
    task->model = std::move(model);
    task->deviceId = deviceId;

    napi_value promise = nullptr;
    napi_create_promise(env, &task->deferred, &promise);
    napi_value resourceName = MakeString(env, "YoloAscendInitialization");
    if (napi_create_async_work(env, nullptr, resourceName, ExecuteInit, CompleteInit,
                               task, &task->work) != napi_ok ||
        napi_queue_async_work(env, task->work) != napi_ok) {
        napi_value errorMessage = MakeString(env, "failed to queue NAPI model initialization work");
        napi_value errorObject = nullptr;
        napi_create_error(env, nullptr, errorMessage, &errorObject);
        napi_reject_deferred(env, task->deferred, errorObject);
        if (task->work != nullptr) napi_delete_async_work(env, task->work);
        delete task;
    }
    return promise;
}

napi_value GetModelInfo(napi_env env, napi_callback_info info)
{
    (void)info;
    YoloModelInfo infoValue = YoloEngine::Instance().GetInfo();
    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamed(env, result, "initialized", MakeBoolean(env, infoValue.initialized));

    napi_value deviceId = nullptr;
    napi_create_int32(env, infoValue.deviceId, &deviceId);
    SetNamed(env, result, "deviceId", deviceId);

    napi_value runMode = nullptr;
    napi_create_int32(env, infoValue.runMode, &runMode);
    SetNamed(env, result, "runMode", runMode);
    SetNamed(env, result, "runtimePath", MakeString(env, infoValue.runtimePath));
    SetNamed(env, result, "lastError", MakeString(env, infoValue.lastError));
    SetNamed(env, result, "inputByteSizes", SizeVectorToArray(env, infoValue.inputSizes));
    SetNamed(env, result, "outputByteSizes", SizeVectorToArray(env, infoValue.outputSizes));
    return result;
}

struct InferTask {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::vector<uint8_t> input;
    std::vector<std::vector<uint8_t>> outputs;
    double latencyMs = 0.0;
    std::string error;
};

void ExecuteInfer(napi_env env, void *data)
{
    (void)env;
    auto *task = static_cast<InferTask *>(data);
    if (!YoloEngine::Instance().Infer(task->input.data(), task->input.size(),
                                      task->outputs, task->latencyMs)) {
        task->error = YoloEngine::Instance().GetInfo().lastError;
        if (task->error.empty()) task->error = "AscendCL inference failed";
    }
}

void CompleteInfer(napi_env env, napi_status status, void *data)
{
    auto *task = static_cast<InferTask *>(data);
    if (status != napi_ok || !task->error.empty()) {
        std::string message = task->error.empty() ? "NAPI async inference failed" : task->error;
        napi_value errorMessage = MakeString(env, message);
        napi_value errorObject = nullptr;
        napi_create_error(env, nullptr, errorMessage, &errorObject);
        napi_reject_deferred(env, task->deferred, errorObject);
    } else {
        napi_value result = nullptr;
        napi_create_object(env, &result);
        SetNamed(env, result, "success", MakeBoolean(env, true));

        napi_value latency = nullptr;
        napi_create_double(env, task->latencyMs, &latency);
        SetNamed(env, result, "latencyMs", latency);

        napi_value outputs = nullptr;
        napi_create_array_with_length(env, task->outputs.size(), &outputs);
        for (size_t i = 0; i < task->outputs.size(); ++i) {
            napi_value tensor = nullptr;
            napi_create_object(env, &tensor);
            napi_value index = nullptr;
            napi_create_uint32(env, static_cast<uint32_t>(i), &index);
            SetNamed(env, tensor, "index", index);

            napi_value byteLength = nullptr;
            napi_create_double(env, static_cast<double>(task->outputs[i].size()), &byteLength);
            SetNamed(env, tensor, "byteLength", byteLength);

            void *arrayData = nullptr;
            napi_value arrayBuffer = nullptr;
            napi_create_arraybuffer(env, task->outputs[i].size(), &arrayData, &arrayBuffer);
            if (!task->outputs[i].empty()) {
                std::memcpy(arrayData, task->outputs[i].data(), task->outputs[i].size());
            }
            napi_value byteArray = nullptr;
            napi_create_typedarray(env, napi_uint8_array, task->outputs[i].size(),
                                   arrayBuffer, 0, &byteArray);
            SetNamed(env, tensor, "data", byteArray);
            napi_set_element(env, outputs, i, tensor);
        }
        SetNamed(env, result, "outputs", outputs);
        napi_resolve_deferred(env, task->deferred, result);
    }

    napi_delete_async_work(env, task->work);
    delete task;
}

napi_value Infer(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        napi_throw_type_error(env, nullptr, "infer(input) requires a Float32Array");
        return nullptr;
    }

    napi_typedarray_type arrayType;
    size_t elementCount = 0;
    void *arrayData = nullptr;
    napi_value arrayBuffer = nullptr;
    size_t byteOffset = 0;
    if (napi_get_typedarray_info(env, args[0], &arrayType, &elementCount, &arrayData,
                                 &arrayBuffer, &byteOffset) != napi_ok ||
        arrayType != napi_float32_array || arrayData == nullptr) {
        napi_throw_type_error(env, nullptr, "input must be a Float32Array in NCHW layout");
        return nullptr;
    }

    void *bufferData = nullptr;
    size_t bufferByteLength = 0;
    if (napi_get_arraybuffer_info(env, arrayBuffer, &bufferData, &bufferByteLength) != napi_ok ||
        byteOffset > bufferByteLength) {
        napi_throw_type_error(env, nullptr, "unable to inspect Float32Array backing buffer");
        return nullptr;
    }

    // OpenHarmony API levels in the field differ here: some report element
    // count, while this board reports the typed view length in bytes. Resolve
    // both forms against the model's expected byte size and backing buffer.
    const size_t availableBytes = bufferByteLength - byteOffset;
    const YoloModelInfo modelInfo = YoloEngine::Instance().GetInfo();
    const size_t expectedBytes = modelInfo.inputSizes.empty() ? 0 : modelInfo.inputSizes[0];
    size_t byteLength = 0;
    if (expectedBytes > 0 && availableBytes >= expectedBytes &&
        (elementCount == expectedBytes ||
         (elementCount <= std::numeric_limits<size_t>::max() / sizeof(float) &&
          elementCount * sizeof(float) == expectedBytes) ||
         availableBytes == expectedBytes)) {
        byteLength = expectedBytes;
    } else if (elementCount <= std::numeric_limits<size_t>::max() / sizeof(float) &&
               elementCount * sizeof(float) <= availableBytes) {
        byteLength = elementCount * sizeof(float);
    } else if (elementCount <= availableBytes) {
        byteLength = elementCount;
    } else {
        napi_throw_range_error(env, nullptr, "Float32Array length exceeds its backing buffer");
        return nullptr;
    }

    auto *task = new InferTask();
    task->input.resize(byteLength);
    std::memcpy(task->input.data(), arrayData, byteLength);

    napi_value promise = nullptr;
    napi_create_promise(env, &task->deferred, &promise);
    napi_value resourceName = MakeString(env, "YoloAscendInference");
    if (napi_create_async_work(env, nullptr, resourceName, ExecuteInfer, CompleteInfer,
                               task, &task->work) != napi_ok ||
        napi_queue_async_work(env, task->work) != napi_ok) {
        napi_value errorMessage = MakeString(env, "failed to queue NAPI inference work");
        napi_value errorObject = nullptr;
        napi_create_error(env, nullptr, errorMessage, &errorObject);
        napi_reject_deferred(env, task->deferred, errorObject);
        if (task->work != nullptr) napi_delete_async_work(env, task->work);
        delete task;
    }
    return promise;
}

napi_value ReleaseModel(napi_env env, napi_callback_info info)
{
    (void)info;
    YoloEngine::Instance().Release();
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor properties[] = {
        {"initModel", nullptr, InitModel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"initModelAsync", nullptr, InitModelAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getModelInfo", nullptr, GetModelInfo, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"infer", nullptr, Infer, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"inferPixelMap", nullptr, InferPixelMap, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"inferYuv420", nullptr, InferYuv420, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"releaseModel", nullptr, ReleaseModel, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    return exports;
}
EXTERN_C_END

static napi_module yoloModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "yolo_napi",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterYoloNapiModule()
{
    napi_module_register(&yoloModule);
}
