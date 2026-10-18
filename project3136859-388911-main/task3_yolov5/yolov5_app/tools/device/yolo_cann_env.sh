#!/system/bin/sh

# Image-owned environment for the loopback YOLO CANN service.
if [ -z "${ASCEND_TOOLKIT_HOME:-}" ]; then
    for candidate in \
        /usr/local/Ascend/8.2.RC1 \
        /usr/local/Ascend/latest \
        /usr/local/Ascend/ascend-toolkit/latest; do
        if [ -d "$candidate" ]; then
            ASCEND_TOOLKIT_HOME=$candidate
            break
        fi
    done
fi

ASCEND_TOOLKIT_HOME=${ASCEND_TOOLKIT_HOME:-/usr/local/Ascend/8.2.RC1}
PYTHON_HOME=${PYTHON_HOME:-/usr/local/Python}

if [ -f "$PYTHON_HOME/set_python_env.sh" ]; then
    _yolo_env_flags=$-
    case "$_yolo_env_flags" in
        *u*) _yolo_env_restore_u=1; set +u ;;
        *) _yolo_env_restore_u=0 ;;
    esac
    . "$PYTHON_HOME/set_python_env.sh"
    if [ "$_yolo_env_restore_u" = "1" ]; then
        set -u
    fi
    unset _yolo_env_flags _yolo_env_restore_u
fi

ASCENDCL_LIBRARY=
for candidate in \
    "$ASCEND_TOOLKIT_HOME/lib64/libascendcl.so" \
    "$ASCEND_TOOLKIT_HOME/runtime/lib64/libascendcl.so" \
    /usr/local/Ascend/runtime/lib64/libascendcl.so; do
    if [ -r "$candidate" ]; then
        ASCENDCL_LIBRARY=$candidate
        break
    fi
done

export ASCEND_TOOLKIT_HOME
export ASCEND_HOME_PATH=${ASCEND_HOME_PATH:-$ASCEND_TOOLKIT_HOME}
export ASCEND_AICPU_PATH=${ASCEND_AICPU_PATH:-$ASCEND_TOOLKIT_HOME}
export TOOLCHAIN_HOME=${TOOLCHAIN_HOME:-$ASCEND_TOOLKIT_HOME/toolkit}
export PYTHON_HOME
export ASCENDCL_LIBRARY

if [ -d "$ASCEND_TOOLKIT_HOME/opp" ]; then
    export ASCEND_OPP_PATH=${ASCEND_OPP_PATH:-$ASCEND_TOOLKIT_HOME/opp}
else
    unset ASCEND_OPP_PATH 2>/dev/null || true
fi

export PATH=$PYTHON_HOME/bin:$ASCEND_TOOLKIT_HOME/bin:$ASCEND_TOOLKIT_HOME/compiler/ccec_compiler/bin:${PATH:-}
export PYTHONPATH=$PYTHON_HOME/lib/python3.10/site-packages:$ASCEND_TOOLKIT_HOME/python/site-packages:$ASCEND_TOOLKIT_HOME/opp/built-in/op_impl/ai_core/tbe:${PYTHONPATH:-}
export LD_LIBRARY_PATH=/libaarch64/aarch64-linux-gnu:/usr/lib64:/usr/local/Ascend/driver/lib64:/usr/local/Ascend/driver/lib64/common:/usr/local/Ascend/driver/lib64/driver:${LD_LIBRARY_PATH:-}
export LD_LIBRARY_PATH=$PYTHON_HOME/lib:$ASCEND_TOOLKIT_HOME/lib64:$ASCEND_TOOLKIT_HOME/lib64/plugin/opskernel:$ASCEND_TOOLKIT_HOME/lib64/plugin/nnengine:${LD_LIBRARY_PATH:-}
export LD_LIBRARY_PATH=$ASCEND_TOOLKIT_HOME/opp/built-in/op_impl/ai_core/tbe/op_tiling/lib/linux/aarch64:$ASCEND_TOOLKIT_HOME/opp/built-in/op_impl/ai_core/tbe/op_api/lib/linux/aarch64:${LD_LIBRARY_PATH:-}
