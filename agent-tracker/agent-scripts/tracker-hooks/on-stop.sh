#!/usr/bin/env bash
# on-stop.sh - Claude Code Stop hook
# 当 Claude Code 完成回复时调用
#
# 安装方法:
#   1. 复制到 ~/.config/claude/hooks/
#   2. 在 settings.json 的 hooks.Stop 中添加此脚本

# 读取 stdin 的 JSON 数据
INPUT=$(cat)

# 解析 transcript_path
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
if [[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]]; then
    exit 0
fi

# 获取最后一条 assistant 消息
LAST_MESSAGE=$(tail -1 "$TRANSCRIPT_PATH" | jq -r '.message.content[0].text // empty' 2>/dev/null)
if [[ -z "$LAST_MESSAGE" ]]; then
    LAST_MESSAGE="done"
fi

# 截断消息长度
LAST_MESSAGE="${LAST_MESSAGE:0:200}"

# 检查是否在 tmux 中运行
PANE="${TMUX_PANE:-}"
if [[ -z "$PANE" ]]; then
    exit 0
fi

# 获取 tmux context
TMUX_INFO=$(tmux display-message -p -t "$PANE" "#{session_id}:::#{window_id}:::#{pane_id}" 2>/dev/null)
if [[ -z "$TMUX_INFO" ]]; then
    exit 0
fi

IFS=':::' read -r SESSION_ID WINDOW_ID PANE_ID <<< "$TMUX_INFO"

# 查找 tracker-client
TRACKER_CLIENT="${TRACKER_CLIENT:-$HOME/.config/agent-tracker/bin/tracker-client}"
[[ -x "$TRACKER_CLIENT" ]] || TRACKER_CLIENT=$(which tracker-client 2>/dev/null)
[[ -x "$TRACKER_CLIENT" ]] || exit 0

# 调用 finish_task
"$TRACKER_CLIENT" command \
    -session-id "$SESSION_ID" \
    -window-id "$WINDOW_ID" \
    -pane "$PANE_ID" \
    -summary "$LAST_MESSAGE" \
    finish_task 2>/dev/null &

exit 0
