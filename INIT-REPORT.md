# AI API 聚合平台 — 项目初始化报告

> 日期：2026-05-28
> 执行者：Claude Code
> 阶段：骨架初始化（阶段 0）

---

## 一、创建的文件清单

### 后端 (`backend/`)

| 文件 | 说明 |
|------|------|
| `go.mod` | Go 模块定义，module = `github.com/ai-api-agg/backend` |
| `go.sum` | 依赖校验文件（自动生成） |
| `cmd/server/main.go` | Gin 最简 HTTP 服务器，含 `GET /health` 健康检查端点 |
| `internal/auth/` | 认证模块（目录占位） |
| `internal/apikey/` | API Key 管理模块（目录占位） |
| `internal/payment/` | 支付模块（目录占位） |
| `internal/middleware/` | 中间件模块（目录占位） |
| `internal/config/` | 配置加载模块（目录占位） |

### 前端 (`frontend/`)

| 文件 | 说明 |
|------|------|
| `package.json` | Node.js 项目定义 |
| `tsconfig.json` | TypeScript 配置（Next.js 标准） |
| `next.config.js` | Next.js 配置 |
| `postcss.config.mjs` | PostCSS 配置（Tailwind CSS 插件） |
| `src/app/globals.css` | 全局样式（Tailwind CSS v4 引入） |
| `src/app/layout.tsx` | 根布局（中文 metadata） |
| `src/app/page.tsx` | 首页（项目标题 + 模型标签） |
| `src/lib/utils.ts` | cn() 工具函数（shadcn/ui 必备） |
| `src/components/ui/` | shadcn/ui 组件（目录占位） |
| `src/components/dashboard/` | 仪表盘组件（目录占位） |

### Docker (`docker/`)

| 文件 | 说明 |
|------|------|
| `docker-compose.yml` | Docker Compose 编排（OneAPI + Nginx + 后端/前端占位） |
| `nginx/nginx.conf` | Nginx 反代配置模板（含 SSL 占位） |
| `oneapi/.env.example` | OneAPI 环境变量模板 |

### 配置与脚本

| 文件 | 说明 |
|------|------|
| `config/config.example.yaml` | 应用配置模板（服务器/数据库/JWT/支付/CORS/限流） |
| `scripts/start.sh` | 开发环境一键启动脚本 |
| `scripts/healthcheck.sh` | 健康检查脚本 |

---

## 二、组件版本

### Go 后端核心依赖

| 包 | 版本 | 用途 |
|----|------|------|
| Go SDK | 1.25.1 | 运行时 |
| gin-gonic/gin | v1.12.0 | HTTP 框架 |
| golang-jwt/jwt/v5 | v5.3.1 | JWT 认证 |
| golang.org/x/crypto | v0.52.0 | bcrypt 密码哈希 |
| modernc.org/sqlite | v1.50.1 | 纯 Go SQLite（无 CGO） |

### 前端核心依赖

| 包 | 版本 | 用途 |
|----|------|------|
| next | 15.5.18 | React 全栈框架 |
| react | 19.2.6 | UI 库 |
| tailwindcss | 4.3.0 | 原子化 CSS |
| lucide-react | 0.503.0 | 图标库 |
| typescript | 5.9.3 | 类型检查 |
| class-variance-authority | 0.7.1 | 组件变体（shadcn/ui 依赖） |
| tailwind-merge | 3.6.0 | 类名合并（shadcn/ui 依赖） |
| clsx | 2.1.1 | 条件类名（shadcn/ui 依赖） |

### 基础设施

| 组件 | 版本 | 用途 |
|------|------|------|
| Docker | 29.1.3 | 容器运行时 |
| Docker Compose | v5.1.3 | 服务编排 |
| OneAPI | justsong/one-api:latest | AI 模型网关 |
| Nginx | nginx:alpine | 反向代理 |

---

## 三、启动开发环境

### 方式一：一键启动

```bash
cd /mnt/d/WSL/openclawWorkspace/workspace/projects/ai-api-agg
bash scripts/start.sh
```

### 方式二：分步启动

```bash
# 1. 启动 Docker 基础设施
cd docker
cp oneapi/.env.example oneapi/.env   # 首次需复制配置
docker compose up -d oneapi nginx

# 2. 启动 Go 后端
cd ../backend
go run ./cmd/server

# 3. 启动前端（新终端）
cd ../frontend
npm run dev
```

### 访问地址

| 服务 | 地址 |
|------|------|
| 前端页面 | http://localhost:3001 |
| OneAPI 管理 | http://localhost:3000 |
| 后端健康检查 | http://localhost:8080/health |
| Nginx 入口 | http://localhost:80 |

---

## 四、编译验证结果

- **Go 后端**：`go build ./cmd/server` ✅ 通过
- **Next.js 前端**：`npm run build` ✅ 通过（静态页面预渲染成功）

---

## 五、待完成事项

以下任务按 TASKS.md 的阶段划分。当前已完成**阶段 0（项目骨架）**。

### 阶段 1 — 基础设施
- [ ] T1.1 Docer Compose 部署配置（已建骨架，待实际联调）
- [ ] T1.2 OneAPI 渠道配置脚本（DeepSeek / 智谱 / MiMo）
- [ ] T1.3 健康检查 + 故障自动切换
- [ ] T1.4 多账号邮件注册 + 余额监控脚本

### 阶段 2 — 后端服务
- [ ] T2.1 用户注册/登录 API（`internal/auth/`）
- [ ] T2.2 API Key 管理 CRUD（`internal/apikey/`）
- [ ] T2.3 Stripe Checkout 支付集成（`internal/payment/`）
- [ ] T2.4 Nginx 反代 + SSL 自动配置（`docker/nginx/`）

### 阶段 3 — 前端
- [ ] T3.1 Dashboard 仪表盘（`src/components/dashboard/`）
- [ ] T3.2 API Key 管理页面
- [ ] T3.3 模型目录 + Developer Docs
- [ ] T3.4 用量图表组件
- [ ] T3.5 USDT 充值页面

### 阶段 4 — 运维与验证
- [ ] T4.1 Prometheus 监控配置
- [ ] T4.2 自动备份脚本
- [ ] T4.3 端到端测试脚本

### 其他
- [ ] 安全扫描（依赖漏洞、密钥泄露检查）
- [ ] `.gitignore` 完善（排除二进制、node_modules、.env）
- [ ] CI/CD pipeline 配置（GitHub Actions）

---

## 六、下一步

推荐按 TASKS.md 中 T1.1 → T1.2 → T2.1 → T2.2 → T2.3 → T3.1 的顺序推进。
下一个待执行任务：**T1.1 — Docker Compose 实际联调**，确认 OneAPI 容器可正常启动和访问。

> 完整任务清单见 `TASKS.md` | 完整技术方案见 `MASTER-PLAN.md`
