# OpenHarmony 310B 移植补丁集

本目录包含将 **OpenHarmony 5.0.3** 移植到 **Ascend 310B** 开发板所需的全部补丁，同时集成了 **CANN 推理引擎** 和 **YOLOv5 目标检测服务** 的框架支持。所有补丁均基于 `OpenHarmony-5.0.3-Release` 分支（动态分支）制作，用于修复编译错误、添加设备配置、集成 AI 推理应用。

------

## 目录结构

```
task1_transplantation/
├── device-board-ascend-310B-BUILD.gn.patch                           # 添加 yolov5 模块编译依赖
├── device-board-ascend-310B-cfg-BUILD.gn.patch                     # 添加网络/环境/5000/5001服务配置文件
├── device-board-ascend-310B-cfg-init.310B.cfg.patch                # 修改 init.cfg，增加网络、环境、YOLOv5 服务
├── device-board-ascend-310B-cfg-init.310B.yolov5.cfg.patch         # 新增 YOLOv5 服务定义
├── device-board-ascend-310B-cfg-init.310B.yolov5-yolo_acl.patch    # 增加 5001 本机 NAPI 服务
├── device-board-ascend-310B-cfg-BUILD-yolo_acl.patch               # 安装 5001 服务文件
├── device-board-ascend-310B-cfg-setup_ascend_env.sh.patch          # 设置 CANN 环境变量脚本
├── device-board-ascend-310B-cfg-setup_network.sh.patch             # 配置网络（eth1 固定 IP）
├── device-board-ascend-310B-cfg-start_yolov5_server.sh.patch       # 启动 YOLOv5 服务脚本
├── device-board-ascend-310B-yolov5-BUILD.gn.patch                  # yolov5 模块构建文件
├── device-board-ascend-310B-yolov5-main.py.patch                   # YOLOv5 推理主程序（支持 OM/ONNX）
├── device-board-ascend-310B-yolov5-server.py.patch                 # HTTP 服务端（接收图片、执行推理、返回结果）
├── device-soc-ascend-310B-hardware-display-src-display_device-drm_connector.cpp.patch  # 修复 EDID/模式/CRTC 选择
└── patch_fix/
    ├── foundation-multimedia-image_effect-frameworks-native-render_environment-graphic-gl_utils.cpp.patch  # 修复 EGL 函数动态加载
    └── openharmony-5.0.3-build-fixes.patch                         # 修复 OHOS 4000/Ninja 构建问题
```

------

## 补丁功能说明

| 补丁文件                                                     | 作用                                                         |
| :----------------------------------------------------------- | :----------------------------------------------------------- |
| `device-board-ascend-310B-BUILD.gn.patch`                    | 在 `device/board/ascend/310B/BUILD.gn` 中添加 `yolov5:yolov5_files` 依赖，使编译系统包含 YOLOv5 相关文件。 |
| `device-board-ascend-310B-cfg-BUILD.gn.patch`                | 添加网络、CANN 环境、兼容 5000 服务以及 5001 NAPI 服务的安装目标，确保 init 配置和服务脚本进入 `/vendor/etc`。 |
| `device-board-ascend-310B-cfg-init.310B.cfg.patch`           | 扩展 `init.cfg`： - 添加网络配置（`eth1` 固定 IP 192.168.137.100） - 设置 CANN 环境变量（写入 `/etc/profile.d/ascend.sh`） - 创建 `/task3_app` 目录结构 - 复制 `server.py` 和 `main.py` 到 `/task3_app/server` |
| `device-board-ascend-310B-cfg-init.310B.yolov5.cfg.patch`    | 新增兼容图片服务 `yolov5_server` 和本机 `yolo_acl_service`（127.0.0.1:5001）两个独立服务。 |
| `device-board-ascend-310B-cfg-init.310B.yolov5-yolo_acl.patch` | 对已有 init 配置补充 `yolo_acl_service`，兼容已经应用旧补丁的源码树。 |
| `device-board-ascend-310B-cfg-BUILD-yolo_acl.patch`           | 对已有 cfg 构建目标补充 `run_yolo_acl_service.sh` 和 `yolo_acl_service.py`。 |
| `device-board-ascend-310B-cfg-setup_network.sh.patch`        | 配置网络接口：关闭无关网卡，设置 `eth1` IP 为 `192.168.137.100`，添加路由和 DNS。 |
| `device-board-ascend-310B-cfg-setup_ascend_env.sh.patch`     | 将 CANN 所需的环境变量（`LD_LIBRARY_PATH`、`PATH`、`PYTHONPATH` 等）写入 `/etc/profile.d/ascend.sh`。 |
| `device-board-ascend-310B-cfg-start_yolov5_server.sh.patch`  | 等待 `/task3_app/.deployed` 文件出现（表示系统部署完成），然后加载 CANN 环境并启动 `server.py`。 |
| `device-board-ascend-310B-yolov5-BUILD.gn.patch`             | 定义 `ohos_prebuilt_etc` 规则，将 `main.py` 和 `server.py` 打包到系统 `/system/etc/yolov5/` 目录。 |
| `device-board-ascend-310B-yolov5-main.py.patch`              | 完整的 YOLOv5 推理程序，支持 `ais_bench`（Ascend OM 模型）和 ONNX Runtime 后端，包含预处理、后处理、NMS、绘图等功能。 |
| `device-board-ascend-310B-yolov5-server.py.patch`            | 基于 Python `http.server` 的 HTTP 服务，提供 `/upload`（上传图片）、`/start`（开始识别）、`/progress`（查询进度）、`/results`（获取结果）等 API，支持将结果保存到长期存储。 |
| `device-soc-ascend-310B-hardware-display-src-display_device-drm_connector.cpp.patch` | 修复显示模块的真实 EDID 校验、内核模式选择、热插拔资源释放和同一 CRTC 绑定；不再伪造 1080p。 |
| `patch_fix/foundation-multimedia-image_effect-...-gl_utils.cpp.patch` | 修复 `image_effect` 组件中 EGL 扩展函数（`glEGLImageTargetTexture2DOES`、`eglCreateImageKHR`）的符号未定义问题，通过 `eglGetProcAddress` 动态获取。 |
| `patch_fix/openharmony-5.0.3-build-fixes.patch` | 修复音频策略条件编译、GN/Ninja 重复输出、BPF action 返回值，以及 Account/KV Store/Rosen/AV Codec 测试 target 名称冲突。 |

