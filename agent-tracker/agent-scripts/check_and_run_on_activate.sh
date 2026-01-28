#!/usr/bin/env bash
# check_and_run_on_activate.sh
# 放置位置: ~/.config/tmux/ (全局)
# 功能: tmux window-focus hook 调用此脚本，检测并执行项目级的 on-tmux-window-activate.sh
#
# 安装方法:
#   1. 复制到 ~/.config/tmux/check_and_run_on_activate.sh
#   2. chmod +x ~/.config/tmux/check_and_run_on_activate.sh
#   3. 在 ~/.tmux.conf 中添加:
#      set-hook -g window-focus 'run-shell "~/.config/tmux/check_and_run_on_activate.sh"'
#   4. 重新加载 tmux: tmux source-file ~/.tmux.conf

# 获取 agent 目录 (worktree 目录)
AGENT_DIR=$(tmux display-message -p '#{@agent_dir}' 2>/dev/null || echo "")

# 如果没有设置 @agent_dir，说明不是 agent window，跳过
[[ -z "$AGENT_DIR" ]] && exit 0

# feature 目录 = worktree 的父目录
# agents/features/feature-1/repo → agents/features/feature-1
FEATURE_DIR="$(dirname "$AGENT_DIR")"

# 检测 feature 目录中是否有 on-tmux-window-activate.sh
ACTIVATE_SCRIPT="$FEATURE_DIR/on-tmux-window-activate.sh"

if [[ -x "$ACTIVATE_SCRIPT" ]]; then
    "$ACTIVATE_SCRIPT"
fi

exit 0
