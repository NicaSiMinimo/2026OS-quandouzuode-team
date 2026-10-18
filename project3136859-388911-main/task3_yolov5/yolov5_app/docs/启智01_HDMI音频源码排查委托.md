# 启智01 OpenHarmony 系统源码综合排查与补丁委托

## 一、任务目标

请在另一台具备启智01完整 OpenHarmony 系统源码与编译环境的电脑上，完成以下相互独立的源码排查和补丁设计：

1. 修复 HDMI 只有画面、没有播放声卡的问题。
2. 永久修复无效 HDMI 连接器、虚假显示模式和 `drmModeAtomicCommit -22` 问题。
3. 将当前 YOLOv5 NAPI + 本机 CANN 服务正式集成进系统镜像，并优化 IPC。
4. 修复 USB 摄像头预览与连续 YUV 分析流不能稳定并行的问题，降低实时检测延迟。
5. 统一 USB 摄像头预览、JPEG/YUV 分析帧的镜像和方向元数据。
6. 定位并修复反复安装/停止应用后 Launcher/RenderService 的 `RSRenderThread SIGSEGV`。

以上任务必须拆成独立提交，分别构建、验证和回滚。不要把显示、音频、相机、推理和图形服务修改混在一个无法定位回归的补丁中。

本文件整合了此前的显示驱动、推理 NAPI 指导，以及本轮 HDMI 音频和实时摄像头实测结果。应用层已经实现实时预览、目标检测、规则判断、本地 MP3 语音队列和测试按钮；系统源码任务应解决底层能力和稳定性，不要重复改写已经工作的业务页面。

请优先给出最小、可回滚的系统源码补丁，不要修改当前 Windows 电脑上的应用工程，也不要要求在该电脑下载完整系统源码。

### 1.1 另一台电脑必须阅读的资料

目标板资料：

```text
D:\WORK\E\2026OS\project3136859-388911\技术文档.pdf
D:\WORK\E\2026OS\project3136859-388911\task1_transplantation\README.md
D:\WORK\E\2026OS\project3136859-388911\task1_transplantation\device-soc-ascend-310B-hardware-display-src-display_device-drm_connector.cpp.patch
D:\WORK\E\2026OS\project3136859-388911\task1_transplantation\device-board-ascend-310B-cfg-init.310B.yolov5.cfg.patch
D:\WORK\E\2026OS\project3136859-388911\task1_transplantation\device-board-ascend-310B-cfg-BUILD.gn.patch
```

当前应用关键文件：

```text
D:\WORK\DevEcoStudio\yolov5_app\entry\src\main\cpp\yolo_engine.cpp
D:\WORK\DevEcoStudio\yolov5_app\entry\src\main\cpp\yolo_live_napi.cpp
D:\WORK\DevEcoStudio\yolov5_app\entry\src\main\ets\native\YoloNativeBridge.ets
D:\WORK\DevEcoStudio\yolov5_app\entry\src\main\ets\pages\LiveCamera.ets
D:\WORK\DevEcoStudio\yolov5_app\tools\device\yolo_acl_service.py
D:\WORK\DevEcoStudio\yolov5_app\tools\device\run_yolo_acl_service.sh
D:\WORK\DevEcoStudio\yolov5_app\docs\实时检测与语音告警说明.md
```

参考应用：

```text
D:\WORK\DevEcoStudio\HarmonyInstrument_modify40
D:\WORK\DevEcoStudio\monitor_all
```

参考项目只能用于理解 ArkTS/NAPI/音频播放器的组织方式。不要直接复用 RKNN、RK3568 板级库或其他 SoC 的驱动；目标芯片是 Ascend 310B。

## 二、任务 A：启用 HDMI 音频播放

### 2.1 目标硬件与系统

