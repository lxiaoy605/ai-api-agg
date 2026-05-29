# AI API 聚合平台 (ai-api-agg)

AI API 聚合与转售服务。单一 OpenAI 兼容端点，统一接入 DeepSeek、智谱、小米 MiMo 等模型。

**状态：** MVP 运行中 | 蓝绿部署 | 前端上线

---

## 项目结构

```
ai-api-agg/
├── backend/                    # Go 后端 (API 代理 + 业务逻辑)
│   ├── cmd/server/             # 主入口
│   └── internal/
│       ├── admin/              # 管理 API
│       ├── apikey/             # API Key 管理
│       ├── audit/              # 审计日志
│       ├── config/             # 配置管理
│       ├── database/           # 数据库
│       ├── middleware/         # 中间件 (认证/限流/CORS)
│       ├── models/             # 数据模型
│       ├── notify/             # 通知 (Telegram)
│       └── payment/            # 支付 (NOWPayments/USDT)
│
├── frontend/                   # Next.js 前端
│   └── src/
│       ├── app/                # App Router 页面
│       │   ├── page.tsx               # Landing
│       │   └── (main)/
│       │       ├── dashboard/         # 仪表盘
│       │       ├── api-keys/          # API Key 管理
│       │       ├── models/            # 模型列表
│       │       ├── docs/              # 文档
│       │       ├── recharge/          # 充值
│       │       └── usage/             # 用量分析
│       ├── components/
│       │   ├── layout/         # 布局组件 (Sidebar/TopNav)
│       │   └── charts/         # 图表组件
│       └── messages/           # i18n (en/ru/tr)
│
├── stack/                      # Docker Compose 生产部署
│   ├── docker-compose.yml      # 完整服务编排
│   ├── .env                    # 环境变量 (API Keys)
│   ├── haproxy/                # 负载均衡 (蓝绿)
│   ├── nginx/                  # HTTPS 反向代理
│   ├── keepalived/             # VIP 高可用
│   └── oneapi/                 # OneAPI 引擎 (.env)
│
├── scripts/                    # 运维脚本
│   ├── init.sh                 # 一键初始化 (Key 验证→模型发现→渠道创建)
│   ├── deploy.sh               # 部署脚本
│   ├── bluegreen-deploy.sh     # 蓝绿部署
│   ├── bluegreen-switch.sh     # 蓝绿切换
│   ├── backup.sh               # 自动备份
│   ├── restore.sh              # 备份恢复
│   ├── healthcheck.sh          # 健康检查
│   ├── balance-monitor.py      # 余额监控
│   ├── ops-daily-report.sh     # 每日运营报告
│   └── rotate-channel-key.sh   # Key 轮换
│
├── monitoring/                 # 可观测性
│   ├── prometheus.yml          # Prometheus 配置
│   └── grafana/                # Grafana 仪表盘
│
├── tests/
│   └── e2e/                    # 端到端测试
│       ├── test-api.sh
│       └── run-all.sh
│
├── channels/                   # 渠道配置
│   ├── channel-configs.json    # 模型渠道定义
│   └── channel-setup.sh        # 渠道初始化
│
└── docs/                       # 项目文档
```

## 技术栈

| 层 | 技术 | 说明 |
|----|------|------|
| 前端 | Next.js 15 (App Router) + Tailwind CSS 4 | React 19, SSR, i18n (en/ru/tr) |
| 后端 | Go 1.21+ | API 代理、Key 管理、支付集成 |
| API 引擎 | OneAPI | 渠道管理、负载均衡、配额 |
| 负载均衡 | HAProxy | 蓝绿部署、健康检查 |
| 反向代理 | Nginx | HTTPS、静态文件、路由 |
| 数据库 | SQLite | 轻量级单机数据库 |
| 监控 | Prometheus + Grafana | 指标收集、可视化、告警 |
| 支付 | NOWPayments | 非托管加密网关 (USDT) |
| 容器 | Docker Compose | 一键部署 |

## 架构

```
用户 → Nginx (443) → Frontend (3000)
                    → API (8080) → HAProxy → OneAPI Blue (3001) → Provider APIs
                                            → OneAPI Green (3002)
                    监控层: Prometheus (9090) → Grafana (3030)
```

- **蓝绿部署**：两套 OneAPI 实例，HAProxy 按健康检查切换，零停机更新
- **Key 轮换**：自动检测过期 Key，支持热替换
- **支付系统**：NOWPayments 自动回调确认，USDT 链上对账

## 快速开始

```bash
# 一键初始化
bash scripts/init.sh

# 或分步执行
bash scripts/deploy.sh          # 构建并启动所有服务
bash scripts/init.sh --dry-run  # 先验证 Key 有效性

# 查看状态
docker compose -f stack/docker-compose.yml ps
```

### 服务端口

| 说明 | 地址 |
|------|------|
| 前端 | https://api-hub.local |
| OneAPI Blue | http://localhost:3001 |
| OneAPI Green | http://localhost:3002 |
| HAProxy 统计 | http://localhost:8081 |
| Grafana | http://localhost:3030 |
| Prometheus | http://localhost:9090 |

## 环境变量 (`stack/.env`)

```bash
# DeepSeek
DEEPSEEK_API_KEY=sk-xxx
DEEPSEEK_API_KEY_2=sk-xxx

# 智谱 Z.ai
ZHIPU_API_KEY=xxx
ZHIPU_API_KEY_2=xxx

# 小米 MiMo
MIMO_API_KEY=xxx
MIMO_API_KEY_2=xxx
MIMO_API_BASE=https://token-plan-sgp.xiaomimimo.com/v1
```

## 活跃任务

见顶部「关键进度」及 `TASKS.md`。

---

_最后更新：2026-05-29_
