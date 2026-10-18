#!/bin/bash
# 启智01 HDMI 音频上板验证脚本
# 用法（板端 shell 或 hdc shell 下）：
#   sh /tmp/hdmi_audio_board_check.sh
set +e

echo "===== [1] ALSA 声卡 ====="
cat /proc/asound/cards 2>/dev/null
echo

echo "===== [2] 音频/HDMI 内核模块 ====="
echo "--- /var/davinci/driver 中的相关模块 ---"
ls /var/davinci/driver/ 2>/dev/null | grep -E 'ascend_310b|ascend_vdp'
echo "--- 当前已加载 ---"
cat /proc/modules 2>/dev/null | grep -E 'ascend_310b|ascend_vdp|drv_hdmi' | awk '{print $1}'
echo

echo "===== [3] 设备树 sound 节点 ====="
DT_PATH=""
if [ -d /sys/firmware/devicetree/base ]; then
    DT_PATH=/sys/firmware/devicetree/base
elif [ -d /proc/device-tree ]; then
    DT_PATH=/proc/device-tree
fi
if [ -n "$DT_PATH" ] && [ -d "$DT_PATH/sound" ]; then
    echo "sound 节点存在："
    echo -n "compatible = "
    tr '\0' ' ' < "$DT_PATH/sound/compatible" 2>/dev/null
    echo
    for c in ascend310b_codec ascend310b_platform; do
        if [ -d "$DT_PATH/sound/$c" ]; then
            echo -n "$c compatible = "
            tr '\0' ' ' < "$DT_PATH/sound/$c/compatible" 2>/dev/null
            echo
        fi
    done
else
    echo "!!! 设备树中无 sound 节点（DT 未包含音频节点，或路径不同）"
fi
echo

echo "===== [4] 平台设备与驱动绑定 ====="
ls -d /sys/bus/platform/devices/*sound* /sys/bus/platform/devices/*audio* /sys/bus/platform/devices/*hdmi* 2>/dev/null
echo "--- 相关 driver 目录 ---"
ls /sys/bus/platform/drivers/ 2>/dev/null | grep -iE 'ascend|soc-audio|hdmi|aiao'
for d in /sys/bus/platform/devices/sound /sys/bus/platform/devices/*audio* /sys/bus/platform/devices/*hdmi*; do
    [ -e "$d" ] || continue
    drv=$(readlink -f "$d/driver" 2>/dev/null)
    echo "== $d -> driver: ${drv:-未绑定}"
done
echo

echo "===== [5] 内核日志（音频/HDMI） ====="
dmesg 2>/dev/null | grep -iE 'ascend.*(audio|machine|codec|platform)|310b.*audio|sound.*(probe|bind)|hdmi.*audio|aiao|Deviceid' | tail -40
echo

echo "===== [6] HDMI 链路 ====="
for c in /sys/class/drm/card*-HDMI-A-*; do
    [ -e "$c" ] || continue
    echo "$c status=$(cat "$c/status" 2>/dev/null) edid_bytes=$(wc -c < "$c/edid" 2>/dev/null)"
done
echo

echo "===== [7] 结论判定 ====="
echo "通过条件："
echo "  1) /proc/asound/cards 出现 ascend310b 声卡（card 编号可为 0 或 1）"
echo "  2) /sys/bus/platform/devices/sound 已绑定 ascend310b machine 驱动"
echo "  3) dmesg 中 codec/platform/machine insmod 与 probe 无失败"
echo "  4) amixer -c ascend310b 可访问，Deviceid 已配置为 3"
echo "  5) 用 aplay/tinyplay 直放 48kHz/16bit/双声道 WAV 能出声"
