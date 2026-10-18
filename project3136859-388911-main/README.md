# OS 功能挑战赛道 proj31 赛题项目简介

<div align="center">
  <img src="https://readme-typing-svg.demolab.com?font=Fira+Code&size=28&duration=3000&pause=500&color=FF6B6B&center=true&vCenter=true&width=600&lines=你好！欢迎来到我们的项目！;这是合肥工业大学全都做得队的OS赛题提交！" alt="Typing animation" />
</div>

---

## 团队信息

<div align="center">

| 项目 | 内容 |
|------|------|
| 学校 | 合肥工业大学 |
| 队伍ID | T2026103599911150 |
| 队伍名 | 全都做得队 |
| 题号 | proj31 |
| 队伍成员 | 潘孝成，杨洋，芦甲翔 |


</div>

---

## 项目简介

本项目为 **2026年OS国赛"功能挑战"赛题** —— 将 OpenHarmony 标准版适配启智01开发者套件（基于昇腾310B）并完成 NPU 推理功能。

---

## 赛题信息

<div align="center">

| 项目 | 内容 |
|------|------|
| 赛题名称 | 将OpenHarmony标准版适配启智01开发者套件（基于昇腾310B）并完成NPU推理 |
| 赛题类型 | 工程型 |
| 难度等级 | B(普) |

</div>

---

## 核心任务

### 任务1：OpenHarmony系统移植与基础功能适配

将 OpenHarmony 5.0.3 标准系统移植到启智01开发板，实现：
- 系统启动：成功启动 OpenHarmony 图形桌面环境
- 显示输出：支持 HDMI 显示输出，分辨率 1080P
- 输入设备：USB 鼠标/键盘，USB 触摸屏（进阶）

### 任务2：昇腾CANN推理引擎移植

将华为昇腾 CANN 推理运行时（8.2.RC1+）移植到 OpenHarmony 系统：
- 下载 CANN 软件包（ARM64架构）
- 安装 CANN NNRT 组件
- 配置 NPU 设备、驱动、环境变量
- 验证 NPU 可用性

### 任务3：YOLOv5目标检测推理应用开发

基于 CANN 推理引擎，开发 YOLOv5 目标检测应用：
- 模型转换：将 YOLOv5 ONNX 模型转换为 om 格式
- 推理程序：Python 命令行软件，实现图片加载、NPU推理、NMS后处理、绘制检测框
- 图形应用（进阶）：OpenHarmony APP，提供可视化界面展示识别结果

### 任务4：系统性能优化与指标测试

- 系统启动时间优化：基准 50s
- 系统启动初始内存优化：基准 used 1.7GB

---

## 硬件平台

**启智01开发板**（基于昇腾310B处理器）

<div align="center">

| 规格 | 参数 |
|------|------|
| CPU | 4核 TAISHAN V200M @1.6GHz |
| NPU | DaVinci V300 @1.224GHz（20 TOPS INT8） |
| 内存 | 24GB LPDDR4X |
| 编解码 | 20路1080P@30FPS H.264/H.265 |
| 接口 | 2个MIPI-CSI、2个千兆网口、USB 3.0 |

</div>

---

## 目录结构

```
OS_project/
├── README.md                       # 项目总览（团队信息、赛题介绍、硬件平台、技术栈）
├── LaTex_PDF/                      # 撰写PDF技术文档的LaTex项目
├── scripts/                        # 通用工具脚本
├── task1_transplantation/          # 任务1：OpenHarmony 系统移植与基础功能适配
├── task2_cann/                     # 任务2：昇腾 CANN 推理引擎移植
├── task3_yolov5/                   # 任务3：YOLOv5 目标检测推理应用开发
└── task4/                          # 任务4：系统性能优化与指标测试
```

---

## 各模块说明

### LaTex_PDF/ — 用于撰写PDF

基于合肥工业大学学位论文 LaTeX 模板，撰写技术文档。

> 详细说明参见 `LaTex_PDF/README.md`。

---

### scripts/ — 通用工具脚本

