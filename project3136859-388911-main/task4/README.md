# 系统性能优化介绍

本目录包含针对 **OpenHarmony 5.0.3 + Ascend 310B** 平台的系统级性能优化补丁，旨在解决嵌入式设备内存紧张和启动耗时问题，通过内核参数调优、启动流程优化、服务按需加载、ZRAM 配置等多种手段，显著降低系统内存占用、缩短启动时间，提升运行稳定性。

所有补丁均基于 `OpenHarmony-5.0.3-Release` 分支制作，适用于 Ascend 310B 开发板的内存受限场景。

---

## 目录结构

```Plain Text
task4/
├── memory/                                                                            # 内存优化补丁
│   ├── base-startup-appspawn-appspawn_preload.json.patch                              # 应用预加载 NAPI 模块精简
│   ├── device-board-ascend-310B-ascendinstall-minirc_sys_init.sh.patch                # 系统初始化脚本：模块按需加载 + MMZ 缩减
│   ├── device-board-ascend-310B-cfg-init.310B.cfg.patch                               # 板级 init.cfg：VM 内存参数 + ZRAM 优化
│   ├── device-board-ascend-310B-ascendinstall-init.cfg.patch                          # 板级 init.cfg：启动流程优化
│   ├── foundation-barrierfree-accessibility-sa_profile-accessibility.cfg.patch        # 无障碍服务 ondemand 启动配置
│   ├── foundation-communication-bluetooth_service-services-bluetooth-etc-init-bluetooth_service.cfg.patch  # 蓝牙服务 ondemand 启动配置
│   ├── foundation-resourceschedule-memmgr-profile-memmgr_config.xml.patch             # 内存管理器（memmgr）阈值配置
│   ├── vendor-ascend-310B-config.json.patch                                           # 产品编译配置（子系统/组件）
│   └── vendor-ascend-310B-preinstall-config-install_list.json.patch                   # 预装应用列表精简
│
└── time/                                                                              # 启动时间优化补丁
    ├── device-board-ascend-310B-ascendinstall-BUILD.gn.patch                          # 构建脚本：新增 post_boot 脚本编译
    ├── device-board-ascend-310B-ascendinstall-ascend_post_boot.sh.patch               # 启动完成后延迟启动非关键服务
    └── device-board-ascend-310B-ascendinstall-init.cfg.patch                          # init.cfg：注册 post_boot 回调
```

---

## 补丁功能说明

### memory/ — 内存优化补丁

| 补丁文件 | 作用 |
|---|---|
| `base-startup-appspawn-appspawn_preload.json.patch` | **精简** NAPI 预加载模块列表。原配置预加载 81 个模块，补丁移除 32 个非必要模块，保留 49 个系统仍需预加载的模块，包括 Ability、Context、Window、Hilog、ResourceManager、sensor、inputMethod 等，减少 appspawn 进程的内存占用和启动开销。 |
| `device-board-ascend-310B-ascendinstall-minirc_sys_init.sh.patch` | **MMZ 缩减 + 模块按需加载**：MMZ 内存预留从 3072M → 2048M；禁用启动时加载 media/DVPP 模块，改为按需加载（节省 50-100MB 内核内存）；模块仅在首次访问设备节点时通过 modprobe 自动加载；注释中保留恢复启动加载的方法。 |
| `device-board-ascend-310B-cfg-init.310B.cfg.patch` | **核心 VM 内存参数调优**：提高 `min_free_kbytes` 从 10MB → 64MB；新增 `extra_free_kbytes = 32MB`、`watermark_scale_factor = 10`；**ZRAM 优化**：使用 lz4 算法、disksize 从 1024M → 512M、mem_limit 768M。 |
| `device-board-ascend-310B-ascendinstall-init.cfg.patch` | **系统参数优化**：将 `rmem_max` 从 16MB 降至 2MB、`RLIMIT_NOFILE` 从 32768 降至 4096、`dirty_background_ratio` 从 5 调至 3，并在启动 dmp_daemon 前等待 `/dev/davinci0`。 |
| `foundation-barrierfree-accessibility-sa_profile-accessibility.cfg.patch` | **修改**无障碍服务配置：移除开机主动启动，改为 ondemand 启动，保留所需权限与数据目录。 |
| `foundation-communication-bluetooth_service-...-bluetooth_service.cfg.patch` | **修改**蓝牙服务配置：移除开机主动启动，改为 ondemand 启动，保留 CAP_NET_ADMIN 权限与数据目录。 |
| `foundation-resourceschedule-memmgr-profile-memmgr_config.xml.patch` | **新增**内存管理器配置：设置可用内存缓冲区阈值（100-200MB）；配置 Zswapd 压缩参数（内存→zram 比例 60%）；定义系统内存等级（purgeable 512MB → critical 200MB）；配置 5 级内存杀进程阈值（500MB → 100MB）；禁用 NAND 寿命限制的 swap 配额。 |
| `vendor-ascend-310B-config.json.patch` | **精简**产品编译配置：保留 bluetooth_service、netmanager_ext、HDF、mindspore、图形栈与 hiview 等必需能力，移除本产品未使用的 msdp 和 castplus 子系统。 |
| `vendor-ascend-310B-preinstall-config-install_list.json.patch` | **精简**预装应用列表为 32 项，保留 SystemUI、Launcher、Settings、Camera、Photos、输入法等核心应用及必要数据组件。 |

