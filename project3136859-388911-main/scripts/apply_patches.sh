#!/bin/bash

SOURCE_DIR="${SOURCE_DIR:-/home/hfut/work/5.0.3}"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
PATCH_DIRS=(
    "${PROJECT_DIR}/task1_transplantation"
    "${PROJECT_DIR}/task1_transplantation/patch_fix"
    "${PROJECT_DIR}/task4/memory"
    "${PROJECT_DIR}/task4/time"
)
FAIL_FILE="${SCRIPT_DIR}/fail_apply.txt"
# 颜色提示
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "目标目录: $SOURCE_DIR"
echo "补丁目录（按应用顺序）:"
printf '  %s\n' "${PATCH_DIRS[@]}"

# 检查目录是否存在
for patch_dir in "${PATCH_DIRS[@]}"; do
    if [ ! -d "$patch_dir" ]; then
        echo -e "${RED}错误: 补丁目录 '$patch_dir' 不存在。${NC}"
        exit 1
    fi
done

if [ ! -d "$SOURCE_DIR" ]; then
    echo -e "${RED}错误: 目标源码目录 '$SOURCE_DIR' 不存在。${NC}"
    exit 1
fi

# 进入目标目录
cd "$SOURCE_DIR" || exit 1

# 按教程顺序收集补丁；每个目录内按文件名升序。
patches=()
shopt -s nullglob
for patch_dir in "${PATCH_DIRS[@]}"; do
    dir_patches=("$patch_dir"/*.patch)
    if [ ${#dir_patches[@]} -eq 0 ]; then
        echo -e "${RED}错误: 在 '$patch_dir' 中没有找到 .patch 文件。${NC}"
        exit 1
    fi
    patches+=("${dir_patches[@]}")
done
shopt -u nullglob

echo "找到 ${#patches[@]} 个补丁文件，准备应用..."

# 记录开始时间
start_time=$(date +%s)

# 初始化失败记录文件
> "$FAIL_FILE"

success_count=0
fail_count=0

# 逐个应用补丁
for patch_file in "${patches[@]}"; do
    patch_name="${patch_file#"$PROJECT_DIR/"}"
    echo -e "\n${GREEN}正在应用: $patch_name${NC}"
    
    # 从补丁头提取目标文件相对路径（兼容 -p1 层级）
    target_file=$(grep '^+++ b/' "$patch_file" | head -1 | sed 's/^+++ b\///' | tr -d '\r')
    
    # 记录应用前文件状态：存在则记录md5，不存在则标记为空
    if [ -f "$target_file" ]; then
        before_hash=$(md5sum "$target_file" | awk '{print $1}')
    else
        before_hash="NOT_EXIST"
    fi
    
    # 捕获输出，同时保留退出码（原参数完全不变）
    patch_output=$(sudo patch -p1 -N -r - < "$patch_file" 2>&1)
    patch_exit=$?
    
    if [ $patch_exit -eq 0 ]; then
        # 计算应用后文件哈希
        if [ -f "$target_file" ]; then
            after_hash=$(md5sum "$target_file" | awk '{print $1}')
        else
            after_hash="NOT_EXIST"
        fi
        
        # 哈希无变化 = 文件未修改 = 补丁已应用
        if [ "$before_hash" = "$after_hash" ]; then
            echo -e "${GREEN}  -> 补丁已应用，跳过${NC}"
        else
            echo -e "${GREEN}  -> 成功${NC}"
        fi
        ((success_count++))
    elif echo "$patch_output" | grep -q "Reversed (or previously applied) patch detected"; then
        # 原有反向补丁检测逻辑完整保留
        echo -e "${GREEN}  -> 补丁已应用，跳过${NC}"
        ((success_count++))
    else
        # 其他失败
        echo -e "${RED}  -> 失败！补丁 $patch_name 应用失败，请检查冲突。${NC}"
        echo "$patch_name 应用失败" >> "$FAIL_FILE"
        ((fail_count++))
    fi
done

# The 5001 NAPI service is shared with the application source.  Keep the
# exact checked-in Python/sh pair in the board cfg directory so the GN targets
# added by the cfg patch package cannot silently build an older HTTP-only copy.
SERVICE_SOURCE_DIR="$PROJECT_DIR/task3_yolov5/yolov5_app/tools/device"
SERVICE_TARGET_DIR="$SOURCE_DIR/device/board/ascend/310B/cfg"
if [ -f "$SERVICE_SOURCE_DIR/yolo_acl_service.py" ] &&
   [ -f "$SERVICE_SOURCE_DIR/run_yolo_acl_service.sh" ]; then
    echo "同步 127.0.0.1:5001 NAPI 服务文件到 $SERVICE_TARGET_DIR"
    sudo install -m 0644 "$SERVICE_SOURCE_DIR/yolo_acl_service.py" \
        "$SERVICE_TARGET_DIR/yolo_acl_service.py"
    sudo install -m 0755 "$SERVICE_SOURCE_DIR/run_yolo_acl_service.sh" \
        "$SERVICE_TARGET_DIR/run_yolo_acl_service.sh"
else
    echo -e "${RED}错误: 缺少 yolo_acl_service.py 或 run_yolo_acl_service.sh。${NC}"
    exit 1
fi

# 计算用时
end_time=$(date +%s)
elapsed=$((end_time - start_time))
minutes=$((elapsed / 60))
seconds=$((elapsed % 60))

echo -e "\n${GREEN}所有补丁应用完成。${NC}"
echo "成功: $success_count 个, 失败: $fail_count 个"
if [ "$fail_count" -gt 0 ]; then
    echo -e "${RED}请检查失败记录文件: $FAIL_FILE${NC}"
fi

if [ $minutes -gt 0 ]; then
    echo "总用时: ${minutes} 分 ${seconds} 秒"
else
    echo "总用时: ${seconds} 秒"
fi

if [ "$fail_count" -gt 0 ]; then
    echo -e "${RED}补丁未完整应用，已停止后续构建。请先处理 $FAIL_FILE。${NC}"
    exit 1
fi