- 开发板：启智01，昇腾 310B 系列。
- Device Tree model：`BJJC-QiZhi1-2T`。
- OpenHarmony：`5.0.3.140`。
- Kernel：`Linux 5.10.0+`，构建日期 `2026-06-28`。
- 启动参数包含：`ohos.boot.hardware=310B`。
- 显示器通过 HDMI 传输画面，通过 USB 供电并传输触摸信号。
- 同一显示器连接 Windows 电脑时，能够通过 HDMI 正常播放声音，已排除显示器扬声器、HDMI 线和显示器音量问题。
- 开发板 HDMI 当前输出为 `1920×1080@60Hz`，画面和触摸正常。

## 三、应用侧已经排除的问题

应用使用 ArkTS `AVPlayer` 播放打包在 HAP `rawfile` 中的本地 MP3。

按钮点击后播放器状态完整经过：

```text
initialized
prepared
playing
completed
released
```

测试 MP3 参数：

```text
Duration: 约 2.21 秒
mean_volume: -18.7 dB
max_volume: -4.4 dB
```

系统 MUSIC 音量为 `7/15`，`mute = 0`。因此 MP3 不是静音文件，系统媒体音量也不是 0。

## 四、板端关键证据

### 4.1 HDMI 视频链路正常

```text
/sys/class/drm/card0-HDMI-A-1/status = connected
/sys/class/drm/card0-HDMI-A-1/edid = 128 bytes
```

内核日志持续显示 HDMI 成功取得以下时序：

```text
vact = 1080
hact = 1920
crtc_refresh_rate = 60
hdmi_pix_freq = 148500
```

### 4.2 内核没有 HDMI 播放声卡

`cat /proc/asound/cards`：

```text
0 [WEBCAM]: USB-Audio - C270 HD WEBCAM
```

`aplay -l`：

```text
**** List of PLAYBACK Hardware Devices ****
```

列表为空。

`cat /proc/asound/pcm`：

```text
00-00: USB Audio : USB Audio : capture 1
```

`/dev/snd` 只有：

```text
controlC0
pcmC0D0c
timer
```

其中 `pcmC0D0c` 是 C270 摄像头的 Capture 设备，没有任何以 `p` 结尾的 Playback PCM。

系统中也没有 `/proc/asound/card*/eld*`，说明 HDMI 音频能力没有进入 ALSA/ASoC 链路。

### 4.3 AudioPolicy 只有逻辑扬声器

`hidumper -s AudioPolicyService -a '-d'` 显示：

```text
Output local Devices:
  device name: SPEAKER
  device type: 2
  device id: 1
  sampleRates: 48000
  channels: 1

Highest priority output device: SPEAKER
```

这是 OpenHarmony 音频策略层的逻辑输出，底层没有对应的 ALSA Playback PCM，因此应用可以报告播放完成，但听不到声音。

### 4.4 设备树平台设备存在，但未绑定驱动

板端平台设备：

```text
400160000.audio
  compatible = "vendor,aiao"

4001a0000.hdmi
  compatible = "vendor,hdmi"

audio-sys
  compatible = "hisilicon,hisi-audio-sys"

sound
  compatible = "Ascend,310b-audio-machine"
```

`sound` 节点还包含：

```text
ascend310b,audio-codec
ascend310b,platform
audio-routing
```

但是以下设备均没有 `driver` 绑定：

```text
sound-unbound
audio-unbound
hdmi-unbound
```

`/sys/bus/platform/drivers` 中与音频相关的只看到通用 `soc-audio`。

### 4.5 内核配置与模块现状

已启用：

```text
CONFIG_SND=y
CONFIG_SND_PCM=y
CONFIG_SND_USB=y
CONFIG_SND_USB_AUDIO=y
CONFIG_SND_SOC=y
```

未发现针对该板 HDMI/AI AO/310B audio machine 的已启用配置。另有：

```text
# CONFIG_SND_HDA_INTEL is not set
```

系统分区只找到：

```text
/system/lib/modules/5.10.0+/kernel/sound/soundcore.ko
```

没有可临时加载的 310B、AIAO、HDMI audio 或 audio-machine 模块，因此无法在现有镜像上通过 `insmod` 完成验证。