### time/ — 启动时间优化补丁

| 补丁文件 | 作用 |
|---|---|
| `device-board-ascend-310B-ascendinstall-BUILD.gn.patch` | 修改构建脚本，新增 `ascend_post_boot.sh` 的编译和安装规则，将脚本安装到 `/system/var/` 目录。 |
| `device-board-ascend-310B-ascendinstall-ascend_post_boot.sh.patch` | **新增** `ascend_post_boot.sh` 脚本：在系统启动完成后延迟启动非关键服务（slogd、sklogd、log-daemon、proc_launcher、iammgr、teecd、tlogcat、dmp_daemon），避免这些服务在启动关键路径上阻塞。脚本还负责复制 cpuset 配置到 cgroup 目录。 |
| `device-board-ascend-310B-ascendinstall-init.cfg.patch` | 从 `post-fs-data` 移除 6 次固定等待、cpuset 复制和 8 个服务的立即启动；注册 post_boot 回调，在 `bootevent.boot.completed=true` 后执行 `ascend_post_boot.sh`。 |

---

## 优化效果汇总

### 内存优化效果

| 优化项 | 优化前 | 优化后 | 内存节省 / 收益 |
|---|---|---|---|
| MMZ 内存预留 | 3072MB | 2048MB | **节省 1024MB** 物理内存 |
| Media/DVPP 内核模块 | 启动时加载 | 按需加载 | **节省 50-100MB** 启动时内存 |
| ZRAM 大小 | 1024MB | 512MB | 减少压缩内存占用，提升交换效率 |
| min_free_kbytes | 10MB | 64MB | 减少 OOM 风险，提升系统稳定性 |
| NAPI 预加载模块 | 81 个 | 49 个 | 减少 appspawn 内存占用 |

**整体内存优化收益：约 1.1GB 物理内存。** 优化后系统启动初始内存占用从 1.7GB 降至约 0.9GB，降幅约 50%。

### 启动时间优化效果

| 指标 | 优化前 | 优化后 | 优化幅度 |
|---|---|---|---|
| 系统启动时间 | 50s | 约 42s | **缩短 16%** |

---

## 使用方法

### 1. 准备 OpenHarmony 源码

确保已完成 task1 里的所有步骤。

### 2. 应用补丁

所有补丁均以 **OpenHarmony 源码根目录** 为基准，按以下顺序应用：

```bash
cd /path/to/openharmony  # 进入源码根目录

# 应用 base 层补丁
patch -p1 < /path/to/task4/memory/base-startup-appspawn-appspawn_preload.json.patch

# 应用 device 层补丁（内存优化）
patch -p1 < /path/to/task4/memory/device-board-ascend-310B-ascendinstall-minirc_sys_init.sh.patch
patch -p1 < /path/to/task4/memory/device-board-ascend-310B-cfg-init.310B.cfg.patch
patch -p1 < /path/to/task4/memory/device-board-ascend-310B-ascendinstall-init.cfg.patch

# 应用 foundation 层补丁
patch -p1 < /path/to/task4/memory/foundation-barrierfree-accessibility-sa_profile-accessibility.cfg.patch
patch -p1 < /path/to/task4/memory/foundation-communication-bluetooth_service-services-bluetooth-etc-init-bluetooth_service.cfg.patch
patch -p1 < /path/to/task4/memory/foundation-resourceschedule-memmgr-profile-memmgr_config.xml.patch

# 应用 vendor 层补丁
patch -p1 < /path/to/task4/memory/vendor-ascend-310B-config.json.patch
patch -p1 < /path/to/task4/memory/vendor-ascend-310B-preinstall-config-install_list.json.patch

# 应用启动时间优化补丁（注意，此步请在完成内存优化补丁应用后再进行）
patch -p1 < /path/to/task4/time/device-board-ascend-310B-ascendinstall-BUILD.gn.patch
patch -p1 < /path/to/task4/time/device-board-ascend-310B-ascendinstall-ascend_post_boot.sh.patch
patch -p1 < /path/to/task4/time/device-board-ascend-310B-ascendinstall-init.cfg.patch
```

> **注意**：如果补丁应用失败，可使用 `patch -p1 --fuzz=3 < patchfile` 放宽匹配，或参照补丁内容手动修改文件。

### 3. 编译镜像

使用本组撰写的编译脚本，位置在仓库目录/scripts/build_and_flash_310B.sh：

```bash
cd /path/to/scripts
./build_and_flash_310B.sh
```

或手动编译，编译完成后拷贝镜像文件到 firmware 固件目录下，执行烧录脚本进行烧录：

```bash
cd /path/to/openharmony
./build.sh --product-name 310B --ccache

# 烧录镜像
sudo ./formatSD310B.sh /dev/sdb
```

