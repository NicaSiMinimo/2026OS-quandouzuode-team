#!/bin/sh
set -eu

WHEEL_DIR=${WHEEL_DIR:-/cann-install/python_packs}
PYTHON_HOME=${PYTHON_HOME:-/usr/local/Python}

if [ -f "$PYTHON_HOME/set_python_env.sh" ]; then
    _wheel_flags=$-
    case "$_wheel_flags" in
        *u*) _wheel_restore_u=1; set +u ;;
        *) _wheel_restore_u=0 ;;
    esac
    . "$PYTHON_HOME/set_python_env.sh"
    if [ "$_wheel_restore_u" = "1" ]; then
        set -u
    fi
    unset _wheel_flags _wheel_restore_u
fi

if [ ! -d "$WHEEL_DIR" ]; then
    echo "wheel directory not found: $WHEEL_DIR" >&2
    exit 1
fi

pip3 install "$WHEEL_DIR/attrs-24.2.0-py3-none-any.whl" || true
pip3 install "$WHEEL_DIR/PyYAML-6.0.2-cp310-cp310-manylinux_2_17_aarch64.manylinux2014_aarch64.whl" || true
pip3 install "$WHEEL_DIR/wheel-0.44.0-py3-none-any.whl" || true
pip3 install "$WHEEL_DIR/psutil-6.1.0-cp36-abi3-manylinux_2_17_aarch64.manylinux2014_aarch64.whl" || true
pip3 install "$WHEEL_DIR/numpy-1.24.0-cp310-cp310-manylinux_2_17_aarch64.manylinux2014_aarch64.whl" || true
pip3 install "$WHEEL_DIR/decorator-5.1.1-py3-none-any.whl" || true
pip3 install "$WHEEL_DIR/mpmath-1.3.0-py3-none-any.whl" || true
pip3 install "$WHEEL_DIR/sympy-1.13.3-py3-none-any.whl" || true
pip3 install "$WHEEL_DIR/scipy-1.14.1-cp310-cp310-manylinux_2_17_aarch64.manylinux2014_aarch64.whl" || true
pip3 install "$WHEEL_DIR/protobuf-3.20.0-cp310-cp310-manylinux2014_aarch64.whl" || true
pip3 install "$WHEEL_DIR/gnureadline-8.2.13-cp310-cp310-manylinux_2_17_aarch64.manylinux2014_aarch64.whl" || true
pip3 install "$WHEEL_DIR/MarkupSafe-3.0.2-cp310-cp310-manylinux_2_28_aarch64.whl" || true
pip3 install "$WHEEL_DIR/MarkupSafe-3.0.2-cp310-cp310-manylinux_2_17_aarch64.manylinux2014_aarch64.whl" || true
pip3 install "$WHEEL_DIR/jinja2-3.1.4-py3-none-any.whl" || true
pip3 install "$WHEEL_DIR/typing_extensions-4.12.2-py3-none-any.whl" || true
pip3 install "$WHEEL_DIR/networkx-3.4.2-py3-none-any.whl" || true
pip3 install "$WHEEL_DIR/filelock-3.16.1-py3-none-any.whl" || true
pip3 install "$WHEEL_DIR/fsspec-2024.10.0-py3-none-any.whl" || true
pip3 install "$WHEEL_DIR/pillow-11.0.0-cp310-cp310-manylinux_2_28_aarch64.whl" || true
pip3 install "$WHEEL_DIR/torchvision-0.16.0-cp310-cp310-linux_aarch64.whl" || true
pip3 install "$WHEEL_DIR/torch-2.1.0-cp310-cp310-manylinux_2_17_aarch64.manylinux2014_aarch64.whl" || true
pip3 install "$WHEEL_DIR/torch_npu-2.1.0.post13.dev20250722-cp310-cp310-manylinux_2_17_aarch64.manylinux2014_aarch64.whl" || true
pip3 install einops || true

pip3 install "$WHEEL_DIR/aclruntime-0.0.2-cp310-cp310-linux_aarch64.whl" || true
pip3 install "$WHEEL_DIR/ais_bench-0.0.2-py3-none-any.whl" || true
pip3 install numpy==1.22.4 || true
pip3 install opencv-python==4.10.0.84 || true
pip3 install ipywidgets || true
pip3 install scikit-video || true

for pkg in "$WHEEL_DIR"/*.whl; do
    [ -f "$pkg" ] || continue
    pip3 install "$pkg" || true
done

python3.10 - <<'PY'
import importlib
for name in ["numpy", "PIL"]:
    importlib.import_module(name)
print("basic python packages are importable")
PY
