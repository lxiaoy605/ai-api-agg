# ai-api-agg 项目进度

> 最后更新：2026-05-28

## 最终目标

搭建 AI 模型 API 聚合平台（面向亚美尼亚周边市场），基于 OneAPI + Docker Compose + Go 后端 + Next.js 前端。

## 检查点

### 阶段 0: 项目骨架 ✅
- [x] Go 后端骨架（Gin + SQLite + JWT + bcrypt）
- [x] Next.js 前端骨架（Tailwind CSS v4 + shadcn/ui）
- [x] Docker Compose + Nginx 配置模板
- [x] 编译验证通过，健康检查端点可用
- 报告：INIT-REPORT.md

### 阶段 1: 基础设施
- [ ] T1.1 Docker Compose 实际联调
- [ ] T1.2 OneAPI 渠道配置脚本
- [ ] T1.3 健康检查 + 故障切换
- [ ] T1.4 多账号注册 + 余额监控

### 阶段 2: 后端服务 ✅
- [x] T2.1 用户注册/登录 API (bcrypt + JWT)
- [x] T2.2 API Key 管理 CRUD (AES-256-GCM 加密)
- [ ] T2.3 Stripe Checkout 支付集成
- [ ] T2.4 Nginx 反代 + SSL

### 阶段 3: 前端
- [x] T3.1 Dashboard 仪表盘
- [x] T3.2 API Key 管理页面
- [x] T3.3 模型目录 + Developer Docs
- [x] T3.4 用量图表组件
- [ ] T3.5 USDT 充值页面

### 阶段 4: 运维与验证
- [ ] T4.1 Prometheus 监控
- [ ] T4.2 自动备份
- [ ] T4.3 端到端测试

## 下一步

按 TASKS.md 依赖链：T3.1-T3.4 ✅ → T3.5（USDT 充值页面）或 T2.3（Stripe Checkout 支付集成）。
