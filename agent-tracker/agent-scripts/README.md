# Agent Scripts - Git Worktree + tmux 工作流

基于 TheCW 的 tmux agent 工作流，使用 **Git Worktree** 实现多分支并行开发。

## 核心概念

```
┌─────────────────────────────────────────────────────────────┐
│  start-agent "feature-1"                                    │
│       ↓                                                     │
│  创建 worktree + 分支 + tmux window + dev server            │
│       ↓                                                     │
│  开发中... (可以同时开多个 feature)                          │
│       ↓                                                     │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │ 关闭窗口        │    │ ../destroy.sh   │                │
│  │ (Ctrl+D/kill)   │    │                 │                │
│  └────────┬────────┘    └────────┬────────┘                │
│           ↓                      ↓                          │
│  worktree 保留 ✅         worktree 删除 ❌                  │
│  resume-agent 可恢复      无法恢复                          │
└─────────────────────────────────────────────────────────────┘
```

## 目录结构

```
my_app/                      # 项目根目录 (.git 在这里)
├── backend/                 # 后端代码
├── frontend/                # 前端代码
├── start-agent              # 创建 agent
├── resume-agent             # 恢复/切换 agent
├── destroy.sh               # 销毁模板 (会复制到 feature 目录)
├── on-tmux-window-activate.sh  # 窗口切换同步 (可选)
├── .agent-config            # 项目配置文件
└── agents/features/
    └── feature-1/
        ├── destroy.sh       # ../destroy.sh 执行这个
        └── repo/            # git worktree
            ├── backend/
            └── frontend/
```

## 脚本说明

### 1. `start-agent` - 创建新 Agent

```bash
./start-agent "feature-1"    # 创建 feature-1
./start-agent "fix-bug"      # 创建 fix-bug
```

**自动执行**:
- 创建 git worktree（独立工作目录）
- 创建同名分支（从 BASE_BRANCH）
- 创建 tmux window（3 pane 布局）
- 启动 dev server
- 打开浏览器

### 2. `resume-agent` - 恢复/切换 Agent

```bash
./resume-agent              # 交互式选择 (支持 fzf)
./resume-agent "feature-1"  # 直接切换/恢复
```

**场景**:
- 窗口已打开 → 切换到该窗口
- 窗口关闭但 worktree 存在 → 重新创建窗口
- worktree 不存在 → 报错

### 3. `destroy.sh` - 销毁 Agent

```bash
# 在 worktree 目录中执行
../destroy.sh           # 交互确认
../destroy.sh -y        # 跳过确认
../destroy.sh --keep    # 只关窗口，保留 worktree
```

**自动执行**:
- 停止 dev server 进程
- 删除 git worktree
- 删除分支
- 关闭 tmux 窗口

### 4. `on-tmux-window-activate.sh` - 窗口切换同步 (可选)

通过 tmux hook 自动调用，切换窗口时:
- 刷新 lazygit
- 切换浏览器标签页

## 配置

### 方式一：使用 `.agent-config` 文件（推荐）

在项目根目录创建 `.agent-config` 文件：

```bash
# Next.js 项目示例
PORT_BASE=3000
DEV_SERVER_CMD="npm run dev -- --port \$PORT"
BROWSER="chrome"
AUTO_OPEN_BROWSER=true
BASE_BRANCH="main"
```

```bash
# FastAPI 项目示例
PORT_BASE=8000
DEV_SERVER_CMD="source .venv/bin/activate && uvicorn main:app --reload --port \$PORT"
BROWSER="chrome"
AUTO_OPEN_BROWSER=true  # 打开 Swagger UI
BASE_BRANCH="main"
```

```bash
# Flutter Web 项目示例
PORT_BASE=9100
DEV_SERVER_CMD="flutter run -d chrome --web-port=\$PORT"
BROWSER=""  # Flutter 会自动打开 Chrome
AUTO_OPEN_BROWSER=false
BASE_BRANCH="develop"
```

```bash
# Flutter Mobile 项目示例
PORT_BASE=9100
DEV_SERVER_CMD="flutter run -d 'iPhone 15 Pro'"
BROWSER=""
AUTO_OPEN_BROWSER=false
BASE_BRANCH="develop"
```

```bash
# Node.js 后端项目示例
PORT_BASE=4000
DEV_SERVER_CMD="npm run dev -- --port \$PORT"
BROWSER=""  # 后端项目通常不需要浏览器
AUTO_OPEN_BROWSER=false
BASE_BRANCH="main"
```

