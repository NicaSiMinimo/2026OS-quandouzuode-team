#!/bin/sh
set -eu

DEVICE_TEMP=${DEVICE_TEMP:-/storage/temp}
INSTALL_DIR=${INSTALL_DIR:-/cann-install}
ASCEND_INSTALL_DIR=${ASCEND_INSTALL_DIR:-/usr/local/Ascend}
PYTHON_INSTALL_DIR=${PYTHON_INSTALL_DIR:-/usr/local/Python}
SHELL_BIN=${SHELL_BIN:-sh}

need_file() {
    if [ ! -f "$1" ]; then
        echo "missing file: $1" >&2
        exit 1
    fi
}

extract_tgz() {
    archive="$1"
    target="$2"
    if tar -xzvf "$archive" -C "$target"; then
        return 0
    fi
    echo "tar -z failed for $archive, retry with gzip pipeline" >&2
    gzip -dc "$archive" | tar -xvf - -C "$target"
}

detect_ascend_toolkit_home() {
    for candidate in "$ASCEND_INSTALL_DIR/8.2.RC1" "$ASCEND_INSTALL_DIR/latest" "$ASCEND_INSTALL_DIR/ascend-toolkit/latest"; do
        if [ -d "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    echo "$ASCEND_INSTALL_DIR/latest"
}

install_toolkit_part() {
    part_name="$1"
    installer="$2"
    args="$3"
    part_dir="$INSTALL_DIR/toolkit/run_package/$part_name"
    if [ -d "$part_dir" ]; then
        echo "installing $part_name"
        cd "$part_dir"
        chmod -R +x . || true
        $SHELL_BIN -c "$installer -- -- $args"
        rm -rf "$part_dir"
    else
        echo "skip $part_name: $part_dir not found"
    fi
}

need_file "$DEVICE_TEMP/initenv.tar.gz"
need_file "$DEVICE_TEMP/toolkit.tar.gz"
need_file "$DEVICE_TEMP/nnal.tar.gz"
need_file "$DEVICE_TEMP/kernels.tar.gz"

mount -o remount,rw / || true
mkdir -p "$INSTALL_DIR"
mkdir -p "$ASCEND_INSTALL_DIR"

echo "extracting initenv"
extract_tgz "$DEVICE_TEMP/initenv.tar.gz" "$INSTALL_DIR"
if [ -d "$INSTALL_DIR/initenv" ]; then
    cp -rf "$INSTALL_DIR/initenv"/* "$INSTALL_DIR"/
fi

cd "$INSTALL_DIR"
chmod 777 ./*.sh 2>/dev/null || true
if [ -f "$INSTALL_DIR/initmodel.sh" ]; then
    if command -v bash >/dev/null 2>&1; then
        INIT_SHELL=bash
    else
        INIT_SHELL=sh
    fi
    "$INIT_SHELL" "$INSTALL_DIR/initmodel.sh" || {
        echo "initmodel.sh failed; edit the script to disable /var/dmp_daemon if your image does not provide it" >&2
        exit 1
    }
fi

if [ -d "$INSTALL_DIR/Python" ]; then
    echo "installing Python runtime"
    rm -rf "$PYTHON_INSTALL_DIR"
    mkdir -p "$(dirname "$PYTHON_INSTALL_DIR")"
    cp -rf "$INSTALL_DIR/Python" "$PYTHON_INSTALL_DIR"
    _install_flags=$-
    case "$_install_flags" in
        *u*) _install_restore_u=1; set +u ;;
        *) _install_restore_u=0 ;;
    esac
    . "$PYTHON_INSTALL_DIR/set_python_env.sh"
    if [ "$_install_restore_u" = "1" ]; then
        set -u
    fi
    unset _install_flags _install_restore_u
    chmod +x "$PYTHON_INSTALL_DIR"/bin/* || true
    "$PYTHON_INSTALL_DIR/bin/python3.10" -m ensurepip --upgrade || true
fi

echo "extracting toolkit"
extract_tgz "$DEVICE_TEMP/toolkit.tar.gz" "$INSTALL_DIR"

install_toolkit_part "toolkit" "./toolkit/scripts/install.sh" "--full"
install_toolkit_part "runtime" "./runtime/scripts/install.sh" "--full"
install_toolkit_part "opp" "./opp/script/install.sh" "--full"
install_toolkit_part "ncs" "./ncs/script/install.sh" "--full"
install_toolkit_part "compiler" "./compiler/scripts/install.sh" "--full"
install_toolkit_part "aoe" "./aoe/script/install.sh" "--full"
install_toolkit_part "pyACL" "./script/install.sh" "--full"
install_toolkit_part "test-ops" "./script/install.sh" "--full --install-path=$ASCEND_INSTALL_DIR/"
install_toolkit_part "hccl" "./hccl/scripts/install.sh" "--full"
rm -rf "$INSTALL_DIR/toolkit"

echo "extracting nnal"
extract_tgz "$DEVICE_TEMP/nnal.tar.gz" "$INSTALL_DIR"
if [ -d "$INSTALL_DIR/nnal/run_package/atb" ]; then
    export ASCEND_TOOLKIT_HOME=${ASCEND_TOOLKIT_HOME:-$(detect_ascend_toolkit_home)}
    export ASCEND_HOME_PATH=$ASCEND_TOOLKIT_HOME
    cd "$INSTALL_DIR/nnal/run_package/atb"
    chmod -R +x . || true
    ./install.sh -- -- --install
fi
rm -rf "$INSTALL_DIR/nnal"

echo "extracting kernels"
extract_tgz "$DEVICE_TEMP/kernels.tar.gz" "$INSTALL_DIR"
if [ -d "$INSTALL_DIR/kernels/run_package/opp_kernel" ]; then
    cd "$INSTALL_DIR/kernels/run_package/opp_kernel"
    chmod -R +x . || true
    ./script/install.sh -- -- --full
fi
rm -rf "$INSTALL_DIR/kernels"

rm -f "$DEVICE_TEMP/toolkit.tar.gz" "$DEVICE_TEMP/initenv.tar.gz" "$DEVICE_TEMP/nnal.tar.gz" "$DEVICE_TEMP/kernels.tar.gz"

echo "CANN installation finished. Run: . /cann-install/task2_cann/03_set_cann_env.sh before inference."
