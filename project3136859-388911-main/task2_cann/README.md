# CANN 安装指导文档

本目录包含在 **OpenHarmony 5\.0\.3** 系统上为 **Ascend 310B** 开发板部署 **CANN（Compute Architecture for Neural Networks）AI 计算框架** 的完整自动化脚本集。支持从 Windows 主机通过 HDC 一键推送安装包、远程执行安装、配置环境变量、安装 Python 依赖并验证 NPU 运行时。

---

## 目录结构

```Plain Text
task2_cann/
├── 00_deploy_scripts_from_windows.ps1      # Windows 端：部署安装脚本到设备
├── 01_push_packages_from_windows.ps1       # Windows 端：推送 CANN 安装包到设备
├── 02_install_cann_on_device.sh            # 设备端：主安装脚本（解压+安装 CANN 组件）
├── 03_set_cann_env.sh                      # 设备端：设置 CANN 运行环境变量
├── 04_install_python_wheels.sh             # 设备端：安装 Python 依赖包（torch_npu、ais_bench 等）
├── 05_verify_npu.sh                        # 设备端：验证 NPU 设备与 CANN 运行时
├── verify_cann_runtime.py                  # Python 端：通过 pyACL 验证 CANN 运行时
└── README.md                               # 本文档
```

---

## 脚本功能说明

|脚本文件|执行环境|作用|
|---|---|---|
|`00_deploy_scripts_from_windows.ps1`|Windows|通过 HDC 将所有设备端脚本（`.sh` 和 `.py`）发送到开发板 `/cann-install/task2_cann/` 目录，并设置可执行权限。|
|`01_push_packages_from_windows.ps1`|Windows|通过 HDC 将 CANN 安装包（`initenv.tar.gz`、`toolkit.tar.gz`、`nnal.tar.gz`、`kernels.tar.gz`）推送到设备 `/storage/temp/` 临时目录。|
|`02_install_cann_on_device.sh`|设备端|CANN 主安装程序：<br>1\. 解压并安装 `initenv`（初始化环境、Python 运行时）<br>2\. 解压并安装 `toolkit`（toolkit、runtime、opp、ncs、compiler、aoe、pyACL、hccl 等）<br>3\. 解压并安装 `nnal`（神经网络加速库 ATB）<br>4\. 解压并安装 `kernels`（算子内核）<br>5\. 清理临时安装包|
|`03_set_cann_env.sh`|设备端|自动检测 CANN 安装路径，设置所有必要环境变量：<br>\- `ASCEND_TOOLKIT_HOME`、`ASCEND_HOME_PATH`<br>\- `PATH`、`PYTHONPATH`、`LD_LIBRARY_PATH`<br>\- 算子路径、驱动库路径等|
|`04_install_python_wheels.sh`|设备端|批量安装 AI 推理所需 Python 包：<br>\- 基础库：numpy、scipy、pillow、protobuf、PyYAML<br>\- 深度学习：torch、torchvision、torch\_npu<br>\- CANN 专用：aclruntime、ais\_bench<br>\- 其他：opencv\-python、einops、scikit\-video 等|
|`05_verify_npu.sh`|设备端|集成验证脚本：<br>1\. 加载 CANN 环境变量<br>2\. 调用 `npu-smi info` 查看硬件信息<br>3\. 运行 `verify_cann_runtime.py` 验证 pyACL 运行时|
|`verify_cann_runtime.py`|设备端|通过 pyACL API 验证 CANN 运行时：<br>\- 初始化 ACL<br>\- 检测设备数量<br>\- 设置 / 重置设备<br>\- 创建 / 销毁上下文<br>\- 查询运行模式和内存信息<br>\- 输出验证结果|

---

## 前置准备

### 1\. 硬件与环境

- **开发板**：Ascend 310B 开发板，已烧录 OpenHarmony 5\.0\.3 镜像

- **主机**：Windows 10/11，已安装 HDC 工具并配置环境变量

- **连接**：开发板与主机通过 USB 或网络连接，`hdc list targets` 可正常识别设备

### 2\. 准备 CANN 安装包

将以下 4 个 CANN 安装包放置于 `task2_cann/` 目录（与脚本同级）：

```Plain Text
task2_cann/
├── initenv.tar.gz          # 初始化环境包（含 Python 3.10 运行环境）
├── toolkit.tar.gz          # CANN Toolkit 工具包
├── nnal.tar.gz             # 神经网络加速库
└── kernels.tar.gz          # 算子内核包
```

