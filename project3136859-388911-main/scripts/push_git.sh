#!/bin/bash

# ===== 在这里修改默认值 =====
REPO_PATH="/home/hfut/Desktop/2026OS/project3136859-388911"  # 仓库路径，留空则使用当前目录
MESSAGE=""  # 提交信息
# ============================

# -------------------- 计时功能 --------------------
start_time=$(date +%s)                     # 记录开始时间戳
trap 'end_time=$(date +%s);                # 在脚本退出时自动执行
      elapsed=$((end_time - start_time));
      echo "总耗时: ${elapsed}秒"' EXIT
# ------------------------------------------------

# 快速Git提交推送脚本

# 切换到仓库目录
if [ -n "$REPO_PATH" ]; then
    echo "切换到仓库: $REPO_PATH"
    cd "$REPO_PATH" || {
        echo "错误: 无法切换到目录 $REPO_PATH"
        exit 1
    }
    echo "当前目录: $(pwd)"
fi

echo "执行: git add . && git commit -m \"$MESSAGE\" && git push origin main"
read -p "确认? (y/n): " confirm

if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    git add . && git commit -m "$MESSAGE" && git push origin main
    echo "✓ 完成！"
else
    echo "已取消"
fi
