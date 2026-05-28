# 支付对账系统 — 完成报告

> **任务:** MASTER-PLAN 6.4 — 支付对账系统
> **完成日期:** 2026-05-28
> **产出文件:** 3 个

---

## 产出清单

| 文件 | 说明 |
|------|------|
| `scripts/reconcile-payments.sh` | 支付对账脚本（bash + Python） |
| `scripts/reconcile-payments.service` | systemd 服务单元 |
| `scripts/reconcile-payments.timer` | systemd 定时器（每日 02:00） |

---

## reconcile-payments.sh 功能

- **按日对账**: 默认昨天，`--date YYYY-MM-DD` 指定日期
- **Stripe 对账**: `GET /v1/balance_transactions` vs 本地 `payment_log` 表
- **USDT 对账**: TronGrid TRC-20 API vs 本地 `payment_log` 表
- **双输出模式**: 文本报告（默认）/ JSON 报告（`--json`）
- **异常告警**: 差异时通过 `ops-notify.sh` 发送运维通知
- **API 未配**: Stripe/USDT API 未配时标注 N/A，不报错

### 用法

```bash
# 对账昨天
./scripts/reconcile-payments.sh

# 对账指定日期
./scripts/reconcile-payments.sh --date 2026-05-27

# JSON 输出（供外部消费）
./scripts/reconcile-payments.sh --json
```

### 环境变量

| 变量 | 说明 | 必须 |
|------|------|:---:|
| `STRIPE_SECRET` | Stripe Secret Key | 否 |
| `TRON_PRO_API_KEY` | TronGrid API Key | 否 |
| `USDT_WALLET` | USDT TRC-20 收款地址 | 否 |
| `DATABASE_PATH` | SQLite 数据库路径 | 否 |
| `TELEGRAM_BOT_TOKEN` | Telegram Bot Token | 否 |
| `TELEGRAM_CHAT_ID` | Telegram Chat ID | 否 |

---

## 文本报告示例

```
============================================
  支付对账报告 — 2026-05-27
============================================

 Stripe:  API 5笔/$120.00 | 本地 5笔/$120.00 | 差异 0 ✅
 USDT:   链上 3笔/$250.00 | 本地 3笔/$250.00 | 差异 0 ✅

────────────────────────────────────────────
 未入账交易: 0 笔
 未到账支付: 0 笔
============================================
```

差异时显示 ❌ 红色标记并触发运维通知。

---

## JSON 输出结构

```json
{
  "date": "2026-05-27",
  "generated_at": "2026-05-28T14:55:01+00:00",
  "stripe": {
    "status": "OK",
    "api": {"count": 5, "amount_usd": "120.00"},
    "local": {"count": 5, "amount_usd": "120.00"},
    "diff": {"count": 0, "amount_usd": "0.00"},
    "match": true
  },
  "usdt": {
    "status": "N/A",
    "api": {"count": 0, "amount_usd": "0.00"},
    "local": {"count": 0, "amount_usd": "0.00"},
    "diff": {"count": 0, "amount_usd": "0.00"},
    "match": true
  },
  "summary": {
    "missing_from_local": 0,
    "extra_in_local": 0
  }
}
```

---

## systemd 部署

```bash
# 复制单元文件
sudo cp scripts/reconcile-payments.service /etc/systemd/system/
sudo cp scripts/reconcile-payments.timer /etc/systemd/system/

# 启用定时器
sudo systemctl daemon-reload
sudo systemctl enable reconcile-payments.timer
sudo systemctl start reconcile-payments.timer

# 查看状态
sudo systemctl status reconcile-payments.timer
sudo systemctl list-timers | grep reconcile

# 手动触发一次
sudo systemctl start reconcile-payments.service

# 查看日志
sudo journalctl -u reconcile-payments.service -n 50
```

---

## 技术实现说明

- **JSON 解析**: 使用 Python 3（`python3 -c`）内联脚本，无需安装 jq
- **Stripe API**: Basic Auth，按 `created[gte]/[lte]` 时间范围过滤 `type=charge`
- **TronGrid API**: 按 `min_timestamp/max_timestamp` 查询 TRC-20 转入，过滤 `to=wallet & type=Transfer`
- **USDT 精度**: TRC-20 6 位小数，脚本自动转换
- **通知**: 通过 `ops-notify.sh` 统一发送运维告警

## 依赖

- `bash` 4.x+
- `python3` (用于 JSON 解析和浮点运算)
- `sqlite3` (用于本地数据库查询)
- `curl` (用于 API 请求)
- `ops-notify.sh` (用于运维告警通知)