> **注意**：安装包版本需与 Ascend 310B 硬件及驱动版本匹配，建议使用 CANN 8\.2\.RC1 系列，四个压缩包下载链接：https://pan.baidu.com/s/1AomSfD3pPvQ56-lhn_wDUQ?pwd=aate 提取码: aate  

> 此外，为了节省装环境的步骤，本组对 initenv.tar.gz 压缩包进行了修改，在 python_packs 文件夹下面增加了两个 .whl 包，分别是 **ais_bench-0.0.2-py3-none-any.whl** 和 **aclruntime-0.0.2-cp310-cp310-linux_aarch64.whl** 这两个包，原在 example.tar.gz 中。
> 

### 3\. 准备 Python Wheel 包

将所有 Python `.whl` 包放置于设备端 `/cann-install/python_packs/` 目录（或通过 `WHEEL_DIR` 环境变量指定）。
> **注意**：Python Wheel 包已经包含在了 initenv.tar.gz 压缩包之中，在执行本组提供的脚本后，所有 .whl 包会放到设备端相应的位置。
> 
> 

---

## 安装步骤（推荐：Windows 主机一键执行）

### 步骤 1：部署脚本到设备

在 Windows 主机上打开 PowerShell，进入 `task2_cann` 目录，执行：

```powershell
.\00_deploy_scripts_from_windows.ps1
```

该脚本会自动：

- 挂载系统分区为可写

- 在设备上创建 `/cann-install/task2_cann/` 目录

- 将所有 `.sh` 和 `.py` 脚本发送到设备

- 为 Shell 脚本添加可执行权限

### 步骤 2：推送 CANN 安装包

继续在 Windows PowerShell 中执行：

```powershell
.\01_push_packages_from_windows.ps1
```

该脚本会将 4 个 CANN 安装包推送到设备的 `/storage/temp/` 目录。

> **提示**：若安装包位于其他目录，可通过参数指定：
> 
> ```powershell
> .\01_push_packages_from_windows.ps1 D:\cann-install
> ```
> 
> 

### 步骤 3：在设备端执行 CANN 安装

通过 HDC 进入设备 Shell：

```bash
hdc shell
```

在设备端执行主安装脚本：

```bash
cd /cann-install/task2_cann
./02_install_cann_on_device.sh
```

如果提示文件不存在或者无法运行之类的，这是因为Windows 编辑的脚本传到 Linux，每行结尾 \r\n，Linux 识别文件名时会把 \r 算进文件名，导致真实文件名变为02_install_cann_on_device.sh\r，所以02_install_cann_on_device.sh对不上，报不存在。
通过下面的命令来修复换行
```
sed -i 's/\r$//' 02_install_cann_on_device.sh
```

安装过程约需 15\-25 分钟，脚本会自动完成：

1. 初始化环境与 Python 3\.10 运行时

2. 安装 CANN Toolkit、Runtime、OPP、Compiler 等所有组件

3. 安装神经网络加速库 ATB

4. 安装算子内核

5. 清理临时文件

### 步骤 4：安装 Python 依赖包

在设备端继续执行(此步需要联网)：

```bash
./04_install_python_wheels.sh
```

同样的，如果提示文件不存在或者无法运行之类的，这是因为Windows 编辑的脚本传到 Linux，每行结尾 \r\n，Linux 识别文件名时会把 \r 算进文件名，导致真实文件名变为04_install_python_wheels.sh\r，所以04_install_python_wheels.sh对不上，这时也要通过命令来修复换行。

该脚本会批量安装所有 AI 推理所需的 Python 依赖。

### 步骤 5：验证安装

在设备端执行验证脚本：

```bash
./05_verify_npu.sh
```

同样的，如果提示文件不存在或者无法运行之类的，这是因为Windows 编辑的脚本传到 Linux，每行结尾 \r\n，Linux 识别文件名时会把 \r 算进文件名，导致真实文件名变为05_verify_npu.sh\r，所以05_verify_npu.sh对不上，报不存在，这时也要通过命令来修复换行。

成功输出示例：

```Plain Text
npu-smi Version           : 24.1.rc2
...
device_count=1
run_mode=1
device_memory_free=XXXXXX device_memory_total=XXXXXX
CANN runtime verification passed.
```

---

## 手动分步验证安装结果

若需分步调试，可按以下顺序手动执行：

