# 启智01 HDC USB Gadget 启动修复补丁

## 问题现象

Windows 电脑通过 USB 连接启智01（昇腾 310B，OpenHarmony 5.0.3）后，
`hdc list targets` 为空，`hdc shell` 不可用；手动补建 USB gadget 后
能恢复，但重启复现。

## 根因（依据《delegation_for_source_machine》板端证据）

1. **USB gadget 无人创建**：板上 `/vendor/etc/init/` 下只有
   `init.usb.configfs.cfg`，它直接对 `/config/usb_gadget/g1/functions/...`
   执行 mkdir，但父目录 g1 不存在；而负责完整初始化的
   `init.310B.usb.cfg` 未出现在板上，导致 ffs.hdc、UDC 绑定全部失效；
2. **chip_prod 分区未自动挂载**：内核 cmdline 只有
   `ohos.required_mount.userdata` 与 `ohos.required_mount.vendor`，
   没有 `ohos.required_mount.chip_prod`，因此
   `hardware_310B.para` 里的 `persist.hdc.control` 默认值从未被加载，
   刷完 userdata 即丢失。

板端表现：`/dev/usb-ffs/hdc` 为空、`UDC not attached`、
`sys.usb.ffs.ready` 不存在、`persist.hdc.control` 不存在、
`/chip_prod` 未挂载。

## 修复内容（5 个补丁）

### 0001：内核 cmdline 增加 chip_prod 挂载

文件：`dtb/dts/hi1910b/hi1910BL/hi1910B-asic-M275-B25.dts`

bootargs 增加：

```text
ohos.required_mount.chip_prod=/dev/block/mmcblk1p3@/chip_prod@ext4@ro,barrier=1@wait,required
```

init 的 required mount 只解析内核 cmdline 的 `ohos.required_mount.*`
（`LoadFstabFromCommandLine`），**不读取 fstab.310B**，因此必须在 dts
bootargs 中声明。

### 0002：init.usb.configfs.cfg 完整 gadget 初始化放进 hdc 触发 job

文件：`drivers/peripheral/usb/cfg/init.usb.configfs.cfg`

板端实测：vendor cfg 的 boot job **开机时不执行**，真正执行的是
`param:sys.usb.config=hdc && param:sys.usb.configfs=1` 参数触发 job
（hdcd 也是由它启动的）。因此把完整的 gadget 初始化放进该参数触发 job：

```json
"name" : "param:sys.usb.config=hdc && param:sys.usb.configfs=1",
"cmds" : [
    "stop hdcd",
    "mkdir /dev/usb-ffs 0770 shell shell",
    "mkdir /dev/usb-ffs/hdc 0770 shell shell",
    "mkdir /config/usb_gadget/g1",
    "mkdir /config/usb_gadget/g1/strings/0x409 0770",
    "mkdir /config/usb_gadget/g1/functions/ffs.hdc",
    "mkdir /config/usb_gadget/g1/configs/b.1 0770 shell shell",
    "mkdir /config/usb_gadget/g1/configs/b.1/strings/0x409 0770 shell shell",
    "write /config/usb_gadget/g1/idVendor 0x2207",
    "write /config/usb_gadget/g1/idProduct 0x5000",
    "write /config/usb_gadget/g1/os_desc/use 1",
    "write /config/usb_gadget/g1/bcdDevice 0x0223",
    "write /config/usb_gadget/g1/bcdUSB 0x0300",
    "copy /sys/block/mmcblk1/device/cid /config/usb_gadget/g1/strings/0x409/serialnumber",
    "write /config/usb_gadget/g1/strings/0x409/manufacturer Hisilicon",
    "write /config/usb_gadget/g1/strings/0x409/product \"HDC Device\"",
    "write /config/usb_gadget/g1/os_desc/b_vendor_code 0x1",
    "write /config/usb_gadget/g1/os_desc/qw_sign MSFT100",
    "write /config/usb_gadget/g1/configs/b.1/MaxPower 500",
    "symlink /config/usb_gadget/g1/configs/b.1 /config/usb_gadget/g1/os_desc/b.1",
    "mount functionfs hdc /dev/usb-ffs/hdc uid=2000,gid=2000",
    "sleep 1",
    "start hdcd"
]
```

实机修正要点：
- **删除** job 内部 `setparam sys.usb.configfs 1`——它反复触发自身，
  导致 mount functionfs 失败（err 16）出现 73 次；
- **不依赖** `setparam sys.usb.controller`（系统已提供该值）；
- 挂载 functionfs 前 `stop hdcd`，挂载后 `sleep 1` 再 `start hdcd`，
  否则 hdcd 在挂载前已启动，只有 ep0 没有 ep1/ep2。