## 五、请在源码中完成的排查

### 5.1 确认源码版本和产品目标

请先记录：

- 完整源码根目录。
- 仓库清单或 manifest 版本。
- 分支、tag、commit。
- 启智01/310B 对应的 product、board、kernel build target。
- 当前板端 `OpenHarmony 5.0.3.140` 和 `5.10.0+` 对应的源码版本。

不要先套用 RK3568、RK3566 或其他开发板补丁。目标是昇腾 310B/启智01现有的自定义 HDMI 与 AIAO 驱动。

### 5.2 搜索设备树兼容字符串

请在完整源码根目录执行同等搜索：

```bash
rg -n 'Ascend,310b-audio-machine|vendor,aiao|vendor,hdmi|hisilicon,hisi-audio-sys'
rg -n 'ascend310b,audio-codec|ascend310b,platform|audio-routing'
```

需要回答：

1. 每个 `compatible` 应由哪个 `platform_driver` 匹配？
2. 对应驱动源码是否存在？
3. 驱动是否被 Kconfig/Makefile 排除？
4. 驱动应编进内核还是生成 `.ko`？
5. 当前 product 的 defconfig/config fragment 为什么没有启用？

### 5.3 搜索音频驱动和构建开关

```bash
rg -n -i '310b.*audio|audio.*310b|aiao|audio-machine'
rg -n -i 'hdmi.*audio|audio.*hdmi|hdmi-codec|snd_soc|soc-audio'
rg -n 'CONFIG_SND|CONFIG_SND_SOC|CONFIG_.*AIAO|CONFIG_.*HDMI.*AUDIO' \
  --glob '*defconfig*' --glob '*config*' --glob 'Kconfig*' --glob 'Makefile*'
```

重点检查：

- 310B AIAO CPU DAI 驱动。
- 310B audio machine/card 驱动。
- HDMI codec/DAI 驱动。
- HDMI 视频驱动是否实现音频相关寄存器配置、音频时钟、N/CTS、infoframe 和 mute/unmute。
- ASoC DAI link 是否把 AIAO CPU DAI、platform 和 HDMI codec 正确连接。
- 驱动的 `of_match_table` 是否与运行设备树完全一致，包括大小写。
- 对应对象是否进入最终 `Image` 或 vendor/system `.ko`。

### 5.4 检查设备树

请找到启智01实际打包使用的 DTS/DTSI，而不是只看通用 310B 文件。

检查：

- `/sound` 节点的 `compatible`、card name、CPU/platform/codec phandle。
- `ascend310b,audio-codec` 和 `ascend310b,platform` 是否指向正确节点。
- `audio-routing` 两两字符串是否正确。
- AIAO 和 HDMI 节点的 `status`。
- clocks、resets、interrupts、reg、DMA、IOMMU 等资源是否齐全。
- HDMI0 与 HDMI1 中哪个负责图形桌面和音频输出。
- HDMI connector 是否读取 EDID audio data block，并生成 ELD。
- 显示器插拔后是否会通知 ALSA/ASoC codec。

如果运行设备树与源码不一致，请追踪最终 DTB/DTBO 的生成与打包路径。

### 5.5 检查 OpenHarmony Audio HDI 和策略配置

只有当 `aplay -l` 已经出现 HDMI Playback PCM 后，再检查上层配置。

搜索：

```bash
rg -n -i 'audio_policy_config|primary_output|Speaker_Out|alsa|pcm|card|device' \
  vendor device foundation drivers
```

重点检查：

- `/vendor/etc/audio/audio_policy_config.xml` 的生成源文件。
- primary audio adapter/HDI 是否使用 ALSA 后端。
- 绑定的 card/device 编号是否可随 USB 摄像头声卡编号变化。
- HDMI 设备是否需要定义为独立输出，还是让逻辑 `SPEAKER` 映射到 HDMI PCM。
- 输出格式是否与显示器能力兼容，建议先验证 48 kHz、16-bit、双声道 PCM。

