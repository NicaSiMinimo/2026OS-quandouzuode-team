#!/bin/sh
set -eu

SERVICE_DIR=${SERVICE_DIR:-/data/yolov5_napi}
SERVICE_SCRIPT=${SERVICE_SCRIPT:-/vendor/etc/yolo_acl_service.py}
PID_FILE=$SERVICE_DIR/yolo_acl_service.pid
LOG_FILE=$SERVICE_DIR/yolo_acl_service.log
PYTHON_BIN=${PYTHON_BIN:-/usr/local/Python/bin/python3.10}
ENV_SCRIPT=${ENV_SCRIPT:-/vendor/etc/yolo_cann_env.sh}

mkdir -p "$SERVICE_DIR"
if [ ! -r "$ENV_SCRIPT" ]; then
    echo "Image-owned CANN environment is missing: $ENV_SCRIPT" >&2
    exit 1
fi
. "$ENV_SCRIPT"
if [ ! -x "$PYTHON_BIN" ]; then
    echo "Image-owned Python is missing or not executable: $PYTHON_BIN" >&2
    exit 1
fi
if [ -z "${ASCENDCL_LIBRARY:-}" ] || [ ! -r "$ASCENDCL_LIBRARY" ]; then
    echo "Image-owned CANN runtime is missing: ${ASCENDCL_LIBRARY:-unset}" >&2
    exit 1
fi
if [ ! -f "$SERVICE_SCRIPT" ]; then
    echo "YOLO ACL service script is missing: $SERVICE_SCRIPT" >&2
    exit 1
fi

if [ -f "$PID_FILE" ]; then
    old_pid=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        echo "YOLO ACL service already running, pid=$old_pid"
        exit 0
    fi
    rm -f "$PID_FILE"
fi

setsid "$PYTHON_BIN" "$SERVICE_SCRIPT" \
    >>"$LOG_FILE" 2>&1 </dev/null &
service_pid=$!
echo "$service_pid" > "$PID_FILE"

sleep 1
if ! kill -0 "$service_pid" 2>/dev/null; then
    echo "YOLO ACL service failed to start; see $LOG_FILE" >&2
    tail -n 40 "$LOG_FILE" >&2 || true
    exit 1
fi

echo "YOLO ACL service started, pid=$service_pid, log=$LOG_FILE"
