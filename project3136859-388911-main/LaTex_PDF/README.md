# 合肥工业大学全都做得队 技术文档 LaTeX 项目

本项目基于合肥工业大学学位论文 LaTeX 模板（[HFUT\_Thesis](https://github.com/HFUTTUG/HFUT_Thesis)）改写。

## 项目结构

```
HFUT_Thesis/
├── main.tex              # 主入口文件
├── hfutsetup.tex         # 文档配置（标题、作者、宏包等）
├── hfutthesis.cls        # 模板类文件（已修改）
├── main.pdf              # 编译输出
├── chapters/             # 各章节内容
│   ├── changelog.tex     # 文档更新说明
│   ├── chapter1.tex      # 第一章 移植记录
│   ├── chapter2.tex      # 第二章 昇腾 CANN 推理引擎移植
│   ├── chapter3.tex      # 第三章 YOLOv5 目标检测推理应用开发
│   ├── chapter4.tex      # 第四章 系统性能优化与指标测试
│   ├── appendix.tex      # 附录 参考链接
│   └── debug_log.tex     # 源码排查、构建故障与实机验证记录
├── figures/              # 图片资源
└── bib/                  # 参考文献数据库
```

## 编译环境

- TeX Live 2017 及以上版本（推荐 TeX Live 2024）
- 编译引擎：XeLaTeX
- **不支持** CTeX 套装

## 编译方法

在项目根目录下执行：

```bash
# 编译技术文档（需执行两次以生成目录）
xelatex -interaction=nonstopmode main.tex
xelatex -interaction=nonstopmode main.tex

# 或使用 latexmk 自动处理多次编译
latexmk -xelatex main.tex
```

清理由编译产生的临时文件：

```bash
latexmk -c
```

## 原始模板

- GitHub Releases：https://github.com/HFUTTUG/HFUT_Thesis/releases
- Overleaf 模板：https://www.overleaf.com/latex/templates/hfut-thesis/ythwdqdkpvkp
- 模板新手指南：https://github.com/HFUTTUG/HFUT_Thesis/wiki/新手指南
