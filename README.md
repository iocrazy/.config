# Dotfiles

开发工具和应用程序的配置管理，核心是 **Agent Tracker** 多 AI Agent 任务跟踪系统。

---

## 目录

1. [系统概述](#系统概述)
2. [架构设计](#架构设计)
3. [文件结构](#文件结构)
4. [Agent Tracker 系统](#agent-tracker-系统)
5. [Tmux 配置](#tmux-配置)
6. [Claude Code 配置](#claude-code-配置)
7. [OpenCode 配置](#opencode-配置)
8. [Zsh 配置](#zsh-配置)
9. [安装部署](#安装部署)
10. [快捷键速查](#快捷键速查)
11. [故障排除](#故障排除)
12. [Linux 相关](#linux-相关)

---

## 系统概述

### 解决的问题

当你需要同时运行多个 AI Agent（Claude Code、OpenCode、Gemini 等）处理不同任务时：

- **传统痛点**：需要频繁切换终端窗口，不知道哪个 Agent 已完成
- **本方案**：通过 tmux + agent-tracker 实现可视化状态跟踪

### 核心功能

| 功能 | 说明 |
|------|------|
| 可视化状态 | 状态栏显示 ⏳（进行中）或 🔔（已完成待查看） |
| 桌面通知 | Agent 完成时弹出 macOS 通知 |
| 一键跳转 | `Alt+m` 直接跳转到完成任务的 Agent |
| 多项目管理 | 每个 session = 项目，每个 window = Agent |
| 自动编号 | Session 自动按 `1-项目名`、`2-项目名` 格式编号 |

### 工作流示意

```
┌─────────────────────────────────────────────────────────────┐
│  tmux 状态栏                                                 │
│  [1-project-a⏳] [2-project-b🔔] [3-project-c]              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Session: 1-project-a                                       │
│  ┌─────────────┬─────────────┬─────────────┐               │
│  │ Window 1    │ Window 2    │ Window 3    │               │
│  │ claude⏳    │ opencode    │ shell       │               │
│  │ (开发中)    │ (空闲)      │ (测试)      │               │
│  └─────────────┴─────────────┴─────────────┘               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 架构设计

### 三层架构

```
┌─────────────────────────────────────────────────────────────┐
│                      用户交互层                              │
│  tmux 状态栏 ←→ tracker-client TUI ←→ 桌面通知              │
├─────────────────────────────────────────────────────────────┤
│                      状态管理层                              │
│  tracker-server (Unix Socket) ←→ tracker-client (CLI/TUI)  │
│                    ↑                                        │
│            tracker-mcp (MCP协议)                            │
├─────────────────────────────────────────────────────────────┤
│                      AI Agent 层                            │
│  Claude Code ──hooks──→ notify.py ──→ tracker-client       │
│  OpenCode   ──plugin──→ notify.py ──→ tracker-client       │
└─────────────────────────────────────────────────────────────┘
```

### Agent Tracker 整体架构

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              tmux session                               │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │   main window   │  │  feature-1 窗口  │  │  feature-2 窗口  │  ...    │
│  │  (tracker TUI)  │  │ ┌─────┬───────┐ │  │ ┌─────┬───────┐ │         │
│  │                 │  │ │pane0│lazygit│ │  │ │pane0│lazygit│ │         │
│  │                 │  │ │     ├───────┤ │  │ │     ├───────┤ │         │
│  │                 │  │ │     │dev srv│ │  │ │     │dev srv│ │         │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘         │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Agent Tracker 系统                              │
│                                                                         │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐     │
│  │ tracker-server  │◄───│ tracker-client  │    │  tracker-mcp    │     │
│  │   (brew 服务)   │    │   (TUI/CLI)     │    │  (MCP 服务器)   │     │
│  │                 │    │                 │    │                 │     │
│  │ - 任务状态管理  │    │ - TUI 界面      │    │ - AI 工具接口   │     │
│  │ - Notes 管理    │    │ - 命令行操作    │    │                 │     │
│  │ - Goals 管理    │    │ - 状态查询      │    │                 │     │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘     │
│           ▲                                                             │
│           │                                                             │
│  ┌────────┴────────────────────────────────────────────────────┐       │
│  │                    事件触发源                                 │       │
│  │  ┌──────────────────┐    ┌──────────────────┐               │       │
│  │  │tracker-notify.js │    │  Claude Code     │               │       │
│  │  │ (OpenCode 插件)  │    │    (Hooks)       │               │       │
│  │  │                  │    │                  │               │       │
│  │  │ - 监听 busy/idle │    │ - UserPromptSubmit│              │       │
│  │  │ - 调用 start/end │    │ - Stop           │               │       │
│  │  └──────────────────┘    └──────────────────┘               │       │
│  │                                   │                         │       │
│  │                    ┌──────────────┴──────────────┐          │       │
│  │                    │        notify.py            │          │       │
│  │                    │     (系统通知脚本)          │          │       │
│  │                    │  - 发送 macOS 通知          │          │       │
│  │                    │  - 记录跳转目标             │          │       │
│  │                    └─────────────────────────────┘          │       │
│  └─────────────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────────┘
```

### 数据流

1. **任务开始**：AI Agent 通过 MCP 或脚本向 tracker-server 报告
2. **状态更新**：tracker-server 维护任务状态（in_progress → completed）
3. **状态显示**：tmux 状态栏脚本每秒读取缓存文件显示图标
4. **任务完成**：hooks 调用 notify.py 发送通知
5. **用户确认**：切换到该窗口时自动 acknowledge

### 任务状态流转

```
┌─────────────┐     start_task      ┌─────────────┐
│    IDLE     │ ──────────────────► │ IN_PROGRESS │
│             │                     │     ▶ ⠋     │
└─────────────┘                     └──────┬──────┘
                                           │
                                      finish_task
                                           │
                    ┌──────────────────────┼──────────────────────┐
                    │                      │                      │
                    ▼                      ▼                      │
        ┌─────────────────┐    ┌─────────────────┐               │
        │   COMPLETED     │    │   COMPLETED     │               │
        │  (auto-ack ✓)   │    │ (awaiting 🚩)   │               │
        │                 │    │                 │               │
        │ 用户在当前 pane │    │ 用户在其他 pane │               │
        └─────────────────┘    └────────┬────────┘               │
                                        │                        │
                                   acknowledge                   │
                                   (按 c 确认)                   │
                                        │                        │
                                        ▼                        │
                               ┌─────────────────┐               │
                               │  ACKNOWLEDGED   │               │
                               │       ✓         │               │
                               └─────────────────┘               │
```

---

## 文件结构

```
~/.config/
├── agent-tracker/              # ★ Agent Tracker 系统 (Go)
│   ├── bin/
│   │   ├── tracker-server      # 后台服务
│   │   ├── tracker-client      # CLI/TUI 客户端
│   │   └── tracker-mcp         # MCP 服务器
│   ├── notify.py               # ★ 通知脚本（集中存放）
│   ├── cmd/
│   │   ├── tracker-server/main.go
│   │   ├── tracker-client/main.go   # 包含 runewidth 中文支持
│   │   └── tracker-mcp/main.go
│   ├── internal/
│   │   ├── tracker/tracker.go
│   │   └── ipc/envelope.go
│   ├── scripts/
│   │   ├── focus_latest_notified.sh
│   │   ├── focus_last_origin.sh
│   │   └── install_brew_service.sh
│   ├── run/
│   │   ├── latest_notified.txt  # 最近通知的 pane
│   │   └── jump_back.txt        # 跳回位置
│   ├── go.mod                   # 包含 go-runewidth 依赖
│   └── go.sum

├── claude/                     # Claude Code 配置
│   ├── settings.json           # ★ 包含 UserPromptSubmit + Stop hooks
│   ├── skills/                 # 自定义 skills
│   ├── plugins/                # 插件
│   └── notify.py → ../agent-tracker/notify.py  # 符号链接

├── opencode/                   # OpenCode 配置
│   ├── opencode.json           # 主配置
│   ├── plugin/
│   │   └── tracker-notify.js   # 任务跟踪插件
│   └── tracker-debug.log       # 调试日志

├── tmux/                       # tmux 脚本和状态栏
│   ├── tmux-status/
│   │   ├── left.sh             # 左侧状态栏
│   │   ├── right.sh            # 右侧状态栏
│   │   ├── window_task_icon.sh # 窗口图标
│   │   ├── tracker_cache.sh    # 缓存管理
│   │   ├── notes_count.sh      # 笔记数量
│   │   └── ccusage-today.sh    # Claude 用量
│   └── scripts/
│       ├── session_manager.py  # Session 管理
│       ├── new_session.sh      # 新建 Session
│       └── switch_session_by_index.sh

├── yazi/                       # yazi 文件管理器
│   └── yazi.toml

├── lazygit/                    # lazygit 配置
│   └── config.yml

├── fish/                       # fish shell
│   └── config.fish

├── zsh/                        # zsh 配置
│   ├── zshrc                   # 主配置入口
│   ├── env.zsh                 # 环境变量
│   ├── aliases.zsh             # 命令别名
│   ├── plugins.zsh             # Zim 插件
│   ├── vi.zsh                  # Vi 模式 (Colemak)
│   ├── fzf.zsh                 # FZF 配置
│   ├── mappings.zsh            # 快捷键
│   ├── tmux.zsh                # Tmux 环境同步
│   ├── prompt.zsh              # 提示符
│   └── functions/              # 自定义函数
│       ├── cd_git_root.zsh
│       ├── co.zsh              # Codex 包装器
│       ├── op.zsh              # OpenCode 包装器
│       └── se.zsh              # Search Agent 包装器

├── .tmux.conf                  # tmux 主配置

└── bin/                        # 可执行脚本
    └── upgrade-all             # 一键安装脚本

~/bin/
└── start-agent                 # Agent 窗口创建脚本

# Agent 工作目录（示例）
~/agents/
└── feature-1/
    ├── repo/                   # git worktree
    ├── feature.json            # 实例配置
    ├── destroy.sh              # 销毁脚本
    └── .agent-info             # Agent 信息
```

---

## Agent Tracker 系统

### 组件说明

#### 1. tracker-server (Go 服务)

后台常驻服务，管理所有任务、Notes 和 Goals 的状态。

**安装位置**：`~/.config/agent-tracker/bin/tracker-server`

**运行方式**：通过 Homebrew 服务管理
```bash
brew services start tracker-server
brew services stop tracker-server
brew services restart tracker-server
```

**通信方式**：Unix Socket (`/tmp/agent-tracker.sock`)

#### 2. tracker-client (Go CLI/TUI)

**功能**：
- TUI 界面显示任务状态
- CLI 命令行操作任务
- 支持中文字符正确显示（使用 runewidth 处理全角字符）

**使用方式**：
```bash
# 启动 TUI
tracker-client

# 命令行操作
tracker-client command -pane "%54" -summary "任务描述" start_task
tracker-client command -pane "%54" -summary "完成说明" finish_task
tracker-client command -pane "%54" acknowledge

# 查看状态
tracker-client state
```

**注意**：Go flag 解析要求 **flags 在子命令之前**：
```bash
# 正确 ✓
tracker-client command -pane "%54" -summary "hello" start_task

# 错误 ✗
tracker-client command start_task -pane "%54" -summary "hello"
```

#### 3. tracker-mcp (MCP 服务器)

让 AI Agent 可以主动报告状态。

**配置方式**（在 claude settings.json 中）：
```json
{
  "mcpServers": {
    "tracker": {
      "command": "~/.config/agent-tracker/bin/tracker-mcp"
    }
  }
}
```

#### 4. notify.py (通知脚本)

**功能**：
- 发送 macOS 系统通知（使用 terminal-notifier）
- 记录最近通知的 pane（用于快捷键跳转）
- 调用 tracker-client 标记任务完成

**安装位置**：`~/.config/agent-tracker/notify.py`（集中管理）

**符号链接**：
- `~/.config/claude/notify.py` → `../agent-tracker/notify.py`

### TUI 界面

```
┌─────────────────────────────────────────────────────┐
│ Tracker                                             │
│ Active 2 · Waiting 1 · Notes 3 · 1:30PM            │
├─────────────────────────────────────────────────────┤
│ ▶ ⠋ 正在处理的任务...                    01m30s    │
│    └ Demo / feature-1                               │
│                                                     │
│ ⚑ 等待确认的任务                          00m45s    │
│    └ Demo / feature-2 (awaiting review)             │
│    Note: 任务完成说明                               │
│                                                     │
│ ✓ 已完成的任务                            02m15s    │
│    └ Demo / feature-3                               │
│    Note: done                                       │
└─────────────────────────────────────────────────────┘
```

### 任务状态图标

| 图标 | 状态 | 说明 |
|------|------|------|
| `▶ ⠋` | in_progress | 任务正在进行中（spinner 动画） |
| `⚑` | awaiting review | 任务完成，等待用户确认（红旗） |
| `✓` | acknowledged | 任务已确认完成（绿勾） |

### TUI 快捷键

| 快捷键 | 功能 |
|--------|------|
| `t` | 切换 Tracker / Notes 视图 |
| `Tab` | 在 Goals 和 Notes 之间切换焦点 |
| `u` / `e` | 上 / 下移动选择 |
| `c` | 切换任务状态（完成/确认） |
| `Enter` / `p` / `f` | 跳转到选中任务的 pane |
| `a` | 添加 Note / Goal |
| `k` | 编辑 Note |
| `Shift+A` | 归档 Note |
| `Shift+D` | 删除任务 / Note / Goal |
| `Shift+C` | 显示/隐藏已完成项目 |
| `n` / `i` | 切换 Note 作用域（Window/Session/Global） |
| `s` | 循环 Note 作用域 |
| `Alt+A` | 切换到 Archive 视图 |
| `?` | 显示帮助 |
| `Esc` / `Ctrl+C` | 退出 |

---

## Tmux 配置

### 基础设置

```bash
# 前缀键
unbind C-b
set -g prefix 'C-s'

# 基础优化
set -s escape-time 0          # 消除 ESC 延迟
set -sg repeat-time 300       # 重复按键间隔
set -s focus-events on        # 焦点事件
set -g mouse on               # 启用鼠标
set -g history-limit 10000    # 历史记录
set -g detach-on-destroy off  # 关闭 session 时不 detach

# 256 色支持
set -g default-terminal "tmux-256color"
set -as terminal-features ",*256col*:RGB"
```

### Agent-Tracker Hooks

```bash
# 客户端连接时 - 自动确认当前窗口任务
set-hook -g client-attached 'run -b "tracker-client command acknowledge \
  --session-id #{session_id} --window-id #{window_id} --pane #{pane_id}"'

# 切换 pane 时 - 自动确认
set-hook -g pane-focus-in 'run -b "tracker-client command acknowledge \
  --session-id #{session_id} --window-id #{window_id} --pane #{pane_id}"'

# pane 关闭时 - 删除任务和归档笔记
set-hook -g pane-died 'run -b "tracker-client command delete_task \
  --session-id #{session_id} --window-id #{window_id} --pane #{pane_id}"'
```

### 状态栏配置

```bash
# 左侧状态栏 - 显示所有 session 及状态图标
set-option -g status-left "#(~/.config/tmux/tmux-status/left.sh \"#{session_id}\" \"#{session_name}\")   "

# 右侧状态栏 - 系统监控 + 主机名
set-option -g status-right "#(~/.config/tmux/tmux-status/right.sh)"

# 窗口标题 - 显示任务图标
setw -g window-status-format '#[fg=#c5c8c6] #W#(~/.config/tmux/tmux-status/window_task_icon.sh "#{window_id}") '
setw -g window-status-current-format '#[fg=#{@theme_color},bold] #W#(~/.config/tmux/tmux-status/window_task_icon.sh "#{window_id}") '
```

### 布局 (IJKL/NEUI 风格)

```
        I (上)
        ↑
    N ← · → L
        ↓
        K (下)
```

注：博主使用 Colemak 键盘布局，所以是 `n/e/u/i` 而不是 `h/j/k/l`。

---

## Claude Code 配置

### 语音命令

- `/voice-on` - 启用 TTS（文本转语音）
- `/voice-off` - 禁用 TTS

语音由全局标志文件 `~/.claude/voice-enabled` 控制。

### 高质量系统语音配置

1. **打开系统偏好设置** → **辅助功能** → **朗读内容**
2. **点击"系统语音"下拉菜单旁边的信息图标 (ⓘ)**
3. **搜索"Siri"** 以找到最高质量的语音
4. **下载 Siri 语音** - 这些是基于神经网络的高级语音

### Hooks 配置

编辑 `~/.config/claude/settings.json`：

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "export TMUX_PANE=$(tmux display-message -p '#{pane_id}' 2>/dev/null || echo ''); if [ -n \"$TMUX_PANE\" ]; then TMUX_IDS=$(tmux display-message -p -t \"$TMUX_PANE\" '#{session_id}:::#{window_id}:::#{pane_id}' 2>/dev/null); if [ -n \"$TMUX_IDS\" ]; then SID=$(echo \"$TMUX_IDS\" | cut -d: -f1); WID=$(echo \"$TMUX_IDS\" | cut -d: -f4); PID=$(echo \"$TMUX_IDS\" | cut -d: -f7); summary=$(cat | jq -r '.prompt // \"working...\"' | head -c 100); \"$HOME/.config/agent-tracker/bin/tracker-client\" command -session-id \"$SID\" -window-id \"$WID\" -pane \"$PID\" -summary \"$summary\" start_task 2>/dev/null; fi; fi"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "export TMUX_PANE=$(tmux display-message -p '#{pane_id}' 2>/dev/null || echo ''); if [ -n \"$TMUX_PANE\" ]; then TMUX_IDS=$(tmux display-message -p -t \"$TMUX_PANE\" '#{session_id}:::#{window_id}:::#{pane_id}' 2>/dev/null); if [ -n \"$TMUX_IDS\" ]; then SID=$(echo \"$TMUX_IDS\" | cut -d: -f1); WID=$(echo \"$TMUX_IDS\" | cut -d: -f4); PID=$(echo \"$TMUX_IDS\" | cut -d: -f7); transcript_path=$(cat | jq -r '.transcript_path'); last_message=$(tail -1 \"$transcript_path\" | jq -r '.message.content[0].text // empty' | head -c 200); \"$HOME/.config/agent-tracker/bin/tracker-client\" command -session-id \"$SID\" -window-id \"$WID\" -pane \"$PID\" -summary \"$last_message\" finish_task 2>/dev/null; notification_json=$(jq -n --arg msg \"$last_message\" '{type: \"agent-turn-complete\", \"last-assistant-message\": $msg}'); \"$HOME/.config/claude/notify.py\" \"$notification_json\" 2>/dev/null; fi; fi"
          }
        ]
      }
    ]
  }
}
```

**Hook 说明**：

| Hook | 触发时机 | 用途 |
|------|---------|------|
| **UserPromptSubmit** | 用户发送消息时 | 调用 `start_task` 开始任务跟踪 |
| **Stop** | Claude 完成响应时 | 调用 `finish_task` 结束任务并发送通知 |

### Claude Code 工作流程

```
用户输入 "hello"
       │
       ▼
UserPromptSubmit Hook 触发
       │
       ├──► tracker-client start_task -summary "hello"
       │           │
       │           ▼
       │    tracker-server 记录: [ACTIVE ▶] hello
       │
Claude Code 处理中...
       │
       ▼
Stop Hook 触发
       │
       ├──► tracker-client finish_task -summary "回复内容"
       │           │
       │           ▼
       │    tracker-server 记录:
       │      - 如果用户在当前 pane → [DONE ✓]
       │      - 如果用户在其他 pane → [WAITING 🚩]
       │
       └──► notify.py (发送系统通知)
                   │
                   └──► 🔔 macOS 通知弹出，点击可跳转
```

---

## OpenCode 配置

### 插件配置

**opencode.json 示例**：
```json
{
  "plugin": [
    "opencode-anthropic-auth@0.0.9",
    "./plugin/tracker-notify.js"
  ]
}
```

### tracker-notify.js 工作原理

```javascript
// 监听 session.status 事件
event: async ({ event }) => {
    if (event?.type !== "session.status") return;

    if (status.type === "busy" && !taskActive) {
        // 状态变为 busy → 开始任务
        await startTask(userMessage, sessionID);
    }

    if (status.type === "idle" && taskActive) {
        // 状态变为 idle → 结束任务 + 发通知
        await finishTask(assistantResponse);
        await notify(sessionID);
    }
}
```

### OpenCode vs Claude Code 对比

| 特性 | OpenCode | Claude Code |
|------|----------|-------------|
| 实现方式 | 插件 (tracker-notify.js) | Hooks (settings.json) |
| 任务开始触发 | session.status = "busy" | UserPromptSubmit hook |
| 任务完成触发 | session.status = "idle" | Stop hook |
| TMUX_PANE 获取 | 环境变量自动继承 | Hook 中动态获取 |

---

## Zsh 配置

### 配置文件加载顺序

```
~/.zshrc (由 upgrade-all 创建，内容: source ~/.config/zsh/zshrc)
    ↓
~/.config/zsh/zshrc (主配置入口)
    ├── env.zsh        # 环境变量 (PATH 等)
    ├── aliases.zsh    # 命令别名
    ├── plugins.zsh    # Zim 框架初始化
    ├── vi.zsh         # Vi 模式配置 (Colemak)
    ├── fzf.zsh        # FZF 模糊搜索
    ├── mappings.zsh   # 快捷键映射
    ├── tmux.zsh       # Tmux 环境同步
    ├── prompt.zsh     # 提示符配置
    └── functions/     # 自定义函数
```

### AI Agent 启动包装器

博主为不同的 AI Agent 创建了智能启动包装器：

#### co() - Codex 包装器

```bash
co                    # 启动 Codex，自动加载项目配置
co --model gpt-4      # 带参数启动
```

**功能**：
- 临时配置目录隔离
- 项目级提示词注入
- Tmux ID 自动记录
- MCP 配置合并

#### op() 和 se() - OpenCode 包装器

```bash
op                    # 通用 OpenCode 启动器
se                    # Search Agent 专用启动器
```

### Zim 插件

| 插件 | 功能 |
|------|------|
| `zsh-autosuggestions` | 历史命令建议 |
| `fast-syntax-highlighting` | 实时命令高亮 |
| `fzf-tab` | Tab 补全使用 FZF |
| `zsh-z` | 智能目录跳转 |

---

## 安装部署

### 前置要求

```bash
# 1. 安装 Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. 安装依赖
brew install tmux terminal-notifier lazygit jq go
```

### 快速安装

```bash
bin/upgrade-all
```

脚本功能（幂等，可多次运行）：
- 安装/更新 Homebrew 包
- 设置 zsh 配置
- 创建符号链接 (tmux, claude)
- 编译 Agent Tracker

### 手动安装 Agent Tracker

```bash
# 1. 编译二进制文件
cd ~/.config/agent-tracker
go mod tidy
go build -o bin/tracker-server ./cmd/tracker-server
go build -o bin/tracker-client ./cmd/tracker-client
go build -o bin/tracker-mcp ./cmd/tracker-mcp

# 2. 安装 brew 服务
./scripts/install_brew_service.sh

# 3. 启动服务
brew services start tracker-server
```

### 配置符号链接

```bash
# tmux 配置
ln -sf ~/.config/.tmux.conf ~/.tmux.conf

# Claude Code 配置
ln -sf ~/.config/claude ~/.claude

# notify.py 符号链接
ln -sf ../agent-tracker/notify.py ~/.config/claude/notify.py
```

### 同步配置

修改本项目后，同步到实际生效目录：

```bash
# 重新编译 tracker-client
cd ~/.config/agent-tracker && go mod tidy && go build -o bin/tracker-client ./cmd/tracker-client
```

---

## 快捷键速查

> 前缀键：`Ctrl+s`

### Session 管理

| 快捷键 | 功能 |
|--------|------|
| `Alt+S` | 新建 session |
| `Ctrl+s .` | 重命名 session |
| `Ctrl+1~9` | 切换到 session 1~9 |
| `F1~F5` | 切换到 session 1~5 |

### Window 管理

| 快捷键 | 功能 |
|--------|------|
| `Alt+o` | 新建 window |
| `Alt+Q` | 关闭当前 pane |
| `Alt+1~9` | 切换到 window 1~9 |

### Pane 管理

| 快捷键 | 功能 |
|--------|------|
| `Ctrl+s u` | 上方分屏 |
| `Ctrl+s e` | 下方分屏 |
| `Ctrl+s n` | 左侧分屏 |
| `Ctrl+s i` | 右侧分屏 |
| `Alt+n/e/u/i` | 切换 pane（左/下/上/右） |
| `Alt+f` | 全屏/恢复 |

### Agent-Tracker 专用

| 快捷键 | 功能 |
|--------|------|
| `Alt+t` | 打开/关闭 tracker TUI |
| `Alt+m` | 跳转到最新完成的 Agent |
| `Alt+Shift+M` | 跳回上一个位置 |

### Tracker TUI 快捷键

| 键 | 功能 |
|---|---|
| `t` | 切换 Tracker/Notes |
| `Tab` | 切换 Goals/Notes 焦点 |
| `u`/`e` | 上/下移动 |
| `c` | 确认任务 |
| `Enter`/`f` | 跳转到 pane |
| `a` | 添加 Note/Goal |
| `Shift+D` | 删除 |
| `?` | 帮助 |
| `Esc` | 退出 |

---

## 故障排除

### 1. 任务标题显示 `-pane %54 -summary ...` 格式

**原因**：Go flag 解析器要求 flags 在子命令之前

**解决**：确保命令格式正确：
```bash
# 正确格式
tracker-client command -pane "%54" -summary "hello" start_task
```

### 2. 中文字符显示乱码/截断

**原因**：原代码按字节而不是按字符宽度截断

**解决**：使用 `go-runewidth` 包处理全角字符

### 3. Claude Code 任务没有触发

**检查步骤**：
```bash
# 1. 查看 hook 日志
cat /tmp/claude-hook.log

# 2. 检查 settings.json 配置
cat ~/.config/claude/settings.json | jq '.hooks'

# 3. 确认在 tmux 中运行
echo $TMUX
```

### 4. OpenCode 插件没有生效

**检查步骤**：
```bash
# 1. 检查插件文件
ls -la ~/.config/opencode/plugin/tracker-notify.js

# 2. 查看调试日志
tail -50 ~/.config/opencode/tracker-debug.log

# 3. 确认在 tmux 中运行
echo $TMUX_PANE
```

### 5. tracker-client 命令失败

**检查步骤**：
```bash
# 1. 检查服务状态
brew services list | grep tracker

# 2. 检查 socket 文件
ls -la /tmp/agent-tracker.sock

# 3. 手动测试
tracker-client command -pane "%54" -summary "test" start_task
```

### 6. 系统通知不工作

**检查步骤**：
```bash
# 1. 检查 terminal-notifier
which terminal-notifier

# 2. 检查符号链接
ls -la ~/.config/claude/notify.py

# 3. 手动测试
python3 ~/.config/agent-tracker/notify.py '{"type":"agent-turn-complete","last-assistant-message":"test"}'
```

### 7. 任务直接显示 ✓ 而不是红旗 🚩

**这是正常行为**：如果你在当前 pane 中工作，任务完成时会自动确认。只有当你在**其他 pane** 时，才会看到红旗等待确认。

---

## Linux 相关

<details>
<summary>传统配置（点击展开）</summary>

我的脚本在[此仓库中](https://github.com/theniceboy/scripts)。

此文件夹包含 `i3` 和 `alacritty` 配置，不过现在使用 [dwm](https://github.com/theniceboy/dwm) 和 [st](https://github.com/theniceboy/st)。

### Ranger
使用 `pip install ueberzug` 和 `ranger-git`

### Mutt 邮件设置
在 `~/.gnupg/gpg-agent.conf` 中：
```
default-cache-ttl 34560000
max-cache-ttl 34560000
```

如果这不起作用，请尝试 [pam-gnupg](https://github.com/cruegge/pam-gnupg)：
```bash
yay -S pam-gnupg-git
```

并在 `/etc/pam.d/system-local-login` 中添加：
```
auth     optional  pam_gnupg.so
session  optional  pam_gnupg.so
```

### 输入法
安装：`fcitx` `fcitx-im` `fcitx-googlepinyin` `fcitx-configtool`

并在 `/etc/X11/xinit/xinitrc` 中：
```bash
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS="@im=fcitx"
```

**注意**: Fcitx 用户需要将第一输入法设置为键盘 - 布局

### 字体

#### 本地化配置
在 `locale.conf` 中：
```
LANG=en_US.UTF-8
LC_ADDRESS=en_US.UTF-8
LC_IDENTIFICATION=en_US.UTF-8
LC_MEASUREMENT=en_US.UTF-8
LC_MONETARY=en_US.UTF-8
LC_NAME=en_US.UTF-8
LC_NUMERIC=en_US.UTF-8
LC_PAPER=en_US.UTF-8
LC_TELEPHONE=en_US.UTF-8
LC_TIME=en_US.UTF-8
```

#### 字体推荐
- **主要字体**: `Source Code Pro` 和 `nerd-fonts-source-code-pro`
- **Noto 字体**: 安装 `noto-fonts`（不是 `-all` - 它很臃肿）

#### Emoji 字体
```bash
yay -S ttf-linux-libertine ttf-inconsolata ttf-joypixels ttf-twemoji-color noto-fonts-emoji ttf-liberation ttf-droid
```

#### 中文字体
```bash
yay -S wqy-bitmapfont wqy-microhei wqy-microhei-lite wqy-zenhei adobe-source-han-mono-cn-fonts adobe-source-han-sans-cn-fonts adobe-source-han-serif-cn-fonts
```

### GTK 主题
使用 `adapta-gtk-theme` 和 `arc-icon-theme`。

### Arch 软件包
查看 [my-packages.txt](https://github.com/theniceboy/.config/blob/master/my-packages.txt) 获取完整软件包列表。

</details>

---

## Brew 安装的工具清单

<details>
<summary>完整工具列表（点击展开）</summary>

### 系统工具

| 工具 | 说明 |
|------|------|
| `htop` | 进程监控 |
| `dust` | 磁盘使用分析 |
| `ncdu` | 交互式目录分析 |
| `pipx` | Python 工具安装 |
| `uv` | 快速 pip 替代 |

### GNU 工具

| 工具 | 说明 |
|------|------|
| `coreutils` | GNU 核心工具 |
| `gnu-tar` | GNU tar |
| `gnu-sed` | 增强的流编辑器 |

### 搜索与文本处理

| 工具 | 说明 |
|------|------|
| `ripgrep` (rg) | 快速搜索 |
| `the_silver_searcher` (ag) | 代码搜索 |
| `fd` | 文件查找 |
| `fzf` | 模糊搜索 |
| `bat` | 语法高亮的 cat |
| `jq` | JSON 处理 |

### Git 工具

| 工具 | 说明 |
|------|------|
| `git` | 版本控制 |
| `git-delta` | 美化 git diff |
| `lazygit` | Git TUI |
| `gh` | GitHub CLI |

### 终端工具

| 工具 | 说明 |
|------|------|
| `tmux` | **核心工具** - 终端复用 |
| `neovim` | 现代 Vim |
| `yazi` | 终端文件管理器 |
| `starship` | 跨 shell 提示符 |
| `rainbarf` | tmux 状态栏 CPU/内存 |
| `terminal-notifier` | **Agent 完成通知** |

### NPM 全局包

| 包名 | 说明 |
|------|------|
| `@anthropic-ai/claude-code` | Claude Code |
| `ccusage` | Claude 用量统计 |
| `ccstatusline` | tmux 显示 Claude 状态 |
| `opencode-ai` | OpenCode |

</details>

---

## 参考链接

- [Claude Code Hooks Guide](https://docs.anthropic.com/en/docs/claude-code/hooks-guide)
- [Claude Code Hooks Reference](https://docs.anthropic.com/en/docs/claude-code/hooks)
- [TheCW/theniceboy .config](https://github.com/theniceboy/.config)
- [tmux 官方文档](https://github.com/tmux/tmux/wiki)
- [Zim Framework](https://zimfw.sh/)
- [go-runewidth](https://github.com/mattn/go-runewidth)

---

*最后更新: 2026-01-29*
