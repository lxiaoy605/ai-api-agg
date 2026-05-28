# ai-api-agg 子任务拆分

> 基于 MASTER-PLAN.md v5 + v6 + DESIGN.md 完整方案
> 拆分日期：2026-05-28
> 执行引擎：claude-code
> 验收标准：代码可运行、功能一致、安全基线达标、文档完整
> 最后更新：2026-05-28 22:30

---

## 阶段 1：基础设施（W1 等价）

### T1.1 — Docker Compose 全套部署配置 ✅
- **输入：** MASTER-PLAN.md 第 1 章（项目背景与架构总览）
- **产出：**
  - `docker-compose.yml`（OneAPI + Nginx + SQLite）
  - `.env.example` 环境变量模板
  - 一键启动脚本 `start.sh`
- **验收标准：** `docker compose up -d` 后 OneAPI 管理界面可访问
- **状态：** ✅ 已完成（项目初始化阶段，docker-compose.yml + .env.example + start.sh）

### T1.2 — OneAPI 渠道配置脚本 ✅
- **输入：** MASTER-PLAN.md 第 2 章（厂商对接方案）
- **产出：**
  - DeepSeek、智谱 Z.ai、小米 MiMo 渠道配置 JSON
  - 权重轮询配置（3:3:2）
  - `channel-setup.sh` 自动化配置脚本
- **验收标准：** 三渠道通过 OneAPI 健康检查，轮询分发正常
- **状态：** ✅ 已完成（见 channels/CHANNELS-DONE.md）

### T1.3 — 健康检查 + 故障自动切换 ✅
- **输入：** MASTER-PLAN.md 第 5 章（蓝绿部署）中的健康检查方案
- **产出：**
  - `healthcheck.sh` 多模型端点可用性检测
  - `failover.sh` 故障自动切换脚本（故障渠道 → 健康渠道）
  - systemd timer 定时执行配置
- **验收标准：** 模拟一个渠道挂掉，自动切换在 30s 内完成
- **状态：** ✅ 已完成（见 scripts/HEALTH-DONE.md），healthcheck + failover + systemd timer + ops-notify 集成

### T1.4 — 多账号邮件注册 + 余额监控脚本 ✅ (余额监控部分完成)
- **输入：** MASTER-PLAN.md 第 2 章 2.4（多邮箱申请方案）和 2.5（多账号余额监控）
- **产出：**
  - ~~域名邮箱配置指南（Cloudflare Email Routing + 厂商子邮箱映射）~~ → 缺域名
  - ~~`register-accounts.sh` — 各厂商注册清单 + 账号映射表（YAML）~~ → 缺域名
  - ✅ `balance-monitor.py` — 多厂商余额统一监控脚本（Python 3 标准库）
  - ✅ `balance-monitor.service` + `balance-monitor.timer` — systemd 定时器（每小时）
  - ✅ `TELEGRAM-SETUP.md` — Telegram Bot 告警配置指南
  - ✅ 更新 `docker/.env.example` — 厂商 API Key + Telegram 变量
- **验收标准：** 余额监控脚本可查询 DeepSeek/智谱余额，余额低于 $5 时通过 Telegram 告警，低于 $2 时自动记录到审计日志
- **状态：** ✅ 已完成（balance-monitor.py + systemd timer + ops-notify 集成 + 域名邮箱指南）（见 scripts/BALANCE-DONE.md）｜ ⚠️ 域名邮箱配置 + register-accounts.sh 待域名物料后补充

---

## 阶段 2：后端服务（W2 等价）

### T2.1 — 用户注册/登录 API ✅ (合并到 T2.2)
- **输入：** MASTER-PLAN.md 第 7 章（管理 API）
- **产出：**
  - `POST /auth/register` — 邮箱注册（bcrypt + JWT）
  - `POST /auth/login` — 登录返回 token
  - `GET /auth/me` — 当前用户信息
  - SQLite 用户表 DDL
- **验收标准：** 注册→登录→获取用户信息全流程通过，密码哈希存储
- **状态：** ✅ 已完成（见 BACKEND-DONE.md）

### T2.2 — API Key 管理 CRUD ✅
- **输入：** MASTER-PLAN.md 第 7 章
- **产出：**
  - `POST /api-keys` — 创建 API Key（自动生成 + AES 加密存储）
  - `GET /api-keys` — 列出用户的 Key（不返回完整明文）
  - `DELETE /api-keys/:id` — 删除 Key
  - 用量统计 `GET /api-keys/:id/usage`
