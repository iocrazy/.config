#!/usr/bin/env bash
# destroy.sh
# 放置位置: 主仓库目录 (模板) 和 feature 目录 (自动复制)
# 功能: 销毁当前 agent window 和对应的 worktree
#
# 用法 (在 worktree 目录中执行):
#   ../destroy.sh           # 交互确认
#   ../destroy.sh -y        # 跳过确认直接销毁
#   ../destroy.sh --keep    # 只关闭窗口，保留 worktree
#
# 目录结构:
#   my_app/
#   ├── start-agent
#   └── agents/features/
#       └── feature-1/
#           ├── destroy.sh  # <- 执行这个 (../destroy.sh)
#           └── repo/       # worktree (当前位置)

set -euo pipefail

# 解析参数
FORCE=false
KEEP_WORKTREE=false

for arg in "$@"; do
    case "$arg" in
        -y|--yes)
            FORCE=true
            ;;
        --keep)
            KEEP_WORKTREE=true
            ;;
    esac
done

# 获取窗口信息
WINDOW_NAME=$(tmux display-message -p '#{window_name}')
WINDOW_INDEX=$(tmux display-message -p '#{window_index}')

# 获取 agent 信息
AGENT_DIR=$(tmux display-message -p '#{@agent_dir}' 2>/dev/null || echo "")
MAIN_REPO=$(tmux display-message -p '#{@agent_main_repo}' 2>/dev/null || echo "")

# 检测是否全栈模式
IS_FULLSTACK=$(tmux display-message -p '#{@agent_fullstack}' 2>/dev/null || echo "")

if [[ "$IS_FULLSTACK" == "true" ]]; then
    FRONTEND_PORT=$(tmux display-message -p '#{@agent_frontend_port}' 2>/dev/null || echo "")
    BACKEND_PORT=$(tmux display-message -p '#{@agent_backend_port}' 2>/dev/null || echo "")
else
    AGENT_PORT=$(tmux display-message -p '#{@agent_port}' 2>/dev/null || echo "")
fi

# 确认提示
if [[ "$FORCE" != "true" ]]; then
    echo -e "\033[1;33m⚠️  即将销毁窗口: $WINDOW_NAME (index: $WINDOW_INDEX)\033[0m"

    if [[ "$IS_FULLSTACK" == "true" ]]; then
        [[ -n "$FRONTEND_PORT" ]] && echo -e "   前端端口: $FRONTEND_PORT"
        [[ -n "$BACKEND_PORT" ]] && echo -e "   后端端口: $BACKEND_PORT"
    else
        [[ -n "$AGENT_PORT" ]] && echo -e "   端口: $AGENT_PORT"
    fi

    [[ -n "$AGENT_DIR" ]] && echo -e "   目录: $AGENT_DIR"

    if [[ "$KEEP_WORKTREE" == "true" ]]; then
        echo -e "   \033[1;34mWorktree 将被保留\033[0m"
    else
        echo -e "   \033[1;31mWorktree 将被删除\033[0m"
    fi

    echo ""
    read -p "确认销毁? [y/N] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "已取消"
        exit 0
    fi
fi

# 清理：停止可能运行的 dev server 进程（基于端口）
if [[ "$IS_FULLSTACK" == "true" ]]; then
    if [[ -n "$FRONTEND_PORT" ]]; then
        echo -e "\033[1;34m🔌 停止前端端口 $FRONTEND_PORT...\033[0m"
        lsof -ti:"$FRONTEND_PORT" 2>/dev/null | xargs kill -9 2>/dev/null || true
    fi
    if [[ -n "$BACKEND_PORT" ]]; then
        echo -e "\033[1;34m🔌 停止后端端口 $BACKEND_PORT...\033[0m"
        lsof -ti:"$BACKEND_PORT" 2>/dev/null | xargs kill -9 2>/dev/null || true
    fi
else
    if [[ -n "$AGENT_PORT" ]]; then
        echo -e "\033[1;34m🔌 停止端口 $AGENT_PORT 上的进程...\033[0m"
        lsof -ti:"$AGENT_PORT" 2>/dev/null | xargs kill -9 2>/dev/null || true
    fi
fi

# 删除 worktree（如果不保留）
if [[ "$KEEP_WORKTREE" != "true" && -n "$AGENT_DIR" && -n "$MAIN_REPO" ]]; then
    if [[ -d "$AGENT_DIR" ]]; then
        echo -e "\033[1;34m🗂️  删除 Worktree: $AGENT_DIR\033[0m"

        # 使用 git worktree remove
        git -C "$MAIN_REPO" worktree remove "$AGENT_DIR" --force 2>/dev/null || true

        # 如果 worktree remove 失败，手动删除目录
        if [[ -d "$AGENT_DIR" ]]; then
            rm -rf "$AGENT_DIR"
        fi

        # 删除 feature 目录 (包括 destroy.sh)
        FEATURE_DIR="$(dirname "$AGENT_DIR")"
        if [[ -d "$FEATURE_DIR" ]]; then
            rm -rf "$FEATURE_DIR"
        fi

        # 可选：删除分支
        echo -e "\033[1;34m🌿 删除分支: $WINDOW_NAME\033[0m"
        git -C "$MAIN_REPO" branch -D "$WINDOW_NAME" 2>/dev/null || true
    fi
fi

# 向 agent-tracker 标记任务完成
TRACKER_CLIENT="${TRACKER_CLIENT:-$HOME/.config/agent-tracker/bin/tracker-client}"
if [[ -x "$TRACKER_CLIENT" ]] || command -v tracker-client &>/dev/null; then
    [[ -x "$TRACKER_CLIENT" ]] || TRACKER_CLIENT="tracker-client"
    SESSION_NAME=$(tmux display-message -p '#{session_name}')
    SESSION_ID=$(tmux display-message -p '#{session_id}')
    WINDOW_ID=$(tmux display-message -p '#{window_id}')
    PANE_ID=$(tmux display-message -p '#{pane_id}')
    if "$TRACKER_CLIENT" command finish_task \
        -session "$SESSION_NAME" \
        -session-id "$SESSION_ID" \
        -window "$WINDOW_NAME" \
        -window-id "$WINDOW_ID" \
        -pane "$PANE_ID" \
        -summary "Destroyed: $WINDOW_NAME" 2>/dev/null; then
        echo -e "\033[1;32m📋 Task marked as finished in agent-tracker\033[0m"
    fi
fi

# 销毁窗口
echo -e "\033[1;31m🗑️  销毁窗口: $WINDOW_NAME\033[0m"
tmux kill-window

exit 0
