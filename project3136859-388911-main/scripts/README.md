# OpenHarmony工具集
本目录提供用于 **OpenHarmony** 设备上开发与部署的一系列辅助脚本，涵盖项目提交、环境预检查、镜像构建、固件烧录、补丁管理等常见操作。随着项目演进，将持续增加新工具，以简化开发与交付流程。

## 目录结构
```
.
├── preflight_check_on_device.sh   # 设备端 CANN 安装前预检查
├── build_and_flash_310B.sh        # 310B 开发板镜像编译与 SD 卡烧录
├── apply_patches.sh               # 批量应用补丁脚本
├── reverse_patches.sh             # 批量撤销补丁脚本
├── push_git.sh                    # Git 快速提交推送脚本
└── README.md                      # 本文档
```
后续新增脚本将统一放置于仓库根目录，并在本 README 中补充说明。

------

## 现有脚本说明
### 1. `preflight_check_on_device.sh` — CANN 安装前预检查
**用途**
在目标设备上运行，全面检查系统环境是否满足 CANN 安装要求，包括：
- CPU 架构（需 ARM64）
- 必备系统命令（`mkdir`、`cp`、`tar`、`mount` 等）
- 安装包文件完整性
- 设备节点（`/dev/davinci*`）和驱动目录
- 文件系统可写性
**使用方式**
```bash
# 默认环境变量
./preflight_check_on_device.sh
# 自定义临时目录和安装目录
DEVICE_TEMP=/mnt/sdcard/temp INSTALL_DIR=/data/cann ./preflight_check_on_device.sh
```
**输出**
每个检查项以 `[PASS]`、`[WARN]`、`[FAIL]` 标记，最终统计失败/警告数量。若有任何 `[FAIL]`，脚本以非零状态退出。
**环境变量**
| 变量名        | 默认值          | 描述                                 |
| :------------ | :-------------- | :----------------------------------- |
| `DEVICE_TEMP` | `/storage/temp` | 存放 CANN 安装包（`*.tar.gz`）的目录 |
| `INSTALL_DIR` | `/cann-install` | CANN 安装目标目录（需可写）          |

------

### 2. `build_and_flash_310B.sh` — 310B 镜像编译与烧录
**用途**
在开发主机上自动完成 OpenHarmony 310B 系统的编译、固件拷贝和 SD 卡烧录，同时记录各步骤耗时，便于性能分析。
**使用方式**
```bash
./build_and_flash_310B.sh
```
**可调参数**（源码目录可通过环境变量覆盖，其余参数可编辑脚本头部的默认值）
```bash
SOURCE_DIR=/path/to/5.0.3 ./build_and_flash_310B.sh # 可选；默认 /home/hfut/work/5.0.3
DEFAULT_FIRMWARE_DIR="$HOME/Desktop/.../firmware" # 编译产物拷贝目标
DEFAULT_FLASH_DIR="$HOME/Desktop/.../format"      # 烧录脚本所在目录
DEFAULT_SD_DEV="/dev/sdb"                         # SD 卡设备（请务必确认）
```
**依赖**
- OpenHarmony 编译环境（`hb`、`ninja`、`gn` 等）
- `sudo` 权限（用于编译、文件操作及烧录）
- 目标烧录脚本 `formatSD310B.sh` 存在于 `DEFAULT_FLASH_DIR`
**输出**
无论成功或失败，都会打印各步骤耗时及总耗时，便于问题回溯。产物使用 `cp -a` 复制到固件目录，成功构建后源码树中的 `out/310B/packages/phone/images/` 会保持完整。

------

