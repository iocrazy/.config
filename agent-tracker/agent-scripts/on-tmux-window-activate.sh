#!/usr/bin/env bash
# on-tmux-window-activate.sh
# 放置位置: 项目根目录 (模板) → 会被复制到 feature 目录
# 功能: 切换窗口时自动同步 lazygit 和浏览器标签页
#
# 特点: 从 feature.json 读取配置，支持单服务和全栈模式

set -euo pipefail

# 获取脚本所在目录 (feature 目录)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FEATURE_CONFIG="$SCRIPT_DIR/feature.json"

# 如果没有 feature.json，尝试从 tmux option 获取
if [[ -f "$FEATURE_CONFIG" ]]; then
    # 从 feature.json 读取配置 (需要 jq)
    if command -v jq &>/dev/null; then
        AGENT_NAME=$(jq -r '.name // empty' "$FEATURE_CONFIG" 2>/dev/null || echo "")
        AGENT_DIR=$(jq -r '.worktree // empty' "$FEATURE_CONFIG" 2>/dev/null || echo "")
        BROWSER=$(jq -r '.browser // empty' "$FEATURE_CONFIG" 2>/dev/null || echo "")
        IS_FULLSTACK=$(jq -r '.fullstack // false' "$FEATURE_CONFIG" 2>/dev/null || echo "false")

        if [[ "$IS_FULLSTACK" == "true" ]]; then
            FRONTEND_PORT=$(jq -r '.frontend_port // empty' "$FEATURE_CONFIG" 2>/dev/null || echo "")
            BACKEND_PORT=$(jq -r '.backend_port // empty' "$FEATURE_CONFIG" 2>/dev/null || echo "")
            AGENT_PORT="$FRONTEND_PORT"  # 默认切换到前端
        else
            AGENT_PORT=$(jq -r '.port // empty' "$FEATURE_CONFIG" 2>/dev/null || echo "")
        fi
    else
        # 没有 jq，用 grep 简单解析
        AGENT_NAME=$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$FEATURE_CONFIG" | cut -d'"' -f4 || echo "")
        AGENT_PORT=$(grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' "$FEATURE_CONFIG" | grep -o '[0-9]*' || echo "")
        BROWSER=$(grep -o '"browser"[[:space:]]*:[[:space:]]*"[^"]*"' "$FEATURE_CONFIG" | cut -d'"' -f4 || echo "")
        AGENT_DIR=$(grep -o '"worktree"[[:space:]]*:[[:space:]]*"[^"]*"' "$FEATURE_CONFIG" | cut -d'"' -f4 || echo "")

        # 检查是否全栈模式
        if grep -q '"fullstack"[[:space:]]*:[[:space:]]*true' "$FEATURE_CONFIG"; then
            FRONTEND_PORT=$(grep -o '"frontend_port"[[:space:]]*:[[:space:]]*[0-9]*' "$FEATURE_CONFIG" | grep -o '[0-9]*' || echo "")
            AGENT_PORT="$FRONTEND_PORT"
        fi
    fi
else
    # 回退到 tmux option
    AGENT_PORT=$(tmux display-message -p '#{@agent_port}' 2>/dev/null || echo "")
    AGENT_DIR=$(tmux display-message -p '#{@agent_dir}' 2>/dev/null || echo "")
    BROWSER=$(tmux display-message -p '#{@agent_browser}' 2>/dev/null || echo "")
    AGENT_NAME=$(tmux display-message -p '#{@agent_name}' 2>/dev/null || echo "")

    # 全栈模式
    FRONTEND_PORT=$(tmux display-message -p '#{@agent_frontend_port}' 2>/dev/null || echo "")
    if [[ -n "$FRONTEND_PORT" ]]; then
        AGENT_PORT="$FRONTEND_PORT"
    fi
fi

# 如果没有获取到配置，跳过
[[ -z "$AGENT_PORT" && -z "$AGENT_DIR" ]] && exit 0

# ═══════════════════════════════════════════════════════════════
# 同步 Lazygit (pane 1) - 发送 R 刷新
# ═══════════════════════════════════════════════════════════════
if [[ -n "$AGENT_DIR" ]]; then
    PANE1_CMD=$(tmux display-message -t :.1 -p '#{pane_current_command}' 2>/dev/null || echo "")
    if [[ "$PANE1_CMD" == "lazygit" ]]; then
        tmux send-keys -t :.1 "R" 2>/dev/null || true
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 同步浏览器: 切换到对应端口的标签页
# ═══════════════════════════════════════════════════════════════
if [[ -n "$AGENT_PORT" && -n "$BROWSER" ]]; then
    case "$BROWSER" in
        chrome|"Google Chrome")
            osascript -e "
                tell application \"Google Chrome\"
                    set targetURL to \"localhost:$AGENT_PORT\"
                    repeat with w in windows
                        set tabIndex to 0
                        repeat with t in tabs of w
                            set tabIndex to tabIndex + 1
                            if URL of t contains targetURL then
                                set active tab index of w to tabIndex
                                set index of w to 1
                                return
                            end if
                        end repeat
                    end repeat
                end tell
            " 2>/dev/null || true
            ;;
        safari|Safari)
            osascript -e "
                tell application \"Safari\"
                    set targetURL to \"localhost:$AGENT_PORT\"
                    repeat with w in windows
                        set tabIndex to 0
                        repeat with t in tabs of w
                            set tabIndex to tabIndex + 1
                            if URL of t contains targetURL then
                                set current tab of w to t
                                set index of w to 1
                                return
                            end if
                        end repeat
                    end repeat
                end tell
            " 2>/dev/null || true
            ;;
        arc|Arc)
            osascript -e "
                tell application \"Arc\"
                    set targetURL to \"localhost:$AGENT_PORT\"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if URL of t contains targetURL then
                                tell t to select
                                return
                            end if
                        end repeat
                    end repeat
                end tell
            " 2>/dev/null || true
            ;;
    esac
fi

exit 0
