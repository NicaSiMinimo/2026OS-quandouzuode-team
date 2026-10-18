cmake_minimum_required(VERSION 3.5.0)
project(yolo_napi)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# The application uses the OpenHarmony/musl toolchain.  The board's CANN
# runtime is a separate glibc process, so direct AscendCL loading is opt-in
# only for a toolchain/runtime combination that has been validated together.
option(YOLO_ENABLE_DIRECT_ACL "Enable the unsupported in-process CANN fallback" OFF)

add_library(yolo_napi SHARED
    ascend_cl_api.cpp
    yolo_engine.cpp
    yolo_live_napi.cpp
    yolo_napi.cpp
)

target_include_directories(yolo_napi PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

if (YOLO_ENABLE_DIRECT_ACL)
    target_compile_definitions(yolo_napi PRIVATE YOLO_ENABLE_DIRECT_ACL=1)
else()
    target_compile_definitions(yolo_napi PRIVATE YOLO_ENABLE_DIRECT_ACL=0)
endif()

target_link_libraries(yolo_napi PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    librawfile.z.so
    libpixelmap_ndk.z.so
    libdl.so
)
