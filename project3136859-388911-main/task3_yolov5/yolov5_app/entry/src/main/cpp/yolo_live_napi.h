#ifndef YOLO_NAPI_YOLO_LIVE_NAPI_H
#define YOLO_NAPI_YOLO_LIVE_NAPI_H

#include <napi/native_api.h>

napi_value InferPixelMap(napi_env env, napi_callback_info info);
napi_value InferYuv420(napi_env env, napi_callback_info info);

#endif // YOLO_NAPI_YOLO_LIVE_NAPI_H
