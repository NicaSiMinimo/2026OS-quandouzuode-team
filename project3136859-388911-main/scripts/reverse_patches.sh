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
FAIL_FILE="${SCRIPT_DIR}/fail_reverse.txt"

# 颜色提示
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "目标目录: $SOURCE_DIR"
echo "补丁目录（应用顺序，撤销时自动逆序）:"
printf '  %s\n' "${PATCH_DIRS[@]}"
echo "即将撤销已应用的补丁..."

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

# 按教程应用顺序收集补丁，后续从整个列表末尾开始撤销。
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

echo "找到 ${#patches[@]} 个补丁文件，按逆序撤销..."

# 记录开始时间
start_time=$(date +%s)

# 初始化失败记录文件
> "$FAIL_FILE"

success_count=0
fail_count=0
deleted_empty_count=0

# 逆序遍历补丁（保证撤销顺序正确）
for (( idx=${#patches[@]}-1; idx>=0; idx-- )); do
    patch_file="${patches[idx]}"
    patch_name="${patch_file#"$PROJECT_DIR/"}"
    echo -e "\n${GREEN}正在撤销: $patch_name${NC}"
    
    # 提取补丁涉及的文件路径（兼容多种 patch 格式）
    files_in_patch=()
    
    # 方式1：优先从 --- / +++ 行提取（兼容性最好）
    while IFS= read -r line; do
        # 跳过 /dev/null（表示新增/删除文件）
        if [[ "$line" == */dev/null* ]]; then
            continue
        fi
        
        # 去除前缀：支持 "--- a/"、"--- b/"、"--- " 三种格式
        file_path="${line#--- }"
        file_path="${file_path#+++ }"
        file_path="${file_path#a/}"
        file_path="${file_path#b/}"
        # 去掉后面的制表符、时间戳等内容
        file_path="${file_path%%$'\t'*}"
        file_path="${file_path%% *}"
        
        if [ -n "$file_path" ] && [[ "$file_path" != /dev/null ]]; then
            # 去重
            if [[ ! " ${files_in_patch[@]} " =~ " ${file_path} " ]]; then
                files_in_patch+=("$file_path")
            fi
        fi
    done < <(grep -E '^--- |^\+\+\+ ' "$patch_file" 2>/dev/null)
    
    # 方式2：如果上面没提取到，再尝试 diff --git 格式
    if [ ${#files_in_patch[@]} -eq 0 ]; then
        while IFS= read -r line; do
            file_path="${line#diff --git a/}"
            file_path="${file_path%% b/*}"
            if [ -n "$file_path" ]; then
                files_in_patch+=("$file_path")
            fi
        done < <(grep '^diff --git a/' "$patch_file" 2>/dev/null)
    fi
    
    # 调试：输出提取到的文件（排查问题时可取消注释）
    # echo -e "${YELLOW}  提取到文件: ${files_in_patch[*]}${NC}"
    
    # 尝试撤销补丁
    patch_output=$(sudo patch -R -p1 -N -r - < "$patch_file" 2>&1)
    patch_exit=$?
    
    if [ $patch_exit -eq 0 ]; then
        echo -e "${GREEN}  -> 撤销成功${NC}"
        ((success_count++))
    elif echo "$patch_output" | grep -qiE "reversed|previously applied|skipping patch|unreversed"; then
        echo -e "${GREEN}  -> 补丁已撤销，跳过${NC}"
        ((success_count++))
    else
        echo -e "${RED}  -> 失败！补丁 $patch_name 撤销失败，请检查冲突。${NC}"
        echo "$patch_name 撤销失败" >> "$FAIL_FILE"
        ((fail_count++))
    fi
    
    # 检查并删除空文件
    if [ ${#files_in_patch[@]} -gt 0 ]; then
        for file in "${files_in_patch[@]}"; do
            # 必须是普通文件且存在
            if [ -f "$file" ]; then
                # 判断是否为空（兼容仅含空白字符的伪空文件）
                if [ ! -s "$file" ] || [ -z "$(cat "$file" 2>/dev/null | tr -d '[:space:]')" ]; then
                    echo -e "${GREEN}  -> 检测到空文件，已删除: $file${NC}"
                    sudo rm -f "$file"
                    ((deleted_empty_count++))
                fi
            fi
        done
    fi
done

# 计算用时
end_time=$(date +%s)
elapsed=$((end_time - start_time))
minutes=$((elapsed / 60))
seconds=$((elapsed % 60))

echo -e "\n${GREEN}所有补丁撤销完成。${NC}"
echo "成功: $success_count 个, 失败: $fail_count 个"
echo "清理空文件: $deleted_empty_count 个"
if [ "$fail_count" -gt 0 ]; then
    echo -e "${RED}请检查失败记录文件: $FAIL_FILE${NC}"
fi

if [ $minutes -gt 0 ]; then
    echo "总用时: ${minutes} 分 ${seconds} 秒"
else
    echo "总用时: ${seconds} 秒"
fi