### 3. `apply_patches.sh` — 批量应用补丁
**用途**
按照教程顺序批量应用 `.patch` 补丁到 OpenHarmony 源码目录，支持跳过已应用的补丁，记录失败情况。
**使用方式**
```bash
./apply_patches.sh
# 覆盖默认源码目录
SOURCE_DIR=/path/to/5.0.3 ./apply_patches.sh
```
**功能特性**
- 默认源码目录为 `/home/hfut/work/5.0.3`，可用 `SOURCE_DIR` 环境变量覆盖
- 按 `task1_transplantation` → `task1_transplantation/patch_fix` → `task4/memory` → `task4/time` 的顺序应用，每个目录内按文件名升序
- 自动检测并跳过已应用的补丁（不视为失败）
- 彩色输出显示应用进度
- 记录应用失败的补丁到 `scripts/fail_apply.txt`
- 补丁完成后，把 `task3_yolov5/yolov5_app/tools/device/` 中的 5001 服务脚本同步到板级 `cfg/`，避免沿用旧 HTTP-only 服务文件
- 只要有补丁失败就返回非零状态，防止在不完整源码上误启动构建
- 统计成功/失败数量和总耗时
**依赖**
- `patch` 命令
- `sudo` 权限（用于修改源码目录文件）

------

### 4. `reverse_patches.sh` — 批量撤销补丁
**用途**
按完整应用序列的**逆序**批量撤销已应用的补丁，保证撤销顺序正确性，支持跳过已撤销的补丁，记录失败情况。
**使用方式**
```bash
./reverse_patches.sh
# 覆盖默认源码目录
SOURCE_DIR=/path/to/5.0.3 ./reverse_patches.sh
```
**功能特性**
- 默认源码目录为 `/home/hfut/work/5.0.3`，可用 `SOURCE_DIR` 环境变量覆盖
- 按 `task4/time` → `task4/memory` → `task1_transplantation/patch_fix` → `task1_transplantation` 撤销，每个目录内按文件名逆序
- 自动检测并跳过已撤销的补丁（不视为失败）
- 彩色输出显示撤销进度
- 记录撤销失败的补丁到 `scripts/fail_reverse.txt`
- 统计成功/失败数量和总耗时
**依赖**
- `patch` 命令
- `sudo` 权限（用于修改源码目录文件）
> **注意**：撤销补丁必须使用**逆序**，否则可能导致补丁冲突。本脚本已自动处理逆序逻辑。

------

### 5. `push_git.sh` — Git 快速提交推送
**用途**
一键完成 Git 仓库的 `add`、`commit`、`push` 操作，简化日常代码提交流程，支持自定义仓库路径和提交信息。
**使用方式**
```bash
# 编辑脚本头部配置仓库路径和提交信息后执行
./push_git.sh
# 执行后按提示输入 y 确认执行
```
**可调参数**（直接编辑脚本头部）
```bash
REPO_PATH="/home/hfut/Desktop/2026OS/project3136859-3889116"  # 仓库路径，留空则使用当前目录
MESSAGE=""                                                    # 提交信息
```
**功能特性**
- 自动切换到指定仓库目录
- 执行前显示即将执行的命令并等待用户确认
- 自动统计执行总耗时
- 一键完成 add → commit → push 全流程
**依赖**
- Git 环境已配置
- 仓库已配置远程 origin 和 main 分支

------

## 通用环境要求
- **设备端脚本**：基于 ARM64 架构的 OpenHarmony / Linux 系统，支持 POSIX `sh`。
- **主机端脚本**：Linux（推荐 Ubuntu），需安装 OpenHarmony 编译工具链。
- 所有脚本均需 `sudo` 或相应权限（视具体操作而定）。
- 补丁相关脚本依赖 `patch` 命令，可通过 `sudo apt install patch` 安装。

------

## 使用注意事项
1. **设备节点与路径**：运行前请确认 `DEVICE_TEMP`、`INSTALL_DIR` 及 SD 卡设备与实际情况一致，避免误操作。
2. **烧录风险**：烧录步骤会直接写入 SD 卡设备，请务必确认设备号正确（如使用 `lsblk` 检查），以免破坏主机硬盘。
3. **源码目录配置**：补丁脚本默认操作 `/home/hfut/work/5.0.3`；源码位于其他位置时，请通过 `SOURCE_DIR` 环境变量指定。
4. **补丁顺序**：补丁脚本已固定教程目录顺序，并在各目录内按文件名排序；撤销时会自动使用完整逆序。
5. **Git 提交**：使用 `push_git.sh` 前请确认提交信息 `MESSAGE` 已填写，避免空提交。
6. **持续集成**：这些脚本可集成到 CI/CD 流程中，便于自动化测试与发布。