不要硬编码为 `card 0`。当前 C270 摄像头会占用 USB Audio card，HDMI 声卡编号可能变化；应优先按声卡名称或稳定匹配规则选择。

## 六、期望补丁范围

请提供尽量小的补丁，可能涉及：

1. Kernel Kconfig/defconfig/config fragment。
2. Kernel Makefile。
3. 310B audio machine、AIAO 或 HDMI codec 驱动。
4. 启智01 DTS/DTSI。
5. OpenHarmony Audio HDI/ALSA adapter 配置。
6. Product 打包配置，确保驱动、DTB 和 XML 进入镜像。

不要修改 YOLOv5 应用来掩盖系统问题。不要把“AVPlayer completed”当成硬件播放成功。

补丁必须保留：

- HDMI 1920×1080@60Hz 显示。
- USB 触摸。
- C270 摄像头视频采集和 USB Audio Capture。
- 当前 NPU 推理服务。

## 七、构建和部署要求

请明确给出：

- 需要执行的完整构建命令。
- 仅编内核/DTB/vendor 音频组件是否足够。
- 最终生成文件的绝对或源码相对路径。
- 哪些分区需要烧录或替换。
- 烧录前的备份方法。
- 失败后的回滚方法。
- 是否必须整包升级。

若支持先做最小验证，请优先给出“仅替换内核/DTB/模块”的步骤，验证通过后再制作完整系统镜像。

## 八、验收标准

刷入补丁后，按以下顺序验收。

### 8.1 内核层

```bash
cat /proc/asound/cards
cat /proc/asound/pcm
aplay -l
ls -l /dev/snd
find /proc/asound -name 'eld*' -type f -maxdepth 3 -print
```

必须出现至少一个 HDMI Playback PCM 和对应 `/dev/snd/pcmC*D*p`。

ELD 应显示显示器已连接并具备音频能力。

### 8.2 直接播放

准备 48 kHz、16-bit、双声道 WAV，绕过应用测试：

```bash
aplay -D hw:<hdmi-card>,<device> test.wav
```

显示器必须能听到声音。若 `aplay` 无声，不进入应用层排查。

### 8.3 OpenHarmony 音频框架

```bash
hidumper -s AudioPolicyService -a '-d'
hidumper -s AudioPolicyService -a '-v'
```

确认系统输出已映射到真实 HDMI PCM，且 MUSIC 未静音。

### 8.4 应用

启动 YOLOv5 应用，进入实时摄像头页面，点击“测试语音”。应从显示器听到：

```text
检测到人员到岗。
```

同时确认摄像头推理、检测框和触摸没有回归问题。

## 九、任务 B：永久修复 HDMI 显示连接器和模式选择

### 9.1 已知问题

历史板端实测曾出现两个 DRM HDMI connector，其中一个 connector 被报告为 connected，但 EDID 是全零或无效数据；现有显示补丁又在“模式列表没有 1080p”时强行把 mode 0 改成手工构造的 `1920×1080@60Hz`。

该组合会让 RenderService 发布不存在的物理屏，并出现：

```text
drmModeAtomicCommit failed -22 errno 22
```

运行时关闭无效 connector 后错误会停止，说明应用无法永久解决该问题，必须修显示适配层。

当前 HDMI 名称和探测顺序可能随内核、端口和启动顺序变化，因此不能把 `HDMI-A`、`HDMI-B` 或 connector 数字 ID 当作永久判断依据。

### 9.2 期望修改

重点检查：

```text
device/soc/ascend/310B/hardware/display/src/display_device/drm_connector.cpp
```

以及它在当前源码版本中的实际对应文件。

要求：