------

## 使用方法

### 1. 准备 OpenHarmony 源码

按照 [官方文档](https://gitcode.com/openharmony/docs/blob/weekly_20250414/zh-cn/device-dev/subsystems/subsys-build-all.md) 下载 `OpenHarmony-5.0.3-Release` 分支源码：

```
repo init -u git@gitee.com:openharmony/manifest.git -b OpenHarmony-5.0.3-Release --no-repo-verify
repo sync -c
repo forall -c 'git lfs pull'
```

源码下载完成后，进入源码目录，执行一下命令，下载预编译文件：

```
cd build
./prebuilts_download.sh
```

预编译文件下载完成之后，按照教程赛题教程，整合官方源码和杰创科技的厂商源码。

### 2. 应用补丁

所有补丁均以 **OpenHarmony 源码根目录** 为基准，使用 `patch` 命令逐一应用。建议按如下顺序操作：

```
cd /path/to/openharmony  # 源码根目录

# 应用 board 层补丁
patch -p1 < /path/to/task1_transplantation/device-board-ascend-310B-BUILD.gn.patch
patch -p1 < /path/to/task1_transplantation/device-board-ascend-310B-cfg-BUILD.gn.patch
patch -p1 < /path/to/task1_transplantation/device-board-ascend-310B-cfg-init.310B.cfg.patch
patch -p1 < /path/to/task1_transplantation/device-board-ascend-310B-cfg-init.310B.yolov5.cfg.patch
patch -p1 < /path/to/task1_transplantation/device-board-ascend-310B-cfg-setup_ascend_env.sh.patch
patch -p1 < /path/to/task1_transplantation/device-board-ascend-310B-cfg-setup_network.sh.patch
patch -p1 < /path/to/task1_transplantation/device-board-ascend-310B-cfg-start_yolov5_server.sh.patch
patch -p1 < /path/to/task1_transplantation/device-board-ascend-310B-yolov5-BUILD.gn.patch
patch -p1 < /path/to/task1_transplantation/device-board-ascend-310B-yolov5-main.py.patch
patch -p1 < /path/to/task1_transplantation/device-board-ascend-310B-yolov5-server.py.patch

# 应用 soc 层补丁
patch -p1 < /path/to/task1_transplantation/device-soc-ascend-310B-hardware-display-src-display_device-drm_connector.cpp.patch

# 应用 foundation 补丁（修复 image_effect）
patch -p1 < /path/to/task1_transplantation/patch_fix/foundation-multimedia-image_effect-...-gl_utils.cpp.patch
```

> **注意**：如果某些补丁因行号偏移失败，可使用 `--fuzz=3` 或手动调整，或参考各补丁文件中的上下文手动修改。

`scripts/apply_patches.sh` 在应用补丁后会把应用工程中的
`task3_yolov5/yolov5_app/tools/device/yolo_acl_service.py` 和
`run_yolo_acl_service.sh` 同步到
`device/board/ascend/310B/cfg/`，再由 `cfg/BUILD.gn` 的预编译目标安装到
`/vendor/etc`。不要从旧的 HTTP 服务补丁复制 5001 服务文件。

### 3. 添加缺失文件

补丁中引用的新文件（如 `setup_network.sh` 等）已包含在补丁中（通过创建新文件），但 `main.py` 和 `server.py` 分别由 `device-board-ascend-310B-yolov5-main.py.patch` 和 `server.py.patch` 创建，应用后会自动生成。

还需确保以下外部依赖已准备：

- **CANN 驱动包**：`Ascend-hdk-310b-npu-driver-soc_24.1.rc2_linux-aarch64.run`
- **CANN 工具包**：`Ascend310B-source-bjjc-ohos.tar.gz`
- **libaarch64 辅助库**：`libaarch64.tar.gz`

这些文件需在编译前放置于合适位置（参考技术文档的“1.3 文件替换”），或通过脚本自动处理。

### 4. 编译镜像

使用**本组撰写**的 `build_and_flash_310B.sh` 脚本（位于项目根目录）一键编译和烧录：

```
cd /path/to/scripts
./build_and_flash_310B.sh
```

该脚本会：

- 进入源码目录执行 `./build.sh --product-name 310B --ccache`
- 将生成的镜像文件拷贝到固件目录
- 调用 `formatSD310B.sh` 烧录到 SD 卡

若希望手动编译，可执行：

```
cd /path/to/openharmony
./build.sh --product-name 310B --ccache
```

如果只需要复现本次构建修复，可先生成 GN 构建图并构建音频策略目标：

```bash
cd /home/hfut/work/5.0.3
prebuilts/build-tools/linux-x86/bin/gn gen out/310B
ninja -C out/310B audio_policy_service
```

目标构建通过后再执行产品全量构建。首次应用补丁时，项目中的
`scripts/apply_patches.sh` 会自动扫描 `patch_fix/`；也可以在源码根目录手动执行：

```bash
patch -p1 < /home/hfut/work/project3136859-388911/task1_transplantation/patch_fix/openharmony-5.0.3-build-fixes.patch
```

该补丁包含多个 OpenHarmony 仓库的相对路径，必须从源码树根目录执行。

编译完成后，镜像位于 `out/310B/packages/phone/images/`，然后参考 `310BFormatTest` 工程制作 SD 卡。

### 5. 烧录与启动

- 将 SD 卡插入开发板，上电启动。
- 系统初始化时会自动执行网络配置、CANN 环境变量设置，并启动兼容图片服务（回环 5000）和 NAPI CANN 服务（回环 5001）。
- 5001 服务的模型、缓存和日志写入 `/data/yolov5_napi`；如果板子还未安装 Python、CANN 或 NPU 驱动节点，启动脚本最多等待 180 秒并记录失败原因。
- 兼容 HTTP 服务仅供本机历史页面使用；NAPI 服务固定监听 `127.0.0.1:5001`，不会开放到局域网。

------

## 常见问题

### Q1: 应用补丁时提示 `Hunk FAILED`

**A**: 可能是源码版本与补丁期望的行号不完全匹配。请检查补丁文件中的上下文，并尝试：

- 使用 `patch -p1 --fuzz=3 < patchfile` 放宽匹配
- 手动编辑目标文件，参照补丁内容修改

### Q2: 编译时提示 `undefined reference to glEGLImageTargetTexture2DOES`

**A**: 请确保已应用 `patch_fix` 下的 `gl_utils.cpp.patch`，该补丁通过 `eglGetProcAddress` 动态加载扩展函数，解决了符号未定义问题。

### Q3: 显示无输出（HDMI 黑屏）

**A**: 补丁只采用内核/EDID 实际提供的模式，并过滤无效 EDID；若仍无输出，请检查硬件连接、EDID 校验和稳定供电，不要再手工注入 1080p 时序。

------

## 参考资料

- [OpenHarmony 编译构建指导](https://gitcode.com/openharmony/docs/blob/weekly_20250414/zh-cn/device-dev/subsystems/subsys-build-all.md)
- [Ascend 310B 硬件文档](https://www.hiascend.com/)
- [CANN 安装指南](https://www.hiascend.com/document)

------

## 维护与更新

本补丁集针对 `OpenHarmony-5.0.3-Release` 动态分支制作，若上游源码有较大变动，可能需要重新生成补丁。如有问题，请提交 Issue 或联系项目维护者。
