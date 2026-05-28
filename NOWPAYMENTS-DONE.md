# NOWPayments 支付网关集成 — 完成记录

**日期**: 2026-05-28
**任务**: 替换静态 USDT 地址充值页为 NOWPayments API 驱动的结账流程

## 产出文件

### 新建
| 文件 | 说明 |
|------|------|
| `backend/internal/payment/nowpayments.go` | NOWPayments API 客户端（创建支付、查询状态、获取币种、IPN 验证） |
| `backend/internal/payment/handler.go` | 支付 HTTP 处理器（4 个端点 + token/bonus 计算 + 自动到账） |

### 修改
| 文件 | 变更 |
|------|------|
| `backend/internal/config/config.go` | 新增 `NowPaymentsAPIKey`、`NowPaymentsSecret`、`NowPaymentsURL` 配置字段 |
| `backend/cmd/server/main.go` | 导入 payment 包，创建 handler，注册 4 条支付路由 |
| `docker/.env.example` | 新增 `NOWPAYMENTS_API_KEY`、`NOWPAYMENTS_IPN_SECRET`、`NOWPAYMENTS_API_URL`、IPN/Success/Cancel URL 环境变量 |
| `frontend/src/data/recharge.ts` | 替换静态 USDT 地址数据为 NOWPayments API 类型定义 + fetch 函数 + token 估算 |
| `frontend/src/app/(main)/recharge/page.tsx` | 完全重写为状态机驱动的支付页面（选择→创建→等待→完成/失败/降级） |

## API 端点

| 方法 | 路径 | 认证 | 说明 |
|------|------|------|------|
| GET | `/api/payment/currencies` | 无 | 可用币种列表（NOWPayments 实时 + fallback） |
| POST | `/api/payment/create` | JWT | 创建支付订单（amount_cents + pay_currency） |
| GET | `/api/payment/status/:payment_id` | JWT | 查询支付状态（含自动到账） |
| POST | `/api/payment/webhook` | IPN 签名 | NOWPayments 回调通知 |

## 页面状态机

```
select → creating → pending → completed
                   ↓           ↘ failed
                   fallback
```

- **select**: 金额选择（$5/$10/$20/$50/$100 + 自定义）+ 网络选择（TRC-20/ERC-20/BEP-20）
- **creating**: 调用 API 创建支付，显示 loading
- **pending**: QR 码 + 地址 + 复制 + 倒计时（60min）+ 每 5 秒轮询状态
- **completed**: 成功页面，显示到账 token 数量
- **failed**: 失败/过期，可重新充值
- **fallback**: API 不可用时降级为静态 USDT 地址

## Token 计算

- 基础: amount_cents / 0.01（$1 = 100 tokens）
- Bonus: ≥$10: +5%, ≥$25: +10%, ≥$50: +15%, ≥$100: +20%
- 配置: `USDT_CENTS_PER_TOKEN` 环境变量（默认 0.01）

## 安全和幂等

- IPN 回调: HMAC-SHA512 签名验证（可选，`NOWPAYMENTS_IPN_SECRET`）
- 幂等: `payment_log` 表仅 `status != 'completed'` 时更新额度
- 事务: 额度更新使用 DB 事务保证原子性
- USDT Monitor: 保留 `monitor.go` 作为对账备份，两者可共存

## 部署前配置

在 `.env` 中填入:
```bash
NOWPAYMENTS_API_KEY=your_nowpayments_api_key
NOWPAYMENTS_IPN_SECRET=your_ipn_secret    # 可选
NOWPAYMENTS_API_URL=https://api.nowpayments.io/v1
NOWPAYMENTS_IPN_URL=https://aiflowhub.ai/api/payment/webhook
NOWPAYMENTS_SUCCESS_URL=https://aiflowhub.ai/recharge/success
NOWPAYMENTS_CANCEL_URL=https://aiflowhub.ai/recharge
```