1. 删除“没有 1080p 就强制替换 mode 0”的逻辑。
2. 只复制内核 DRM 实际返回的 modes。
3. 优先选择带 `DRM_MODE_TYPE_PREFERRED` 的模式。
4. 没有 preferred 但 modes 非空时，才使用第一个内核模式作为回退。
5. modes 为空时不能伪造 1080p。
6. 对外接 HDMI 校验 EDID：长度、`00 ff ff ff ff ff ff 00` 文件头、每个 128 字节块校验和和可用 modes。
7. connected 但 EDID 全零、头错误、校验失败且没有有效 mode 的外接 connector，不向 HDF/RenderService 发布为真实物理屏。
8. 如果产品确实需要支持无 EDID 显示器，使用显式产品开关和 connector/mode 白名单，默认关闭。
9. 不要在最终实现中直接写固定 `/sys/class/drm/card0-HDMI-*` 路径；应通过 DRM property/blob API 读取 EDID。
10. `drmModeProperty`、property blob 和 connector 对象在所有退出路径正确释放。

### 9.3 显示验收

至少覆盖以下启动顺序：

- 先开显示器再开板。
- 先开板再开显示器。
- HDMI 热拔插。
- 系统冷启动和重启。

验收要求：

- 只发布真实有效的物理屏。
- 使用显示器 EDID 声明的 preferred mode。
- 连续 10 分钟没有新的 `drmModeAtomicCommit failed -22`。
- 触摸坐标、旋转和 1920×1080 显示不回归。
- 不再依赖 `echo off > .../status`。

## 十、任务 C：将 YOLOv5 NAPI 与 CANN 推理服务正式集成进系统

### 10.1 当前可工作的架构

应用侧已经是普通 NAPI 调用形式：

```text
ArkTS
  -> libyolo_napi.so（OpenHarmony NDK/musl）
  -> 127.0.0.1:5001 二进制协议
  -> yolo_acl_service.py（Linux glibc/Python）
  -> ais_bench / CANN 8.2.RC1
  -> Ascend 310B NPU
```

模型为应用 `rawfile` 中的 `yolov5s_ascend310b.om`。NAPI 将模型发送给本机服务，服务校验长度和 SHA-256 后持久加载。

当前紧凑检测命令已经做到：

- 应用原生侧完成 RGBA/YUV 预处理和 letterbox。
- 向服务发送 `uint8` NCHW 数据。
- 服务端执行 NPU 推理和 NMS。
- IPC 只返回最多 100 个紧凑检测框，不再返回完整 8.5 MB 输出张量。

实测基线：

```text
模型输入：1×3×640×640
模型输出：25200×85
NPU：约 17 ms
native：约 88-90 ms
camera end-to-end：约 330-340 ms
实时速度：约 2.35 FPS
```

### 10.2 ABI 边界，禁止错误直链

当前 `libyolo_napi.so` 是 OpenHarmony musl ABI；板上 CANN `libascendcl.so` 是 glibc ABI，并依赖：

```text
libc.so.6
ld-linux-aarch64.so.1
libpthread.so.0
GLIBC_2.17
```

因此不要：

- 把 glibc CANN 直接 `dlopen` 到 appspawn 创建的 musl 应用进程。
- 把 `libc.so.6` 软链接到 OpenHarmony `libc.so`。
- 同进程混用 glibc/musl 分配器、TLS 和线程实现。
- 仅靠 `LD_LIBRARY_PATH` 或 linker namespace 声称直接 NAPI 已解决。
- 把整套 CANN `.so` 塞入 HAP 绕过系统约束。

只有厂商提供完整 OpenHarmony/musl 版本 CANN 及其全部依赖后，才允许重新评估同进程直接 NAPI。

### 10.3 第一阶段必做：正式打入系统镜像

把当前经过实测的文件纳入源码构建：

```text
yolo_acl_service.py
run_yolo_acl_service.sh
init.310B.yolov5.cfg
相关 BUILD.gn/product 依赖
```

要求：

