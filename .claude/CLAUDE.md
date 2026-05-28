# ai-api-agg Project — Claude Code 指令

> AI 模型 API 聚合平台，基于 OneAPI 开源网关 + Docker Compose 部署

## 项目路径

- 工作目录：`/mnt/d/WSL/openclawWorkspace/workspace/projects/ai-api-agg/`
- 所有产出物写入此目录下的对应子目录

## 技术栈

- 后端：Go (Gin) + SQLite (WAL 模式)
- 前端：Next.js + Tailwind CSS + shadcn/ui
- 部署：Docker Compose + Nginx + Certbot
- 网关：OneAPI (MIT 开源)
- 支付：Stripe Checkout + USDT TRC-20

## 编码规范

- 回复中文
- 所有文件路径使用绝对路径
- 代码注释使用中文
- 配置文件使用 YAML 优先
- 敏感信息（API Key、Token）不写入代码，使用环境变量

## 进度记录

- 每完成一个任务，在 `tasks/` 目录下创建 `{task-id}-done.md` 记录产出
- 遇到阻塞问题写 `tasks/{task-id}-blocked.md`
