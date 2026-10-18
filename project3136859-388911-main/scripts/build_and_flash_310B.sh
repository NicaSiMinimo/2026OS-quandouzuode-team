#!/bin/bash
# 脚本名称: build_and_flash_310B.sh
# 功能: 编译 OpenHarmony 310B 镜像并烧录到 SD 卡
# 特性: 执行成功/失败都会输出时间统计

# ===================== 可直接修改的默认路径 =====================
# 源码根目录
DEFAULT_SOURCE_DIR="${SOURCE_DIR:-/home/hfut/work/5.0.3}"
# 固件存放目录
DEFAULT_FIRMWARE_DIR="$HOME/work/ascend-open-harmony-master/device_board_ascend/310BFormatTest/firmware"
# 烧录脚本目录
DEFAULT_FLASH_DIR="$HOME/work/ascend-open-harmony-master/device_board_ascend/310BFormatTest"
# SD卡设备
DEFAULT_SD_DEV="/dev/sdb"
# ==============================================================

set -euo pipefail  # 严格模式

# 全局时间变量
TOTAL_START=$(date +%s)
STEP1_COST=0
STEP2_COST=0
STEP3_COST=0
FAILED_STEP=""

# 错误捕获函数
error_exit() {
    local exit_code="$1"
    local line_no="$2"
    TOTAL_END=$(date +%s)
    TOTAL_COST=$((TOTAL_END - TOTAL_START))

    echo ""
    echo "=========================================="
    echo " 脚本执行失败！"
    echo " 失败位置: 第 $line_no 行"
    echo " 失败步骤: $FAILED_STEP"
    echo " 结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  -------------------------"
    echo "  步骤1(编译):    ${STEP1_COST}秒 ($((STEP1_COST/60))分$((STEP1_COST%60))秒)"
    echo "  步骤2(拷贝):    ${STEP2_COST}秒"
    echo "  步骤3(烧录):    ${STEP3_COST}秒"
    echo "  -------------------------"
    echo "  总耗时:        ${TOTAL_COST}秒 ($((TOTAL_COST/60))分$((TOTAL_COST%60))秒)"
    echo "=========================================="
    exit "$exit_code"
}

# 捕获错误信号
trap 'error_exit $? $LINENO' ERR

echo "=========================================="
echo "  开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
echo ""

#----------------------------------------------
echo "===== 1. 进入源码目录并编译 ====="
FAILED_STEP="步骤1 - 源码编译"
STEP1_START=$(date +%s)

cd "$DEFAULT_SOURCE_DIR"
sudo ./build.sh --product-name 310B --ccache

STEP1_END=$(date +%s)
STEP1_COST=$((STEP1_END - STEP1_START))
echo ""
echo ">>> 第1步完成，耗时: ${STEP1_COST}秒 ($((STEP1_COST/60))分$((STEP1_COST%60))秒)"
echo ""

#----------------------------------------------
echo "===== 2. 拷贝编译产物到固件目录 ====="
FAILED_STEP="步骤2 - 拷贝镜像"
STEP2_START=$(date +%s)

sudo cp -a "$DEFAULT_SOURCE_DIR"/out/310B/packages/phone/images/. \
     "$DEFAULT_FIRMWARE_DIR"/

STEP2_END=$(date +%s)
STEP2_COST=$((STEP2_END - STEP2_START))
echo ""
echo ">>> 第2步完成，耗时: ${STEP2_COST}秒"
echo ""

#----------------------------------------------
echo "===== 3. 进入工具目录并烧录 ====="
FAILED_STEP="步骤3 - SD卡烧录"
STEP3_START=$(date +%s)

cd "$DEFAULT_FLASH_DIR"
sudo ./formatSD310B.sh "$DEFAULT_SD_DEV"

STEP3_END=$(date +%s)
STEP3_COST=$((STEP3_END - STEP3_START))
echo ""
echo ">>> 第3步完成，耗时: ${STEP3_COST}秒"
echo ""

#----------------------------------------------
# 成功结束统计
TOTAL_END=$(date +%s)
TOTAL_COST=$((TOTAL_END - TOTAL_START))

echo "=========================================="
echo "  全部完成"
echo "  结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  -------------------------"
echo "  步骤1(编译):    ${STEP1_COST}秒 ($((STEP1_COST/60))分$((STEP1_COST%60))秒)"
echo "  步骤2(拷贝):    ${STEP2_COST}秒"
echo "  步骤3(烧录):    ${STEP3_COST}秒"
echo "  -------------------------"
echo "  总耗时:        ${TOTAL_COST}秒 ($((TOTAL_COST/60))分$((TOTAL_COST%60))秒)"
echo "=========================================="
