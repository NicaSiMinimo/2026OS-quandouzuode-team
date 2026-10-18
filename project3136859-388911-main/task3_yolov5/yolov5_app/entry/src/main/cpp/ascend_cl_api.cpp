#include "ascend_cl_api.h"

#include <dlfcn.h>

#include <array>

template<typename T>
bool AscendClApi::Resolve(T &target, const char *symbolName)
{
    dlerror();
    target = reinterpret_cast<T>(dlsym(handle_, symbolName));
    const char *error = dlerror();
    if (target == nullptr || error != nullptr) {
        lastError_ = std::string("missing AscendCL symbol ") + symbolName;
        if (error != nullptr) {
            lastError_ += ": ";
            lastError_ += error;
        }
        return false;
    }
    return true;
}

bool AscendClApi::Load()
{
    if (handle_ != nullptr) {
        return true;
    }

    // The first candidate honors a board-wide loader configuration. Absolute
    // paths cover the layouts installed by task2_cann/03_set_cann_env.sh.
    constexpr std::array<const char *, 7> candidates = {
        "libascendcl.so",
        "/usr/local/Ascend/8.2.RC1/lib64/libascendcl.so",
        "/usr/local/Ascend/latest/lib64/libascendcl.so",
        "/usr/local/Ascend/ascend-toolkit/latest/lib64/libascendcl.so",
        "/usr/local/Ascend/driver/lib64/libascendcl.so",
        "/usr/local/Ascend/driver/lib64/common/libascendcl.so",
        "/usr/local/Ascend/driver/lib64/driver/libascendcl.so",
    };

    std::string loaderErrors;
    for (const char *candidate : candidates) {
        dlerror();
        handle_ = dlopen(candidate, RTLD_NOW | RTLD_GLOBAL);
        if (handle_ != nullptr) {
            libraryPath_ = candidate;
            break;
        }
        const char *error = dlerror();
        if (error != nullptr) {
            if (!loaderErrors.empty()) loaderErrors += " | ";
            loaderErrors += candidate;
            loaderErrors += ": ";
            loaderErrors += error;
        }
    }

    if (handle_ == nullptr) {
        lastError_ = "unable to load libascendcl.so";
        if (!loaderErrors.empty()) {
            lastError_ += ": ";
            lastError_ += loaderErrors;
        }
        return false;
    }

#define RESOLVE_REQUIRED(member) \
    do { if (!Resolve(member, #member)) { Unload(); return false; } } while (false)
    RESOLVE_REQUIRED(aclInit);
    RESOLVE_REQUIRED(aclFinalize);
    RESOLVE_REQUIRED(aclrtSetDevice);
    RESOLVE_REQUIRED(aclrtResetDevice);
    RESOLVE_REQUIRED(aclrtCreateContext);
    RESOLVE_REQUIRED(aclrtDestroyContext);
    RESOLVE_REQUIRED(aclrtSetCurrentContext);
    RESOLVE_REQUIRED(aclrtGetRunMode);
    RESOLVE_REQUIRED(aclrtMalloc);
    RESOLVE_REQUIRED(aclrtFree);
    RESOLVE_REQUIRED(aclrtMemcpy);
    RESOLVE_REQUIRED(aclmdlLoadFromMem);
    RESOLVE_REQUIRED(aclmdlUnload);
    RESOLVE_REQUIRED(aclmdlCreateDesc);
    RESOLVE_REQUIRED(aclmdlDestroyDesc);
    RESOLVE_REQUIRED(aclmdlGetDesc);
    RESOLVE_REQUIRED(aclmdlGetNumInputs);
    RESOLVE_REQUIRED(aclmdlGetNumOutputs);
    RESOLVE_REQUIRED(aclmdlGetInputSizeByIndex);
    RESOLVE_REQUIRED(aclmdlGetOutputSizeByIndex);
    RESOLVE_REQUIRED(aclmdlCreateDataset);
    RESOLVE_REQUIRED(aclmdlDestroyDataset);
    RESOLVE_REQUIRED(aclmdlAddDatasetBuffer);
    RESOLVE_REQUIRED(aclmdlExecute);
    RESOLVE_REQUIRED(aclCreateDataBuffer);
    RESOLVE_REQUIRED(aclDestroyDataBuffer);
#undef RESOLVE_REQUIRED

    // Diagnostic-only API. It is optional on older runtime builds.
    dlerror();
    aclGetRecentErrMsg = reinterpret_cast<decltype(aclGetRecentErrMsg)>(
        dlsym(handle_, "aclGetRecentErrMsg"));
    dlerror();

    lastError_.clear();
    return true;
}

void AscendClApi::Unload()
{
    if (handle_ != nullptr) {
        dlclose(handle_);
    }
    handle_ = nullptr;
    libraryPath_.clear();

    aclInit = nullptr;
    aclFinalize = nullptr;
    aclGetRecentErrMsg = nullptr;
    aclrtSetDevice = nullptr;
    aclrtResetDevice = nullptr;
    aclrtCreateContext = nullptr;
    aclrtDestroyContext = nullptr;
    aclrtSetCurrentContext = nullptr;
    aclrtGetRunMode = nullptr;
    aclrtMalloc = nullptr;
    aclrtFree = nullptr;
    aclrtMemcpy = nullptr;
    aclmdlLoadFromMem = nullptr;
    aclmdlUnload = nullptr;
    aclmdlCreateDesc = nullptr;
    aclmdlDestroyDesc = nullptr;
    aclmdlGetDesc = nullptr;
    aclmdlGetNumInputs = nullptr;
    aclmdlGetNumOutputs = nullptr;
    aclmdlGetInputSizeByIndex = nullptr;
    aclmdlGetOutputSizeByIndex = nullptr;
    aclmdlCreateDataset = nullptr;
    aclmdlDestroyDataset = nullptr;
    aclmdlAddDatasetBuffer = nullptr;
    aclmdlExecute = nullptr;
    aclCreateDataBuffer = nullptr;
    aclDestroyDataBuffer = nullptr;
}

std::string AscendClApi::RecentAclError() const
{
    if (aclGetRecentErrMsg == nullptr) {
        return {};
    }
    const char *message = aclGetRecentErrMsg();
    return message == nullptr ? std::string() : std::string(message);
}
