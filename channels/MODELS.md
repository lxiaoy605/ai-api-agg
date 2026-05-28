# 模型目录与价格对比

> ai-api-agg 平台支持的模型列表，含输入/输出 token 价格对照
> 最后更新：2026-05-28

---

## 一、模型总览

| 模型 ID | 厂商 | 类型 | 上下文窗口 | 状态 |
|---------|------|------|:--------:|:----:|
| `deepseek-v4-flash` | DeepSeek | 对话 | 64K | 🟢 在线 |
| `deepseek-v4-pro` | DeepSeek | 推理 (CoT) | 64K | 🟢 在线 |
| `GLM-5.1` | 智谱 Z.ai | 对话 | 128K | 🟢 在线 |
| `GLM-5` | 智谱 Z.ai | 对话 | 128K | 🟢 在线 |
| `GLM-4.7-Flash` | 智谱 Z.ai | 对话 | 128K | 🟢 在线 (免费) |
| `MiMo-V2.5-Pro` | 小米 MiMo | 对话 | 128K | 🟢 在线 |
| `MiMo-V2-Pro` | 小米 MiMo | 对话 | 32K | 🟢 在线 |
| `MiMo-V2-Omni` | 小米 MiMo | 多模态 | 32K | 🟢 在线 |
| `MiMo-V2-Flash` | 小米 MiMo | 对话 | 32K | 🟢 在线 |

---

## 二、价格对比表

### 2.1 按量计费（USD / 百万 tokens）

| 模型 ID | 输入价格 | 输出价格 | 缓存命中 | 备注 |
|---------|:-------:|:--------:|:------:|------|
| `deepseek-v4-flash` | $0.27 | $1.10 | $0.07 | MVP 推荐，性价比最高 |
| `deepseek-v4-pro` | $0.55 | $2.19 | — | 推理模式，输出含 CoT token |
| `GLM-5.1` | $1.40 | $4.40 | — | 旗舰模型，MoE 架构 |
| `GLM-5` | $1.00 | $3.20 | — | 高性能，性价比之选 |
| `GLM-4.7-Flash` | **免费** | **免费** | — | 轻量模型，高并发场景 |

> **MiMo 定价说明：** 小米 MiMo 采用 Token Plan 订阅制（$6/月起），非按量计费模式。具体每 token 价格取决于所选 Plan 和用量。以下是参考估算：

| 模型 ID | 订阅计划 | 月费（起） | 估算单价 |
|---------|:------:|:--------:|:------:|
| `MiMo-V2.5-Pro` | Token Plan Pro | $12/月 | ~$0.50-1.00/1M |
| `MiMo-V2-Pro` | Token Plan Standard | $6/月 | ~$0.30-0.60/1M |
| `MiMo-V2-Flash` | Token Plan Lite | $6/月 | ~$0.10-0.30/1M |
| `MiMo-V2-Omni` | Token Plan Pro | $12/月 | ~$0.80-1.50/1M |

### 2.2 成本对比（以 1M tokens 输出为例）

```
深度求索 DeepSeek Flash  ████████░░░░░░░░░░░░  $1.10
深度求索 DeepSeek Pro    ████████████████░░░░  $2.19
智谱 GLM-5              ██████████████████████  $3.20
智谱 GLM-5.1            ██████████████████████████████  $4.40
智谱 GLM-4.7-Flash      ░░░░░░░░░░░░░░░░░░░░  免费
小米 MiMo V2-Flash      ██░░░░░░░░░░░░░░░░░░  ~$0.30
小米 MiMo V2-Pro        ████░░░░░░░░░░░░░░░░  ~$0.60
小米 MiMo V2.5-Pro      ████████░░░░░░░░░░░░  ~$1.00
```

---

## 三、推荐默认模型

### 3.1 按场景推荐

| 场景 | 首选模型 | 备选模型 | 理由 |
|------|---------|---------|------|
| **日常对话** | `deepseek-v4-flash` | `GLM-4.7-Flash` | 免费/低价，响应快 |
| **复杂推理** | `deepseek-v4-pro` | `MiMo-V2.5-Pro` | CoT 深度思考 |
| **代码生成** | `deepseek-v4-flash` | `MiMo-V2-Pro` | 代码能力强 |
| **高并发/低成本** | `GLM-4.7-Flash` | `MiMo-V2-Flash` | 免费 + 不限量 |
| **多模态** | `MiMo-V2-Omni` | — | 唯一支持多模态 |
| **长文本 (128K)** | `GLM-5.1` | `MiMo-V2.5-Pro` | 大上下文窗口 |

### 3.2 默认模型链（OneAPI 权重分配）

```
用户请求 ──→ OneAPI 加权轮询 (3:3:2)
                  │
        ┌─────────┼─────────┐
        ▼         ▼         ▼
    DeepSeek   智谱Z.ai   小米MiMo
    (权重3)    (权重3)    (权重2)
```

当某渠道故障时，OneAPI 自动将流量分配到其余健康渠道。

---

## 四、获取 API Key

### 4.1 各厂商注册地址

| 厂商 | 注册地址 | 最低充值 | 认证要求 |
|------|---------|:------:|------|
| DeepSeek | [platform.deepseek.com](https://platform.deepseek.com) | $0（免费500万tokens） | 仅邮箱 |
| 智谱 Z.ai | [z.ai](https://z.ai)（国际站） | $18（Coding Plan Lite） | 邮箱/Google |
| 小米 MiMo | [platform.xiaomimimo.com](https://platform.xiaomimimo.com) | $6（Token Plan） | 邮箱 |

### 4.2 Key 环境变量对应

```bash
# docker/.env 中配置
DEEPSEEK_API_KEY=sk-xxxxxxxx     # DeepSeek 平台 → API Keys
ZHIPU_ZAI_API_KEY=xxxxxxxx       # Z.ai → 个人设置 → API Key
MIMO_API_KEY=sk-xxxxxxxx         # MiMo 平台 → 开发者 → API Key
```

---

## 五、价格更新记录

| 日期 | 变更 |
|------|------|
| 2026-05-28 | 初始版本 — 3 厂商 9 模型 |
