#!/bin/bash
# 构建后自动验证：核对 HDC 修复相关的所有产物是否真正进入镜像
# 用法：bash scripts/verify_hdc_fix_build.sh [源码根目录，默认 /home/hfut/work/5.0.3]
# 在 5.0.3 构建完成后、烧录前执行，避免"编译完才发现缺东西"。

SRC="${1:-/home/hfut/work/5.0.3}"
PKG=$SRC/out/310B/packages/phone
FAIL=0

check() {
    local desc="$1" path="$2"
    if [ -e "$path" ]; then
        echo "[OK]   $desc -> $path"
    else
        echo "[MISS] $desc -> $path"
        FAIL=1
    fi
}

check_string() {
    local desc="$1" file="$2" pattern="$3"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo "[OK]   $desc（$file 含 $pattern）"
    else
        echo "[MISS] $desc（$file 缺少 $pattern）"
        FAIL=1
    fi
}

echo "===== HDC 修复产物验证 ====="

echo "--- 1. system.img 相关 ---"
check "system init cfg 进包" "$PKG/system/etc/init/init.310B.usb.cfg"

echo "--- 2. vendor.img 相关 ---"
check "vendor cfg 存在" "$PKG/vendor/etc/init/init.usb.configfs.cfg"
check "vendor 板级 cfg 存在" "$PKG/vendor/etc/init.310B.usb.cfg"
check_string "vendor cfg 含 stop hdcd" "$PKG/vendor/etc/init/init.usb.configfs.cfg" '"stop hdcd"'
check_string "vendor cfg 含 sleep 1" "$PKG/vendor/etc/init/init.usb.configfs.cfg" '"sleep 1"'
if grep -q 'setparam sys.usb.configfs 1' "$PKG/vendor/etc/init/init.usb.configfs.cfg" 2>/dev/null; then
    echo "[FAIL] vendor cfg 仍含 setparam sys.usb.configfs 1（会自触发循环）"
    FAIL=1
else
    echo "[OK]   vendor cfg 无 setparam sys.usb.configfs 1"
fi

echo "--- 3. chip_prod.img 相关 ---"
# 镜像内文件为 root 只读，改用构建产物 obj 副本核对（同一打包来源）
CHIP_PARAS=$(find "$SRC/out/310B/obj" -name 'hardware_310B.para' 2>/dev/null | head -1)
if [ -n "$CHIP_PARAS" ]; then
    check_string "persist.hdc.control" "$CHIP_PARAS" 'persist.hdc.control = "true"'
    check_string "persist.hdc.mode.usb" "$CHIP_PARAS" 'persist.hdc.mode.usb = "enable"'
    check_string "persist.hdc.mode.tcp" "$CHIP_PARAS" 'persist.hdc.mode.tcp = "disable"'
else
    echo "[MISS] 找不到 chip_prod 参数构建产物（obj 副本）"
    FAIL=1
fi

echo "--- 4. dt.img 相关 ---"
if strings "$SRC/kernel/linux/Ascend310B-5.10/Ascend310B-source/dtb/dtbtool/tmp/dtbs/hi1910B-asic-M275-B25.dtb" 2>/dev/null | grep -q 'ohos.required_mount.chip_prod'; then
    echo "[OK]   dtb 含 chip_prod required_mount"
else
    echo "[MISS] dtb 缺少 chip_prod required_mount（dts 未重建）"
    FAIL=1
fi

echo "--- 5. 产物时间戳（应晚于源码修改） ---"
for img in system.img vendor.img chip_prod.img dt.img; do
    if [ -e "$SRC/out/310B/packages/phone/images/$img" ]; then
        echo "  $img: $(stat -c '%y' "$SRC/out/310B/packages/phone/images/$img")"
    else
        echo "[MISS] 缺少 $img"
        FAIL=1
    fi
done

echo ""
if [ $FAIL -eq 0 ]; then
    echo "全部通过：HDC 修复产物已完整进入镜像，可以烧录。"
    exit 0
else
    echo "存在缺失：请先修复上述 [MISS] 项再烧录。"
    exit 1
fi
