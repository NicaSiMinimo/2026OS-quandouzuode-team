#!/bin/sh
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/03_set_cann_env.sh"

mount -o remount,rw / || true

if command -v npu-smi >/dev/null 2>&1; then
    npu-smi info || true
elif [ -x /var/Ascend/install_cache/npu-smi ]; then
    /var/Ascend/install_cache/npu-smi info || true
else
    echo "npu-smi is not found; continue to pyACL verification"
fi

python3.10 "$SCRIPT_DIR/verify_cann_runtime.py" --device-id "${DEVICE_ID:-0}"
