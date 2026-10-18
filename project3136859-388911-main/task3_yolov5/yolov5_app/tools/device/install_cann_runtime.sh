#!/system/bin/sh
set -eu

ARCHIVE=/system/var/cann_runtime_aarch64.tar.gz
CANN_HOME=/usr/local/Ascend/8.2.RC1
PYTHON_HOME=/usr/local/Python
MANIFEST=$CANN_HOME/PAYLOAD_SHA256SUMS
TAR=/system/bin/tar
VERIFY_LOG=/var/log/cann_payload_verify.log
INSTALL_LOG=/var/log/cann_runtime_install.log

mkdir -p /var/log 2>/dev/null || true
if [ -d /var/log ] && : >>"$INSTALL_LOG" 2>/dev/null; then
    exec >>"$INSTALL_LOG" 2>&1
fi
echo "$(date '+%Y-%m-%d %H:%M:%S') CANN runtime install check"

runtime_ready()
{
    [ -x "$PYTHON_HOME/bin/python3.10" ] &&
    [ -r "$PYTHON_HOME/lib/python3.10/site-packages/numpy/__init__.py" ] &&
    [ -r "$PYTHON_HOME/lib/python3.10/site-packages/ais_bench/infer/interface.py" ] &&
    [ -r "$PYTHON_HOME/lib/python3.10/site-packages/aclruntime.cpython-310-aarch64-linux-gnu.so" ] &&
    [ -r "$CANN_HOME/lib64/libascendcl.so" ] &&
    [ -r "$MANIFEST" ]
}

if runtime_ready; then
    echo "CANN runtime payload is already installed"
    exit 0
fi

if [ ! -r "$ARCHIVE" ]; then
    echo "CANN runtime install failed: $ARCHIVE is unavailable" >&2
    exit 66
fi
if [ ! -x "$TAR" ]; then
    echo "CANN runtime install failed: $TAR is unavailable" >&2
    exit 69
fi

mount -o remount,rw / 2>/dev/null || true
mkdir -p /usr/local

echo "Installing image-owned CANN 8.2.RC1 runtime and Python 3.10"
if ! "$TAR" -xzf "$ARCHIVE" -C /; then
    echo "CANN runtime extraction failed; keeping $ARCHIVE for diagnosis" >&2
    exit 74
fi
if ! runtime_ready; then
    echo "CANN runtime validation failed after extraction" >&2
    exit 74
fi
if ! PYTHONHOME="$PYTHON_HOME" \
    LD_LIBRARY_PATH="$PYTHON_HOME/lib:$PYTHON_HOME/thirdparty/lib:/libaarch/aarch64-linux-gnu:${LD_LIBRARY_PATH:-}" \
    "$PYTHON_HOME/bin/python3.10" - "$MANIFEST" >"$VERIFY_LOG" 2>&1 <<'PY'; then
import hashlib
import pathlib
import sys

manifest = pathlib.Path(sys.argv[1])
for entry in manifest.read_text(encoding="utf-8").splitlines():
    expected, relative = entry.split(maxsplit=1)
    target = pathlib.Path("/") / relative.removeprefix("./")
    digest = hashlib.sha256()
    with target.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    actual = digest.hexdigest()
    if actual != expected:
        raise RuntimeError(f"SHA-256 mismatch: {target}: {actual} != {expected}")
print("CANN payload SHA-256 verification passed")
PY
    echo "CANN runtime SHA-256 validation failed; see $VERIFY_LOG" >&2
    exit 74
fi

chmod 0755 "$PYTHON_HOME/bin/python3.10"
rm -f "$ARCHIVE"
sync
echo "CANN runtime payload installed and verified"