1. 冷启动后 init 自动拉起服务，不依赖 hdc 手工执行。
2. 只监听 `127.0.0.1`，不能监听局域网地址。
3. 等待 `/dev/davinci0`、`/dev/davinci_manager`、`/dev/ascend_manager` 和 CANN 环境就绪。
4. `ais_bench`/`InferSession` 延迟到首次 INIT 时导入。
5. 设置正确的 `ASCEND_HOME_PATH`、`ASCEND_OPP_PATH`、`PYTHONPATH` 和 glibc `LD_LIBRARY_PATH`。
6. 服务异常退出后由 init 有限重启，并记录明确原因。
7. 模型和可写缓存放在 `/data` 或现有 `/cann-install/yolov5_napi`，不写只读 system/vendor。
8. 系统镜像必须包含脚本、服务、init 配置和 GN 依赖，不能只修改已烧录设备。
9. 补充 SELinux、sandbox、NPU 设备节点和本机 IPC 的最小权限策略。
10. NAPI 默认禁用不可靠的直接 ACL 回退；服务不可用时返回明确错误，不崩溃。

### 10.4 第二阶段优化

在第一阶段稳定后，再独立实施：

- 用厂商 aarch64-linux-gnu/glibc 工具链编译 C++ CANN daemon，替换 Python，但保留协议兼容。
- TCP 替换为 Unix Domain Socket，并配置 socket ownership、SELinux 和应用沙箱权限。
- 使用长连接或连接池，避免每帧创建 TCP socket。
- 评估共享内存/零拷贝传输预处理张量，避免大块 IPC 拷贝。
- 服务保持模型、context、dataset 和输出 buffer 长期复用。
- 对输入做长度、shape、版本和上限校验；禁止输出图片或张量内容到日志。

不要在一个提交中同时更换 Python/C++、TCP/UDS、模型格式和预处理算法。

### 10.5 推理验收

- 冷启动无需 hdc 即可完成真实 NPU 推理。
- 服务只监听本机。
- ArkTS 只调用 `libyolo_napi.so`，页面不知道 Python/TCP 的存在。
- 连续推理至少 500 帧，无 native crash、NPU context 泄漏和持续内存增长。
- 应用前后台切换、服务重启、摄像头拔插后可以恢复。
- 同一输入与 `ais_bench` 基准结果一致。
- 保持 NPU 时间约 17-20 ms；IPC 优化不能降低检测精度。

## 十一、任务 D：USB 摄像头低延迟 YUV 分析流与方向一致性

### 11.1 当前状态

摄像头枚举为 `lcam001`，应用使用 `NORMAL_VIDEO`。

当前稳定路径是：

```text
PreviewOutput -> 屏幕预览
PhotoOutput -> JPEG -> PixelMap -> native 预处理 -> NPU
```

该路径能稳定运行，但每帧端到端约 330-340 ms。应用中已经实现 `ImageReceiver + VideoOutput + YUV420` 的连续分析代码，但因当前板端并行输出能力不稳定，`enableContinuousYuv` 默认关闭。

此外，板端 `Photo.release()` 如果同步等待可能长时间挂起；当前应用只能 fire-and-forget 释放，这是系统实现需要排查的迹象。

### 11.2 期望源码修改

请搜索并检查启智01的 CameraService、Camera Framework、USB UVC Camera HDI 和 buffer queue 实现：

```bash
rg -n -i 'lcam|uvc|usb.*camera|camera.*usb|VideoOutput|PhotoOutput|ImageReceiver'
rg -n -i 'YUV_420|YUV420|OHOS_CAMERA_FORMAT|rowStride|pixelStride'
```

目标能力：

1. 同一 `NORMAL_VIDEO` session 稳定支持一个预览输出和一个低分辨率 YUV 分析输出。
2. 推荐分析规格先验证 `640×360` 或接近 16:9 的摄像头原生 YUV 模式。
3. Camera HDI 正确声明支持的 preview/photo/video profiles 和组合能力，不能宣称支持后在 `commitConfig` 或 `start` 失败。
4. YUV plane 的 format、row stride、pixel stride、UV 顺序和 buffer size 与 API 返回一致。
5. `ImageReceiver` 队列采用 latest-frame 策略，推理繁忙时丢旧帧，不反压摄像头预览。
6. 页面退出、摄像头拔插和应用前后台切换时，VideoOutput、ImageReceiver、Session 和 UVC fd 能按确定顺序释放。
7. 修复 `Photo.release()` Promise 可能不完成或死锁的问题。
8. 不新增录像，不保存视频；该分析流只服务实时预览和目标检测。
9. 摄像头与 NPU 并行运行时不能引发 USB 掉线、黑屏或 RenderService 卡死。