提供项目开发过程中常用的辅助脚本，涵盖编译构建、补丁管理、代码提交等操作。

> 详细说明参见 `scripts/README.md`。

---

### task1_transplantation/ — 任务1：OpenHarmony 系统移植

将 OpenHarmony 5.0.3 标准系统移植到启智01开发板（基于昇腾310B），实现系统启动、HDMI 显示输出（1080P）、USB 输入设备支持。同时集成了 CANN 推理引擎和 YOLOv5 目标检测服务的框架支持。

> 详细说明参见 `task1_transplantation/README.md`。

---

### task2_cann/ — 任务2：昇腾 CANN 推理引擎移植

> 详细说明参见 `task2_cann/README.md`。

---

### task3_yolov5/ — 任务3：YOLOv5 目标检测推理应用开发

基于 CANN 推理引擎，开发完整的 YOLOv5 目标检测应用，包括 CLI 推理程序、HTTP 服务端和 OpenHarmony 图形应用。

> 详细说明参见 `task3_yolov5/README.md`。

---

### task4/ — 任务4：系统性能优化与指标测试

> 详细说明参见 `task4/README.md`。

---

## 各任务对应关系

| 赛题任务 | 目录 | 核心内容 |
|---|---|---|
| 任务1：OpenHarmony 系统移植与基础功能适配 | `task1_transplantation/` | 12 个补丁文件，覆盖内核编译、显示驱动、网络配置、CANN 环境集成 |
| 任务2：昇腾 CANN 推理引擎移植 | `task2_cann/` | 7 个脚本，覆盖安装包推送、CANN 安装、环境配置、Python 依赖、NPU 验证 |
| 任务3：YOLOv5 目标检测推理应用开发 | `task3_yolov5/` | CLI 推理程序 + HTTP 服务 + OpenHarmony 图形应用 + 部署脚本 |
| 任务4：系统性能优化与指标测试 | `task4/` | 12 个补丁文件|

---

### 技术栈

<div align="center">
  <img src="https://img.shields.io/badge/OpenHarmony-000000?style=for-the-badge&logo=harmonyos&logoColor=white" alt="OpenHarmony" />
  <img src="https://img.shields.io/badge/ArkTS-3178C6?style=for-the-badge&logo=typescript&logoColor=white" alt="ArkTS" />
  <img src="https://img.shields.io/badge/ArkUI-000000?style=for-the-badge" alt="ArkUI" />
  <img src="https://img.shields.io/badge/CANN-FF6B6B?style=for-the-badge" alt="CANN" />
  <img src="https://img.shields.io/badge/YOLOv5-00A4EF?style=for-the-badge" alt="YOLOv5" />
  <img src="https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white" alt="Python" />
  <img src="https://img.shields.io/badge/DevEco_Studio-00A4EF?style=for-the-badge" alt="DevEco Studio" />
</div>

---

### 许可证

<div align="center">
  <img src="https://img.shields.io/badge/License-GPL%20%7C%20Apache%20%7C%20BSD%20%7C%20Mulan-blue.svg?style=for-the-badge" alt="License" />
  <img src="https://img.shields.io/badge/Docs-CC--BY--SA%204.0-green.svg?style=for-the-badge" alt="CC-BY-SA 4.0" />
</div>

**源代码** 遵循开源协议，采用以下协议：
- [GNU General Public License (GPL)](https://www.gnu.org/licenses/gpl-3.0.html)
- [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- [BSD License](https://opensource.org/licenses/BSD-3-Clause)
- [木兰许可证 (MulanPSL)](https://license.coscl.org.cn/MulanPSL2)

**技术文档与答辩材料** 遵循 [CC-BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) 协议。

---

## 参考资料

- [启智01开发板用户手册](https://www.bj-jc.com.cn/qizhi01/doc/homepage)
- [OpenHarmony 官方文档](https://gitee.com/openharmony/docs)
- [OpenHarmony 社区论坛](https://forums.openharmony.cn/)

---

<div align="center">
  <img src="https://quotes-github-readme.vercel.app/api?type=horizontal&theme=radical" alt="Random Quote" />
</div>

---
