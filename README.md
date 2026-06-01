# AI API Aggregation Platform (AiFlowHub)

AI 模型 API 聚合平台，统一 API 接入国内模型厂商。

## 快速开始
- 开发环境：见 [开发规范](docs/06-开发规范.md)
- 部署：见 [部署报告](docs/09-部署报告.md)

### 端口约定（固定，不再自动跳变）
| 端口 | 服务 | 启动方式 |
|------|------|----------|
| 3000 | 前端（Docker / `npm start`） | `docker compose up -d` 或 `npm run start` |
| 3005 | 前端（热重载开发） | `npm run dev:alt`（Docker 占 3000 时用） |
| 8080 | HAProxy → Backend | Docker compose |
| 8082 | Backend Blue | Docker compose |
| 8083 | Backend Green | Docker compose |

> ⚠️ `npm run dev` 固定 3000。如果 Docker 已占 3000，用 `npm run dev:alt`（3005）或先停 Docker 前端。

## 文档索引
1. [需求调研报告](docs/01-需求调研报告.md)
2. [落地执行方案](docs/02-落地执行方案.md)
3. [技术执行方案](docs/03-技术执行方案.md)
4. [产品及交互设计与流程细化](docs/04-产品及交互设计与流程细化.md)
5. [开发及测试任务派发清单](docs/05-开发及测试任务派发清单.md)
6. [开发规范](docs/06-开发规范.md)
7. [测试规范](docs/07-测试规范.md)
8. [测试验收审查报告](docs/08-测试验收审查报告.md)
9. [部署报告](docs/09-部署报告.md)
10. [生产验收报告](docs/10-生产验收报告.md)（待完成）

## 运维文档
- [操作指引](docs/操作指引.md)
- [运维手册](docs/运维手册.md)
- [VPS开通说明](docs/VPS开通说明.md)

## 技术栈
Go (Gin) + Next.js 16 + Tailwind v4 + SQLite + Docker Compose

## 客户端密钥
`google_client_secret*.json` / `github_*.txt` — 保存在项目根目录，仅用于 OAuth
