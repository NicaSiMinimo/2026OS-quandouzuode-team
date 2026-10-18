#!/bin/sh

if [ -z "${ASCEND_TOOLKIT_HOME:-}" ]; then
    for candidate in /usr/local/Ascend/8.2.RC1 /usr/local/Ascend/latest /usr/local/Ascend/ascend-toolkit/latest; do
        if [ -d "$candidate" ]; then
            ASCEND_TOOLKIT_HOME=$candidate
            break
        fi
    done
fi

ASCEND_TOOLKIT_HOME=${ASCEND_TOOLKIT_HOME:-/usr/local/Ascend/8.2.RC1}
PYTHON_HOME=${PYTHON_HOME:-/usr/local/Python}

if [ -f "$PYTHON_HOME/set_python_env.sh" ]; then
    _cann_env_flags=$-
    case "$_cann_env_flags" in
        *u*) _cann_env_restore_u=1; set +u ;;
        *) _cann_env_restore_u=0 ;;
    esac
    . "$PYTHON_HOME/set_python_env.sh"
    if [ "$_cann_env_restore_u" = "1" ]; then
        set -u
    fi
    unset _cann_env_flags _cann_env_restore_u
fi

export ASCEND_TOOLKIT_HOME
export ASCEND_HOME_PATH=${ASCEND_HOME_PATH:-$ASCEND_TOOLKIT_HOME}
export ASCEND_AICPU_PATH=${ASCEND_AICPU_PATH:-$ASCEND_TOOLKIT_HOME}
export ASCEND_OPP_PATH=${ASCEND_OPP_PATH:-$ASCEND_TOOLKIT_HOME/opp}
export TOOLCHAIN_HOME=${TOOLCHAIN_HOME:-$ASCEND_TOOLKIT_HOME/toolkit}

export PATH=$ASCEND_TOOLKIT_HOME/bin:$ASCEND_TOOLKIT_HOME/compiler/ccec_compiler/bin:$ASCEND_TOOLKIT_HOME/tools/ccec_compiler/bin:${PATH:-}
export PYTHONPATH=$ASCEND_TOOLKIT_HOME/python/site-packages:$ASCEND_TOOLKIT_HOME/opp/built-in/op_impl/ai_core/tbe:${PYTHONPATH:-}
export LD_LIBRARY_PATH=/usr/lib64:/usr/local/Ascend/driver/lib64:/usr/local/Ascend/driver/lib64/common:/usr/local/Ascend/driver/lib64/driver:${LD_LIBRARY_PATH:-}
export LD_LIBRARY_PATH=$ASCEND_TOOLKIT_HOME/lib64:$ASCEND_TOOLKIT_HOME/lib64/plugin/opskernel:$ASCEND_TOOLKIT_HOME/lib64/plugin/nnengine:$ASCEND_TOOLKIT_HOME/opp/built-in/op_impl/ai_core/tbe/op_tiling/lib/linux/$(uname -m):${LD_LIBRARY_PATH:-}
export LD_LIBRARY_PATH=$ASCEND_TOOLKIT_HOME/tools/aml/lib64:$ASCEND_TOOLKIT_HOME/tools/aml/lib64/plugin:${LD_LIBRARY_PATH:-}
export LD_LIBRARY_PATH=$ASCEND_TOOLKIT_HOME/opp/built-in/op_impl/ai_core/tbe/op_api/lib/linux/aarch64:${LD_LIBRARY_PATH:-}
export LD_LIBRARY_PATH=/usr/local/Python/lib/python3.10/site-packages/torch_npu/lib:${LD_LIBRARY_PATH:-}
export LD_LIBRARY_PATH=$ASCEND_TOOLKIT_HOME/hccl/lib64:${LD_LIBRARY_PATH:-}