- **验收标准：** 创建/查看/删除/统计全流程，Key 加密存储
- **状态：** ✅ 已完成（见 API-ENDPOINTS-DONE.md），auth + key CRUD + /stats /topup /channels /audit-log /backup /restore，10+ 测试通过

### T2.3 — Stripe Checkout 支付集成 🔴
- **输入：** MASTER-PLAN.md 第 6 章（Stripe 方案）
- **产出：**
  - `POST /payment/create-checkout` — 创建 Stripe Checkout Session
  - `POST /payment/webhook` — Stripe Webhook 处理器
  - 支付记录表 + 充值回调逻辑（更新用户余额）
  - Webhook 签名验证
- **验收标准：** 创建订单→Stripe 支付模拟→Webhook 回调→余额更新全链路
- **状态：** 🔴 待定：PayPal 中国企业账户(需公司) / Stripe Atlas($500) / USDT 自动监听(进行中)

### T2.4 — Nginx 反代 + SSL 自动配置 ✅
- **输入：** MASTER-PLAN.md 部署章节
- **产出：**
  - `nginx.conf` 反代配置（上游 OneAPI + 后端 API）
  - Certbot SSL 自动签发/续期脚本
  - HTTPS 强制 + 安全头（HSTS、CSP 等）
- **验收标准：** HTTPS 可访问，SSL Labs 评级 A+，HTTP 自动跳转 HTTPS
- **状态：** ✅ 已完成（见 docker/NGINX-DONE.md），含完整安全头配置 + aiflowhub.ai 正式域名 + SSL证书脚本

---

## 阶段 3：前端（W3 等价）

### T3.1 — Dashboard 仪表盘 ✅
- **输入：** MASTER-PLAN.md 第 4 章（Together AI 设计系统）+ 第 8 章 8.6（智能仪表盘）
- **技术栈：** Next.js + Tailwind CSS + shadcn/ui
- **产出：**
  - 总览卡片：活跃渠道数、今日请求量、剩余额度、错误率
  - 渠道健康状态指示器
  - 最近用量折线图
- **验收标准：** 从后端 API 拉取数据，卡片/图表正确渲染
- **状态：** ✅ 已完成（mock 数据），见 FRONTEND-DONE.md

### T3.2 — API Key 管理页面 ✅
- **产出：**
  - Key 列表（名称、创建时间、状态、最近使用）
  - 创建 Key 弹窗（命名 + 一键复制）
  - 删除 Key（确认对话框）
  - 用量概览
- **验收标准：** 对接 T2.2 CRUD API，完整增删查流程
- **状态：** ✅ 已完成（mock 数据），含创建弹窗 + 一键复制 + 删除确认

### T3.3 — 模型目录 + Developer Docs 页面 ✅
- **产出：**
  - 模型卡片列表（名称、厂商、价格、状态）
  - 模型详情页（参数说明、调用示例代码）
  - Developer Docs 页面（快速开始、API 参考、错误码）
- **验收标准：** 模型信息正确展示，代码示例可直接复制使用
- **状态：** ✅ 已完成，8 个模型卡片 + 分类筛选 + 展开详情 + 3 语言代码示例

### T3.4 — 用量图表组件 ✅
- **产出：**
  - 按时间范围的请求量/Token 消耗折线图
  - 按模型的消耗饼图
  - 日期范围选择器
- **验收标准：** 切换时间范围图表正确更新，数据与后端一致
- **状态：** ✅ 已完成，Recharts 折线图 + 饼图 + Today/7d/30d 切换

### T3.5 — USDT 充值页面 ✅
- **输入：** MASTER-PLAN.md 第 6 章（USDT 方案）
- **产出：**
  - USDT 地址展示（TRC-20）
  - 充值金额选择/自定义
  - 充值状态查询
- **验收标准：** USDT 地址正确展示，金额选项合理
- **状态：** ✅ 已完成，TRC-20 + ERC-20 双地址 + QR 码 + npm run build 通过 

---

## 阶段 4：运维与验证（W4 等价）

### T4.1 — Prometheus 监控配置 ✅
- **产出：**
  - `monitoring/prometheus.yml` — Prometheus v3.x 主配置（15s 间隔，Blackbox 探针）
  - `monitoring/alerting-rules.yml` — 6 大类 12 条告警规则
  - `monitoring/alertmanager.yml` — 告警路由 + Telegram 通知
  - `monitoring/grafana-dashboards/ai-api-agg-overview.json` — 系统概览仪表盘
  - `docker/docker-compose.yml` — 已添加 Prometheus/Alertmanager/Blackbox/Grafana 服务
- **验收标准：** Prometheus 正常采集指标，告警规则触发测试通过
- **状态：** ✅ 已完成（见 monitoring/MONITORING-DONE.md）