boot job 第一条仍保留 `mkdir /config/usb_gadget/g1`（幂等兜底，
init 内建 mkdir 不支持 `-p` 但对 EEXIST 容错）。
原 `init.310B.usb.cfg` 的 boot job 不再作为初始化依赖。

### 0003：默认参数写入 chip_prod 参数文件

文件：`vendor/ascend/310B/etc/param/hardware_310B.para`

新增：

```text
persist.hdc.control = "true"
persist.hdc.mode.usb = "enable"
persist.hdc.mode.tcp = "disable"
```

该文件由 `vendor/ascend/310B/etc/BUILD.gn` 安装到 chip_prod 的
`etc/param/` 目录，随 chip_prod 镜像发布。

### 0004：烧录脚本刷写 chip_prod 到 p3 分区

文件：`device_board_ascend/310BFormatTest/formatSD310B.sh`

`write310BOHimg` 增加将 `chip_prod.img` 写入 p3 分区
（p3 为 100MB 预留分区，chip_prod.img 约 50MB，可容纳）。

### 0005：system init 开机 USB gadget boot job（实测补充）

实机复测发现：vendor 的参数触发 job 只在参数变化时执行，
开机时参数已满足条件，因此**开机不触发**。永久修复必须在 system init
加开机一定执行的 boot job。

文件：

- `base/startup/init/services/etc/init.310B.usb.cfg`（新增）：
  boot job 完整建出 g1、ffs.hdc、挂 functionfs、`sleep 1` 后
  `start hdcd`（内容与 A.3 清单一致）；
- `base/startup/init/services/etc/BUILD.gn`：
  新增 `ohos_prebuilt_etc("init.310B.usb.cfg")`，
  `relative_install_dir = "init"`，打包进
  `/system/etc/init/init.310B.usb.cfg`（system init 自动扫描该目录）。

构建后必须确认：

```sh
ls /system/etc/init/init.310B.usb.cfg
```

vendor 侧 `init.usb.configfs.cfg` 的参数触发 job 保留，
用于运行时切换（内容见 0002）。

## 应用方法

### 5.0.3 源码

在工程仓库根目录执行。这里使用 `patch`，因为 OpenHarmony 源码根目录
本身不是单一 Git 仓库；0001、0002、0003、0005 均已统一为 5.0.3
源码根目录相对路径：

```bash
PROJECT_DIR=$PWD
SOURCE_DIR=/home/hfut/work/5.0.3
patch -d "$SOURCE_DIR" -p1 < "$PROJECT_DIR/task5_hdc_usb/0001-dtb-dts-hi1910B-asic-M275-B25-add-chip_prod-required-mount.patch"
patch -d "$SOURCE_DIR" -p1 < "$PROJECT_DIR/task5_hdc_usb/0002-drivers-peripheral-usb-cfg-init.usb.configfs.cfg-ensure-g1.patch"
patch -d "$SOURCE_DIR" -p1 < "$PROJECT_DIR/task5_hdc_usb/0003-vendor-ascend-310B-etc-param-hardware_310B.para-add-hdc-defaults.patch"
patch -d "$SOURCE_DIR" -p1 < "$PROJECT_DIR/task5_hdc_usb/0005-base-startup-init-services-etc-add-system-init-usb-boot-job.patch"
```

重新构建（涉及 dts，会重建内核 dtb）：

```bash
cd /home/hfut/work/5.0.3
./build.sh --product-name 310B --ccache --ninja-args=-j8
```

### 烧录工具

0004 属于独立烧录工具仓库，在工程仓库根目录执行：

```bash
PROJECT_DIR=$PWD
FLASH_DIR=/home/hfut/work/ascend-open-harmony-master
patch -d "$FLASH_DIR" -p1 < "$PROJECT_DIR/task5_hdc_usb/0004-310BFormatTest-formatSD310B.sh-flash-chip_prod-to-p3.patch"
```

重新拷贝镜像到固件目录并执行 `formatSD310B.sh` 烧录
（注意：会重建 SD 分区，请先备份数据）。

## 验收标准（重启后不手动干预）

```sh
ls -d /config/usb_gadget/g1
cat /config/usb_gadget/g1/UDC          # a5080000.hiusbc1
param get sys.usb.ffs.ready            # 1
param get persist.hdc.control          # true
param get persist.hdc.mode.usb         # enable
mount | grep chip_prod                 # /dev/.../p3 on /chip_prod
```

Windows 侧 `hdc list targets` 能列出设备，`hdc shell` 可进入，
重启后不丢失。设备管理器应出现 `VID_2207 & PID_5000` 的 `HDC Device`。

## 临时恢复当前板子（一次性，重启失效）

串口 root shell 手动执行委托文档第 5 节命令，或参考
`hdc_windows_troubleshooting.md` 中的板端步骤。
