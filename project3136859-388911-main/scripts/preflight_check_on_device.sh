#!/bin/sh
set -u

DEVICE_TEMP=${DEVICE_TEMP:-/storage/temp}
INSTALL_DIR=${INSTALL_DIR:-/cann-install}

fail_count=0
warn_count=0

pass() {
    echo "[PASS] $1"
}

warn() {
    warn_count=$((warn_count + 1))
    echo "[WARN] $1"
}

fail() {
    fail_count=$((fail_count + 1))
    echo "[FAIL] $1"
}

check_cmd() {
    if command -v "$1" >/dev/null 2>&1; then
        pass "command exists: $1"
    else
        fail "command missing: $1"
    fi
}

check_file() {
    if [ -f "$1" ]; then
        pass "file exists: $1"
    else
        fail "file missing: $1"
    fi
}

check_dir_or_warn() {
    if [ -d "$1" ]; then
        pass "directory exists: $1"
    else
        warn "directory missing now: $1"
    fi
}

check_path_or_warn() {
    if [ -e "$1" ]; then
        pass "path exists: $1"
    else
        warn "path missing now: $1"
    fi
}

echo "=== OpenHarmony CANN preflight check ==="
echo "kernel: $(uname -a 2>/dev/null || echo unknown)"
echo "arch: $(uname -m 2>/dev/null || echo unknown)"
echo "user: $(id 2>/dev/null || echo unknown)"

case "$(uname -m 2>/dev/null || echo unknown)" in
    aarch64|arm64) pass "architecture is ARM64/AArch64" ;;
    *) warn "architecture is not ARM64/AArch64; CANN ARM64 packages may not run" ;;
esac

check_cmd mkdir
check_cmd cp
check_cmd rm
check_cmd chmod
check_cmd tar
check_cmd gzip
check_cmd mount
check_cmd uname

if command -v bash >/dev/null 2>&1; then
    pass "bash exists"
else
    warn "bash missing; scripts will use sh where possible, but vendor install scripts may require bash"
fi

mkdir -p "$DEVICE_TEMP" "$INSTALL_DIR" 2>/dev/null || fail "cannot create $DEVICE_TEMP or $INSTALL_DIR"

if mount -o remount,rw / 2>/dev/null; then
    pass "root filesystem can be remounted read-write"
else
    warn "root remount rw failed; if installation writes to /usr/local, fix image mount policy first"
fi

touch "$INSTALL_DIR/.write_test" 2>/dev/null && rm -f "$INSTALL_DIR/.write_test" 2>/dev/null && pass "$INSTALL_DIR is writable" || fail "$INSTALL_DIR is not writable"

check_file "$DEVICE_TEMP/initenv.tar.gz"
check_file "$DEVICE_TEMP/toolkit.tar.gz"
check_file "$DEVICE_TEMP/nnal.tar.gz"
check_file "$DEVICE_TEMP/kernels.tar.gz"

check_dir_or_warn /usr/local/Ascend/driver
check_path_or_warn /dev/davinci0
check_path_or_warn /dev/davinci_manager

if command -v npu-smi >/dev/null 2>&1; then
    pass "npu-smi exists"
    npu-smi info || warn "npu-smi info returned non-zero"
elif [ -x /var/Ascend/install_cache/npu-smi ]; then
    pass "npu-smi exists in /var/Ascend/install_cache"
    /var/Ascend/install_cache/npu-smi info || warn "cached npu-smi info returned non-zero"
else
    warn "npu-smi missing before CANN installation; this is acceptable only if driver package has another verification path"
fi

echo "=== preflight result: fail=$fail_count warn=$warn_count ==="
if [ "$fail_count" -ne 0 ]; then
    exit 1
fi