### 11.3 镜像和方向

当前预览画面是水平镜像的，而 JPEG/分析坐标不是镜像的，应用只能使用：

```text
mirroredX = 1 - x - width
```

来补偿检测框。

请检查 UVC 外接摄像头的 metadata：camera position/facing、sensor orientation、connection type 和 preview mirror policy。

期望：

- 外接 UVC 摄像头不要错误标记为手机前置摄像头。
- 预览、PhotoOutput、VideoOutput/YUV 和检测框使用一致坐标系。
- 如果系统规定预览必须镜像，应通过正式 metadata/API 告知应用，而不是只在渲染层静默翻转。
- 横竖屏、旋转和 HDMI 显示方向变化后坐标仍一致。

### 11.4 相机性能验收

- 连续运行至少 30 分钟，无闪退和 USB 摄像头重置。
- 完成 1000 帧分析，buffer 和 fd 数量不持续增长。
- 预览保持流畅，推理忙时只丢分析帧。
- YUV 路径端到端延迟应明显低于当前 JPEG 路径；建议阶段目标 `<200 ms`，再根据板端能力优化到 5 FPS 以上。
- 检测框左右方向与真实物体一致，不再依赖不透明的隐式镜像假设。

## 十二、任务 E：RenderService/Launcher 图形线程崩溃

### 12.1 已观察到的崩溃

反复执行 HAP 覆盖安装、停止/启动应用、进入带视频背景和 Camera XComponent 的页面后，系统 Launcher 会出现：

```text
Process name: com.ohos.launcher
Thread name: RSRenderThread
Signal: SIGSEGV (SEGV_MAPERR) @ 0x70
probably caused by NULL pointer dereference
OpenHarmony 5.0.3.140
```

发生后桌面黑屏或 Launcher 反复崩溃，重启开发板可以恢复。该问题不是应用进程 JavaScript 异常，而是系统图形线程崩溃。

### 12.2 排查要求

1. 使用带符号的 RenderService、Rosen、EGL/GLES、Mesa/Gallium 和显示 HDI 库符号化 PC/LR。
2. 记录崩溃时 GPU/DRM fd、surface、buffer queue、MediaPlayerSurface 和 XComponent surface 的生命周期。
3. 检查应用 force-stop、HAP reinstall、ability 销毁和 Launcher 恢复时的 surface unregister/consumer release 顺序。
4. 检查已销毁 window/surface/render node 被 RSRenderThread 延迟任务继续引用的 use-after-free 或空指针。
5. 检查无效 HDMI connector/atomic commit 失败是否放大了资源释放竞态。
6. 不能只在崩溃点加宽泛 `if (ptr == nullptr) return`；必须解释对象为何为空并修复所有权或任务取消。
7. 增加有界日志，不要保留每帧 HDMI timing DEBUG 刷屏。

### 12.3 复现和验收

建立自动化但可回滚的测试：

1. 启动应用首页视频背景。
2. 进入实时摄像头并运行至少 30 秒。
3. 返回、force-stop、重新启动。
4. 覆盖安装同一 HAP 后再次启动。
5. 重复至少 20 轮。

要求：

- Launcher 和应用的 RSRenderThread 均无 SIGSEGV。
- 桌面无需重启即可恢复。
- MediaPlayerSurface、Camera XComponent 和 Canvas overlay 无残留。
- fd、GraphicBuffer、surface node 和 GPU 内存不持续增长。

