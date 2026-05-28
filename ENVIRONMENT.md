# ai-api-agg 开发环境

> 最后更新：2026-05-28
> 面向 Claude Code / hermes 执行环境

## 运行时

| 组件 | 版本 | 备注 |
|------|------|------|
| OS | Ubuntu 24.04 (WSL2) | 6.6.114.1-microsoft-standard-WSL2 |
| Go | 1.25.1 | `/home/openclaw/go-sdk` |
| Node.js | 22.22.2 | npm 10.9.7 |
| Python | 3.12 | 带 sqlite3 模块 |
| Docker | 29.1.3 | Compose v5.1.3, Docker Desktop |
| SQLite | 3.49.1 | CLI + libsqlite3-0 |

## 网络访问

- 外部 API 可达：DeepSeek、智谱、小米 MiMo、GitHub 等
- Docker 容器间通信：bridge 网络
- 宿主机端口：18789(Gateway)、7023(OmniBox)

## 可用基础镜像

- `oneapi` 开源网关（Docker Hub）
- MySQL 8.0（已有容器运行中，但 ai-api-agg 用 SQLite）
- Nginx（可拉取）

## 项目目录结构

```
projects/ai-api-agg/
├── .claude/              # Claude Code 项目配置
├── MASTER-PLAN.md        # 完整技术方案
├── TASKS.md              # 子任务拆分
├── README.md             # 项目说明
├── backend/              # Go 后端服务
├── frontend/             # Next.js 前端
├── docker/               # Docker Compose + Nginx 配置
├── scripts/              # 运维/工具脚本
└── config/               # YAML 配置文件
```

## Claude Code 可用 Agent

| Agent | 模型 | 用途 |
|-------|------|------|
| default | deepseek-v4-pro | 通用开发 |
| backend-dev | bailian/qwen3.6-max-preview | 后端专精 |
| frontend-dev | moonshotai/kimi-k2.6 | 前端专精 |
| code-review | moonshotai/kimi-k2.6 | 代码审查 |
| fast-task | google/gemini-2.5-flash | 快速简单任务 |

## 环境变量（Go/Python 开发用）

```bash
export GOROOT=/home/openclaw/go-sdk
export GOPATH=/home/openclaw/go-projects
export PATH=$GOROOT/bin:$GOPATH/bin:$HOME/.local/bin:$PATH
```