### 1\. 加载环境变量

每次新开 Shell 都需要先加载环境：

```bash
. /cann-install/task2_cann/03_set_cann_env.sh
```

### 2\. 验证 Python 环境

```bash
python3.10 --version
pip3 list | grep -E "torch|npu|acl"
```

### 3\. 验证 NPU 硬件

```bash
npu-smi info
```

### 4\. 验证 CANN 运行成功与否

```bash
python3.10 /cann-install/task2_cann/verify_cann_runtime.py
```

---

## 环境变量说明

`03_set_cann_env.sh` 会自动设置以下关键环境变量：

|变量名|说明|
|---|---|
|`ASCEND_TOOLKIT_HOME`|CANN Toolkit 安装根目录（默认 `/usr/local/Ascend/8.2.RC1`）|
|`ASCEND_HOME_PATH`|CANN 主路径（同 Toolkit 目录）|
|`ASCEND_OPP_PATH`|算子包路径|
|`PATH`|添加 CANN 工具二进制目录|
|`PYTHONPATH`|添加 pyACL 和 TBE 算子路径|
|`LD_LIBRARY_PATH`|添加驱动库、CANN 运行库、Python 运行库等搜索路径|

> **提示**：建议将 `. /cann-install/task2_cann/03_set_cann_env.sh` 添加到 `/etc/profile` 或用户 `.bashrc`，实现登录自动加载。
> 
> 

---

## 常见问题

### Q1: HDC 连接失败，提示 "no device"

**A**: 请检查：

- 开发板是否正常上电

- USB 数据线是否连接正常

- 主机是否已安装 HDC 驱动

- 执行 `hdc kill-server && hdc start-server` 重启服务

### Q2: 安装脚本提示 "missing file: initenv\.tar\.gz"

**A**: 请确认 4 个 CANN 安装包已通过 `01_push_packages_from_windows.ps1` 推送到设备的 `/storage/temp/` 目录。

### Q3: pyACL 导入失败，提示 "No module named acl"

**A**: 请先执行 `. /cann-install/task2_cann/03_set_cann_env.sh` 加载环境变量，确保 `PYTHONPATH` 包含 CANN 的 Python 站点包路径。

### Q4: npu\-smi 命令不存在

**A**: NPU 驱动需在镜像编译阶段集成。若驱动已安装但命令仍不可用，可尝试：

```bash
export PATH=/var/Ascend/install_cache:$PATH
```

### Q5: torch\_npu 导入失败，提示 "\[libhccl\.so\]\(libhccl\.so\) not found"

**A**: 确保已加载 `03_set_cann_env.sh`，`LD_LIBRARY_PATH` 需包含 `$ASCEND_TOOLKIT_HOME/hccl/lib64`。

### Q6: 安装 Python wheel 时提示 "No space left on device"

**A**: OpenHarmony 系统分区默认空间较小，可：

1. 清理 `/storage/temp/` 下的安装包

2. 将 Python wheel 包存储到 `/data` 分区

3. 编译镜像时扩大系统分区大小

---

## 安装包说明

|安装包|内容说明|
|---|---|
|`initenv.tar.gz`|初始化环境，包含 Python 3\.10 运行时、基础库、驱动初始化脚本|
|`toolkit.tar.gz`|CANN 核心工具集：Toolkit、Runtime、OPP、Compiler、AOE、pyACL、HCCL 等|
|`nnal.tar.gz`|神经网络加速库 ATB（Ascend Transformer Boost）|
|`kernels.tar.gz`|AI Core 算子内核，包含内置算子实现|
|所有组件默认安装到 `/usr/local/Ascend/` 目录下。||

---

## 参考资料

- [CANN 开发者文档](https://www.hiascend.com/document)

- [Ascend PyACL 编程指南](https://www.hiascend.com/document/detail/zh/CANNCommunityEdition/82RC1/development/devguide/aclpython/aclpython_07_0001.html)

- [Torch\-NPU 使用指南](https://gitee.com/ascend/pytorch)

---

## 维护与更新

本脚本集针对 **CANN 8\.2\.RC1** \+ **OpenHarmony 5\.0\.3** \+ **Ascend 310B** 组合验证通过。

- 升级 CANN 版本时，需同步更新安装包并验证安装脚本兼容性

- Python 依赖包版本需与 CANN 版本严格匹配

- 如有问题，请检查各步骤日志输出，定位具体失败环节