### 4. 验证内存优化效果

系统启动后，可通过以下命令验证内存优化效果：

```bash
# 查看内存使用
free -h

# 查看内核模块加载情况（media/dvpp 应未加载）
lsmod | grep -E "media|dvpp"

# 查看 ZRAM 配置
cat /sys/block/zram0/disksize
cat /sys/block/zram0/comp_algorithm

# 查看 VM 参数
cat /proc/sys/vm/min_free_kbytes
```

预期结果：

- `min_free_kbytes` = 65536
- ZRAM disksize = 512MB，使用 lz4 算法
- 启动时无 media/dvpp 相关模块加载

### 5. 验证启动时间优化效果（bootchart）

使用 bootchart 工具采集系统启动过程的性能数据：

```bash
# Step 1：连接开发板进入 shell
hdc shell

# Step 2：启用 bootchart 采集功能
begetctl bootchart enable
begetctl bootchart start

# Step 3：重启开发板开始采集
reboot

# 重启完成后，再次进入 shell
hdc shell

# Step 4：停止采集并查看生成的日志文件
begetctl bootchart stop

cd /data/service/el0/startup/init/
ls -l
# 你会看到 4 个文件：header、proc_diskstats.log、proc_ps.log、proc_stat.log

# Step 5：打包数据
tar -czf bootchart.tgz *

# Step 6：退出 shell，将文件导出到 PC
exit
hdc file recv /data/service/el0/startup/init/bootchart.tgz ./
```

**生成启动分析图表**：

```bash
# 安装 bootchart 可视化工具
pip install pycairo-1.28.0-cp313-cp313-win_amd64.whl

# 解压bootchart-master，把拉取的 bootchart.tgz 文件放到 bootchart-master 目录下，并执行
python -m pybootchartgui.main .\bootchart.tgz
```
最后 bootchart-master 目录下可以读取到 bootchart.png

---

## 常见问题

### Q1: 系统启动后无法使用硬件编解码 / 显示

**A**: 这是正常现象 —— media/DVPP 模块已改为按需加载。首次访问 `/dev/davinci*` 或 `/dev/media*` 设备节点时会自动加载。如需恢复启动时加载，编辑 `minirc_sys_init.sh` 取消注释 `load_media_modules` 和 `load_dvpp_and_qos_modules`。

### Q2: ZRAM 压缩率低，swap 性能差

**A**: 本补丁已使用 lz4 算法（速度优先）。若需更高压缩率，可修改 `init.310B.cfg` 中的 `comp_algorithm` 为 `zstd`，但会增加 CPU 开销。

### Q3: 系统 OOM 杀进程更频繁

**A**: 若出现频繁杀进程，可适当调低 `watermark_scale_factor`（默认 10，范围 1-1000），或增加 `min_free_kbytes`。

### Q4: 启动后部分服务未自动启动

**A**: 这是正常现象 —— slogd、sklogd、log-daemon、proc_launcher、iammgr、teecd、tlogcat、dmp_daemon 等服务已改为延迟启动，会在 `bootevent.boot.completed` 事件触发后由 `ascend_post_boot.sh` 统一启动。如需恢复立即启动，移除 `init.cfg` 中的 post_boot 回调配置。

---

## 注意事项

1. **MMZ 内存调整**：2048M MMZ 预留适用于大多数 AI 推理场景。如需运行超大模型，可恢复为 3072M。

2. **按需加载权衡**：media/DVPP 按需加载节省了启动内存，但首次使用硬件编解码 / 显示时会有 1-2 秒的模块加载延迟。

3. **内存阈值调优**：memmgr_config.xml 中的内存阈值针对 8GB 内存设备优化，若设备内存不同需按比例调整。

4. **预装应用**：install_list.json 中的应用列表可根据实际需求增删，`removable: true` 的应用可在系统中卸载。

5. **延迟启动服务**：`ascend_post_boot.sh` 中的服务列表可根据实际需求增删。如需某个服务在启动时立即加载，将其从列表中移除并恢复 `init.cfg` 中的原始启动配置。

---

## 参考资料

- [OpenHarmony 内存管理指导](https://gitee.com/openharmony/resourceschedule_memmgr)
- [Linux VM 调优指南](https://www.kernel.org/doc/Documentation/sysctl/vm.txt)
- [ZRAM 性能优化](https://www.kernel.org/doc/Documentation/blockdev/zram.txt)
- [Ascend 310B 硬件规格](https://www.hiascend.com/document)
- [OpenHarmony 启动子系统介绍](https://gitee.com/openharmony/startup_init_lite)
- [OpenHarmony 标准系统开机时长优化](https://www.cnblogs.com/openharmony/p/17302295.html)
---

## 维护与更新

本补丁集针对 `OpenHarmony-5.0.3-Release` + Ascend 310B 平台制作。若上游源码或内核版本更新，可能需要重新生成补丁。建议结合 task1_transplantation 补丁集一同使用，以获得完整的系统移植与优化效果。