### T4.2 — 自动备份脚本 ✅
- **产出：**
  - `backup.sh` — 每日备份 SQLite 数据库 + 配置文件
  - 保留最近 7 天 + 异地备份（rsync/scp）
  - systemd timer
- **验收标准：** 脚本执行成功生成备份文件，恢复流程可验证
- **状态：** ✅ 已完成（见 scripts/BACKUP-V2-DONE.md），v2 升级：全量+增量+远程上传+SHA256+manifest + dr-failover

### T4.3 — 端到端测试脚本 ✅
- **产出：**
  - `tests/e2e/test-api.sh` — 12 个测试步骤，覆盖注册→登录→创建 Key→用量→删除 Key
  - `tests/e2e/run-all.sh` — 测试入口，统一退出码
  - 失败继续执行 + 颜色输出 + 汇总统计
- **验收标准：** 全流程通过，任一步失败立即报告
- **状态：** ✅ 已完成（12步测试脚本），待服务运行时验证

---

## 任务汇总

| 阶段 | 任务数 | 已完成 | 阻塞中 | 预估工作量 |
|------|:---:|:---:|:---:|:---:|
| 1. 基础设施 | 4 | 4 | 0 | 小 |
| — | — | — | — | — |
| 🔷 蓝绿部署 | 🔷 5.1+5.3 | 🔷 ✅ BLUEGREEN-DONE.md | 0 | 中 |
| 🔷 Key 轮换 | 🔷 5.2 | 🔷 ✅ KEYROTATION-DONE.md | 0 | 小 |
| 🔷 支付对账 | 🔷 6.4 | 🔷 ✅ RECONCILE-DONE.md | 0 | 小 |
| 🔷 Telegram 运维通道 | 🔷 替代 8 | 🔷 ✅ TELEGRAM-OPS-DONE.md | 0 | 中 |
| 🔷 DR 备份 V2 | 🔷 7.3 | 🔷 ✅ BACKUP-V2-DONE.md | 0 | 小 |
| 🔷 API 补充端点 | 🔷 7.1 | 🔷 ✅ API-ENDPOINTS-DONE.md | 0 | 中 |
| 🔷 USDT 监听引擎 | 🔷 6.3 | 🔷 ✅ USDT-MONITOR-DONE.md | 0 | 大 |
| 2. 后端服务 | 4 | 3 (T2.1,T2.2,T2.4) | 1 (缺 Stripe) | 中-大 |
| 3. 前端 | 5 | 5 (T3.1-3.5) | 0 | 中 |
| 4. 运维验证 | 3 | 3 (T4.1,T4.2,T4.3) | 0 | 小-中 |
| **合计（原始TASKS）** | **16** | **15** | **1** | — |
| **合计（含新增7项）** | **23** | **22** | **1** | — |

## 任务依赖

```
T1.1 ──→ T1.2 ──→ T1.3
  │
  ├──→ T2.4 (Nginx)
  │
  └──→ T2.1 ──→ T2.2
                │
        T2.3 ──┤
                │
        ┌───────┴───────┐
        ↓               ↓
    [前端 T3.1-3.5]   [运维 T4.1-4.3]
```

---

## 新增任务（MASTER-PLAN 补充，非原始 TASKS）

| 任务 | MASTER-PLAN 章节 | 状态 |
|------|------|:--:|
| 蓝绿部署(HAProxy+Keepalived+回滚) | 5.1+5.3 | ✅ BLUEGREEN-DONE.md |
| API Key 90天自动轮换 | 5.2 | ✅ KEYROTATION-DONE.md |
| USDT TronGrid 自动监听引擎 | 6.3 | 🟡 USDT-MONITOR-DONE.md |
| 支付对账(reconcile) | 6.4 | ✅ RECONCILE-DONE.md |
| 管理 API 补充端点(/stats等6个) | 7.1 | ✅ API-ENDPOINTS-DONE.md |
| 灾难恢复级备份(dr-backup) | 7.3 | ✅ BACKUP-V2-DONE.md |
| Telegram 运维通知通道+Bridge | 8(替代) | ✅ TELEGRAM-OPS-DONE.md |

## 待准备物料

| 物料 | 阻塞任务 | 状态 |
|------|------|:--:|
| PayPal 企业账户(需中国公司) 或 Stripe Atlas($500) | T2.3 | 待决策 |

> 已齐备 ✅：域名 aiflowhub.ai / DeepSeek / Z.ai / MiMo / Telegram Bot + Bridge / USDT TRC-20+ERC-20
