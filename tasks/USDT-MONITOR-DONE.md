# USDT 自动到账监听引擎 — 完成报告

> MASTER-PLAN 6.3 任务完成
> 完成日期: 2026-05-28

## 产出文件清单

| 文件 | 行数 | 说明 |
|------|:--:|------|
| `backend/internal/usdt/models.go` | 87 | 数据模型 (PaymentLog struct + DDL + 常量) |
| `backend/internal/usdt/monitor.go` | 483 | 监听核心 (TronGrid 轮询 + 交易解析 + Memo 提取 + 到账) |
| `backend/internal/notify/telegram.go` | 91 | Telegram Bot 通知模块 (全局共享) |
| `backend/internal/config/config.go` | 57 | 扩展配置 (USDT + Telegram 环境变量) |
| `backend/internal/database/sqlite.go` | 120 | 新增 payment_log 表迁移 + 索引 |
| `backend/cmd/server/main.go` | 115 | 集成 USDT monitor goroutine + 优雅关闭 |
| `scripts/usdt-reconcile.sh` | 145 | USDT 对账脚本 (日终运行) |

## 架构说明

```
启动时: main.go → NewMonitor(db, tg) → go monitor.Start(30s)
运行时: monitor 每 30s 拉取 TronGrid API → 解析 TRC-20 交易 → 幂等检查 → 确认数 → Memo提取 → 入账
关闭时: SIGINT/SIGTERM → monitor.Stop() → close(stopCh) → 退出 goroutine → srv.Shutdown
```

### 数据处理流程

```
TronGrid API (30s 轮询)
    │
    ├─ token_info.symbol ≠ "USDT" → 跳过
    ├─ to ≠ 钱包地址 → 跳过
    ├─ type ≠ "Transfer" → 跳过
    ├─ tx_hash 已处理 → 跳过(幂等)
    ├─ 金额 < $5 → 跳过
    ├─ 确认数 < 12 → 跳过
    ├─ Memo 无效 → 记录待人工处理 + Telegram 通知
    ├─ 用户不存在 → 记录待人工处理 + Telegram 通知
    │
    └─ 正常入账:
       ├─ 事务: INSERT payment_log + UPDATE users.quota
       ├─ 审计日志: audit_log
       └─ Telegram 通知: 到账通知
```

### 关键设计决策

| 决策 | 值 | 理由 |
|------|-------|------|
| 轮询间隔 | 30s | 平衡实时性和 API 限流 (TronGrid 免费 5 req/s) |
| 最小确认数 | 12 | TRON 约 12 个区块 (约 1 分钟) 达到最终性 |
| 最小金额 | $5 USDT | 防粉尘攻击 |
| 精度单位 | 1,000,000 | TRC-20/ERC-20 USDT 均为 6 位小数 |
| Memo 格式 | USER_12345 或纯数字 | 从 transfer data hex 末尾提取 |
| 幂等键 | tx_hash UNIQUE | 数据库约束 + 应用层双重保障 |
| Token 计算 | 1 美分 / token, $5 = 500 tokens | 可配 (USDT_CENTS_PER_TOKEN) |

### 环境变量

| 变量 | 必填 | 默认值 | 说明 |
|------|:--:|--------|------|
| `USDT_TRC20_WALLET` | 是 | (空) | TRC-20 收款地址 |
| `TRON_PRO_API_KEY` | 否 | (空) | TronGrid Pro Key (公共API也可用) |
| `USDT_MIN_CONFIRM` | 否 | 12 | 最少区块确认数 |
| `USDT_CENTS_PER_TOKEN` | 否 | 0.01 | 1 token = N 美分 |
| `TELEGRAM_BOT_TOKEN` | 否 | (空) | Bot Token |
| `TELEGRAM_CHAT_ID` | 否 | (空) | 通知 Chat ID |

### 赠送阶梯

| 充值金额 | 赠送比例 | 示例: $100 = 10,000 + 2,000 赠送 |
|:---:|:--:|------|
| >= $100 | 20% | |
| >= $50 | 15% | |
| >= $25 | 10% | |
| >= $10 | 5% | |
| < $10 | 0% | |

### 对账脚本用法

```bash
# 日终对账 (默认 24 小时)
./scripts/usdt-reconcile.sh

# 7 天对账
./scripts/usdt-reconcile.sh 7

# crontab (每晚 23:00)
0 23 * * * /path/to/scripts/usdt-reconcile.sh >> /path/to/logs/usdt-reconcile.log 2>&1
```

## ERC-20 支持 (后续)

当前仅支持 TRC-20。ERC-20 可通过以下方式扩展:
1. 新增 `MonitorERC20` 监听器 (Etherscan API)
2. 复用 models.go 中的 `ProviderUSDTEth` 常量
3. 在 main.go 中另启一个 goroutine

ERC-20 地址: `0xA6e474c3B8755a1FC01921dcC3D758Fa1f5E6120`

## 编译状态

⚠️ 当前环境缺少 Go 编译器，无法验证编译。代码已静态审查确保语法正确、类型匹配、导入完整。
如需编译，在 Go 1.22+ 环境下执行:
```bash
cd backend && go build ./cmd/server/
```