```bash
# 全栈项目示例 (FastAPI + React)
FULLSTACK_MODE=true

# 前端配置
FRONTEND_DIR="frontend"
FRONTEND_PORT_BASE=3000
FRONTEND_CMD="npm run dev -- --port \$PORT"

# 后端配置
BACKEND_DIR="backend"
BACKEND_PORT_BASE=8000
BACKEND_CMD="source .venv/bin/activate && uvicorn main:app --reload --port \$PORT"

# 通用配置
BROWSER="chrome"
AUTO_OPEN_BROWSER=true
BASE_BRANCH="main"
```

### 方式二：直接修改 `start-agent` 默认配置

修改 `start-agent` 顶部的配置区：

```bash
PORT_BASE=3000           # 端口基数
DEV_SERVER_CMD="npm run dev -- --port \$PORT"  # Dev Server 命令
BROWSER="chrome"         # 浏览器 (chrome, safari, arc, "")
AUTO_OPEN_BROWSER=true   # 是否自动打开浏览器
BASE_BRANCH="develop"    # 基础分支
```

### 配置变量说明

| 变量 | 说明 | 示例 |
|------|------|------|
| `PORT_BASE` | 端口基数，实际端口 = PORT_BASE + 窗口索引 | `3000`, `8000`, `9100` |
| `DEV_SERVER_CMD` | Dev Server 启动命令，`$PORT` 会被替换 | `npm run dev -- --port $PORT` |
| `BROWSER` | 浏览器类型，空字符串表示不打开 | `chrome`, `safari`, `arc`, `""` |
| `AUTO_OPEN_BROWSER` | 是否自动打开浏览器 | `true`, `false` |
| `BASE_BRANCH` | 新分支的基础分支 | `main`, `develop` |

## 安装

```bash
# 复制到项目根目录
cp start-agent resume-agent destroy.sh ~/projects/my_app/
chmod +x ~/projects/my_app/start-agent
chmod +x ~/projects/my_app/resume-agent
chmod +x ~/projects/my_app/destroy.sh

# 可选: 复制窗口切换同步脚本
cp on-tmux-window-activate.sh ~/projects/my_app/
chmod +x ~/projects/my_app/on-tmux-window-activate.sh

# 创建项目配置文件
cp examples/nextjs.agent-config ~/projects/my_app/.agent-config
# 根据需要修改配置
vim ~/projects/my_app/.agent-config
```

## 窗口布局

**单服务模式** (3 pane):
```
┌────────────────────────┬──────────────────────┐
│                        │      lazygit         │
│                        │      (pane 1)        │
│       主终端           ├──────────────────────┤
│      (pane 0)          │    dev server        │
│                        │      (pane 2)        │
└────────────────────────┴──────────────────────┘
```

**全栈模式** (4 pane, `FULLSTACK_MODE=true`):
```
┌────────────────────────┬──────────────────────┐
│                        │      lazygit         │
│                        │      (pane 1)        │
│       主终端           ├──────────────────────┤
│      (pane 0)          │  frontend server     │
│                        │      (pane 2)        │
│                        ├──────────────────────┤
│                        │  backend server      │
│                        │      (pane 3)        │
└────────────────────────┴──────────────────────┘
```

## 工作流示例

```bash
# 1. 开始新功能
cd ~/projects/my_app
./start-agent "feature-login"

# 2. 开发中...

# 3. 临时关闭窗口 (worktree 保留)
# Ctrl+D 或 tmux kill-window

# 4. 恢复窗口
./resume-agent "feature-login"

# 5. 完成后彻底销毁
../destroy.sh
```

## Git Worktree 优势

- **并行开发**: 每个分支独立目录，可同时运行多个 dev server
- **无需 stash**: 切换不影响未提交的修改
- **快速切换**: 切换窗口 = 切换分支
- **隔离环境**: 每个 worktree 独立的 node_modules 等

## 常用命令

```bash
git worktree list          # 查看所有 worktree
git worktree prune         # 清理失效引用
```

## 示例配置文件

`examples/` 目录包含不同项目类型的配置示例：

| 配置文件 | 端口 | 特点 |
|---------|------|------|
| `nextjs.agent-config` | 3000+ | npm install, Chrome |
| `fastapi.agent-config` | 8000+ | venv, Swagger UI |
| `nodejs.agent-config` | 4000+ | npm install, 无浏览器 |
| `flutter-web.agent-config` | 9100+ | pub get, 自动打开 Chrome |
| `flutter-mobile.agent-config` | - | 模拟器, 无浏览器 |