## 十三、明确不应通过系统源码“修复”的事项

以下现象已经确认属于硬件、模型或应用业务层，不能靠无关驱动补丁掩盖：

1. 开发板应使用原装或足额的 `12V/4A` 电源；低电流适配器导致屏幕黑屏、绿闪或红白绿蓝测试色循环，不是显示驱动可以补偿的问题。
2. USB 摄像头应连接 USB 3.0 口或独立供电 Hub；USB 供电不足导致摄像头/触摸掉线，不应通过放宽驱动超时掩盖。
3. 显示器扬声器、HDMI 线和屏幕音量已经通过 Windows 电脑验证正常；HDMI 无声是开发板播放驱动问题。
4. 当前 YOLOv5s 是 COCO 80 类模型，没有吸烟、香烟、安全帽或未戴安全帽类别。不能用不相关类别伪造这些判断；需要专用训练模型。
5. 人员到离岗、禁区、人数、疑似手机、设备缺失、安检物品和疑似遗留物规则已经在应用层实现，不应写进内核。
6. 中文语音已由 `D:\WORK\MyScripts\tts.py` 提前生成本地 MP3，应用运行时不需要系统在线 TTS。
7. 本项目不需要录像；相机源码修改不得以“优化”为由恢复录像或持续写盘。

## 十四、建议的提交和实施顺序

请至少拆成以下提交：

1. `audio: enable Ascend310B HDMI playback card`
2. `display: reject invalid EDID and remove forced 1080p mode`
3. `yolo: package local CANN service and init integration`
4. `camera: support preview plus low-latency YUV analysis`
5. `camera: fix UVC facing/mirror metadata and release lifecycle`
6. `graphics: fix RSRenderThread surface teardown crash`

每个提交都必须包含：

- 根因及源码路径/行号。
- 最小 diff。
- 构建命令和输出文件。
- 单独部署方法。
- 单独验证方法。
- 回滚方法。

优先顺序建议：先修 HDMI 音频和显示 connector，再集成推理服务，然后修 Camera YUV，最后在底层状态稳定后复现并修图形竞态。

## 十五、整体验收标准

只有以下全部通过，才可以报告系统源码改造完成：

- HDMI 显示和 EDID/mode 选择稳定。
- `aplay -l` 出现 HDMI Playback，显示器能够直接播放 WAV。
- OpenHarmony AVPlayer 的测试语音从显示器发声。
- 冷启动后 CANN 推理服务自动启动，NAPI 无需 hdc 即可完成真实 NPU 推理。
- 连续 500 帧推理、1000 帧相机分析无泄漏或崩溃。
- Preview + YUV 分析稳定并行，检测框方向正确。
- 20 轮应用安装/启动/停止压力测试无 RSRenderThread SIGSEGV。
- 摄像头、触摸、NPU、显示和音频能够同时运行。
- 所有补丁、构建记录和回滚文件齐全。

## 十六、请回传的结果

请按以下模板回复，方便把结果传回当前电脑继续实施：

```text
【源码版本】
源码根目录：
manifest/分支/tag/commit：
product/board/kernel target：

【任务完成状态】
HDMI 音频：
显示 connector：
YOLO 系统集成：
Camera YUV：
Camera 镜像/释放：
RSRenderThread：

【每项根因】
缺失或错误的驱动/配置/生命周期：
证据（文件路径和准确行号）：

【补丁】
修改文件清单：
统一 diff 或完整关键代码：

【构建】
环境准备：
构建命令：
输出文件：

【部署与回滚】
备份命令：
刷入/替换命令：
回滚命令：

【验证】
实际 aplay -l、/dev/snd、ELD 和 Audio HDI：
实际 HDMI 显示/EDID/atomic commit：
实际 init 服务与 NAPI 推理：
实际 Preview + YUV 性能：
实际镜像和坐标：
实际图形压力测试：

【风险与未决问题】
```

回传时请附上所有结论对应的源码文件路径和准确行号，不要只给概念性建议。
