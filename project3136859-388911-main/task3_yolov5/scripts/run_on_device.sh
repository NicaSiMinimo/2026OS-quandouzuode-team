#!/bin/sh
set -eu

APP_DIR=${APP_DIR:-/cann-install/yolov5_cli}
MODEL=${MODEL:-$APP_DIR/models/yolov5s_ascend310b.om}
IMAGE=${IMAGE:-$APP_DIR/images/test.jpg}
OUTPUT=${OUTPUT:-$APP_DIR/output}
DEVICE_ID=${DEVICE_ID:-0}
IMG_SIZE=${IMG_SIZE:-640}
CONF_THRES=${CONF_THRES:-0.25}
IOU_THRES=${IOU_THRES:-0.45}

if [ -f /cann-install/03_set_cann_env.sh ]; then
    . /cann-install/03_set_cann_env.sh
elif [ -f /cann-install/set_cann_env.sh ]; then
    . /cann-install/set_cann_env.sh
elif [ -f /cann-install/task2_cann/03_set_cann_env.sh ]; then
    . /cann-install/task2_cann/03_set_cann_env.sh
fi

cd "$APP_DIR"
mkdir -p "$OUTPUT"
python3.10 main.py \
  --backend ais_bench \
  --device-id "$DEVICE_ID" \
  --model "$MODEL" \
  --image "$IMAGE" \
  --output "$OUTPUT" \
  --img-size "$IMG_SIZE" \
  --conf-thres "$CONF_THRES" \
  --iou-thres "$IOU_THRES" \
  --save-txt \
  --json "$OUTPUT/result.json"
