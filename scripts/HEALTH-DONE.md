# T1.3 完成记录 — 健康检查 + 故障自动切换

> 完成日期：2026-05-28
> 状态：✅ 已完成
> 域名：aiflowhub.ai

## 产出清单

| 文件 | 说明 | 大小 |
|------|------|------|
| `scripts/healthcheck.sh` | 多渠道健康检测脚本（完全重写） | ~8 KB |
| `scripts/failover.sh` | 故障自动切换引擎 | ~10 KB |
| `scripts/healthcheck.service` | systemd 服务配置 | ~700 B |
| `scripts/healthcheck.timer` | systemd 定时器（每 30s） | ~400 B |
| `docker/.env.example` | 已更新：添加 ONEAPI_DOMAIN + ZHIPU_ZAI_API_KEY 别名 | — |
| `scripts/balance-monitor.py` | 已更新：添加邮箱配置指南 | — |

## healthcheck.sh 功能

```
检测对象:
  1. DeepSeek    → https://api.deepseek.com/v1/models
  2. 智谱 Z.ai   → https://open.bigmodel.cn/api/paas/v4/models
  3. 小米 MiMo   → https://token-plan-sgp.xiaomimimo.com/v1/models
  4. OneAPI 内部  → http://localhost:3000/api/status
  5. 外部域名    → https://aiflowhub.ai/v1/models

特性:
  - 10 秒超时 + 2 次重试
  - 彩色输出（绿=OK，红=FAIL，黄=WARN）
  - 延迟测量 + 颜色编码（<1s 绿, <3s 黄, >3s 红）
  - 支持 --json 输出模式
  - 支持 --channel <name> 单渠道检测
  - 支持 --no-external 跳过外部检测
  - 日志写入 logs/healthcheck.log
  - 环境变量自动从 docker/.env 加载
```

### 用法

```bash
# 标准模式（文本输出 + 日志）
./scripts/healthcheck.sh

# 单渠道检测（供 failover.sh 调用）
./scripts/healthcheck.sh --channel "DeepSeek"

# 跳过外部域名检测
./scripts/healthcheck.sh --no-external

# 使用自定义配置
ONEAPI_URL=http://oneapi:3000 ONEAPI_DOMAIN=aiflowhub.ai ./scripts/healthcheck.sh
```

## failover.sh 功能

```
故障切换流程:
  1. 读取 logs/failover.state 状态文件
  2. 调用 healthcheck.sh --channel 检测每个渠道
  3. 连续失败 < 3 次 → 记录，继续观察
  4. 连续失败 >= 3 次 → 标记 DOWN，通过 OneAPI API 将权重调为 0
  5. DOWN 后恢复 → 自动还原原始权重，Telegram 通知
  6. 所有事件写入 logs/failover.log

状态文件: logs/failover.state
格式: channel_name|original_weight|consecutive_failures|status|last_update
```

### 用法

```bash
# 标准模式（检测 + 切换）
./scripts/failover.sh

# 模拟运行（不实际修改权重）
./scripts/failover.sh --dry-run

# 查看状态
./scripts/failover.sh --status

# 手动重置渠道
./scripts/failover.sh --reset-channel "DeepSeek"
```

## systemd timer 配置

```bash
# 安装（用户级 systemd）
mkdir -p ~/.config/systemd/user/
cp scripts/healthcheck.service ~/.config/systemd/user/
cp scripts/healthcheck.timer ~/.config/systemd/user/

# 启用定时器
systemctl --user daemon-reload
systemctl --user enable healthcheck.timer
systemctl --user start healthcheck.timer

# 查看状态
systemctl --user status healthcheck.timer
systemctl --user status healthcheck.service

# 查看日志
journalctl --user -u healthcheck.service -f
```

## 环境变量

| 变量 | 默认值 | 用途 |
|------|--------|------|
| `ONEAPI_URL` | `http://localhost:3000` | OneAPI 内部地址 |
| `ONEAPI_DOMAIN` | `aiflowhub.ai` | 外部探测域名 |
| `ONEAPI_ROOT_TOKEN` | — | OneAPI 管理员 Token（failover.sh 调整权重需要） |
| `DEEPSEEK_API_KEY` | — | DeepSeek API Key |
| `ZHIPU_ZAI_API_KEY` | `$ZHIPU_API_KEY`（回退） | 智谱 Z.ai API Key |
| `MIMO_API_KEY` | — | 小米 MiMo API Key |
| `TELEGRAM_BOT_TOKEN` | — | Telegram Bot Token (@Xiao_friend_bot) |
| `TELEGRAM_CHAT_ID` | — | Telegram Chat ID |
| `FAILOVER_THRESHOLD` | `3` | 连续失败次数阈值 |
| `HEALTHCHECK_TIMEOUT` | `10` | 单次检测超时（秒） |
| `HEALTHCHECK_RETRIES` | `2` | 最大重试次数 |

## Telegram 通知格式

**故障切换：**
```
🔴 *渠道故障切换通知*

渠道: *DeepSeek*
状态: UP → DOWN
连续失败: 3 次
权重: 已调为 0（流量已切换至其他渠道）
时间: 2026-05-28 15:30:00

⚠️ 请检查该渠道上游 API 是否正常
```

**恢复通知：**
```
🟢 *渠道恢复通知*

渠道: *DeepSeek*
状态: DOWN → UP
权重: 已恢复为 3
时间: 2026-05-28 15:35:00
```

## 邮箱配置指南（已更新到 balance-monitor.py）

多账号注册使用 Cloudflare Email Routing + `aiflowhub.ai` 域名：

| 厂商子邮箱 | 用途 |
|-----------|------|
| `deepseek@aiflowhub.ai` | DeepSeek 平台注册 |
| `zhipu@aiflowhub.ai` | 智谱 Z.ai 平台注册 |
| `mimo@aiflowhub.ai` | 小米 MiMo 平台注册 |

年费用：域名 ~$10/年（Spaceship），Email Routing $0。

## 关键设计决策

1. **直连检测 vs 通过 OneAPI 转发**：healthcheck.sh 直接检测上游 API，绕过 OneAPI 中间层，确保检测的是渠道真正可用性，而非 OneAPI 路由问题
2. **OneAPI `/v1/models` 聚合局限**：该端点返回所有活跃渠道的模型聚合列表，无法区分具体哪个渠道故障，因此采用直连上游的方式
3. **3 次连续失败阈值**：避免因网络抖动误触发切换，同时保证 30s 内响应故障（3 × 10s = 30s）
4. **OneAPI API 权重调整**：通过 `PUT /api/channel/:id` 设置 `weight=0` 实现流量摘除，保留渠道配置不删除，便于恢复
5. **状态持久化**：`logs/failover.state` 记录原始权重和连续失败次数，确保脚本幂等和服务重启后不丢失状态
6. **ZHIPU_ZAI_API_KEY 兼容**：优先读取 `ZHIPU_ZAI_API_KEY`，未设置时回退到 `ZHIPU_API_KEY`

## 验收标准对照

| 标准 | 状态 |
|------|:---:|
| healthcheck.sh 可独立运行，输出渠道健康状态汇总 | ✅ 5 项检测（3 渠道 + OneAPI + 外部域名） |
| failover.sh 检测到故障后能自动标记渠道 | ✅ 连续 3 次失败 → 权重设为 0 |
| systemd timer 配置正确 | ✅ 每 30s 执行 healthcheck.service |
| 彩色输出 | ✅ 绿/红/黄对应 OK/FAIL/WARN |
| Telegram 通知 | ✅ 故障切换 + 恢复双重通知 |
| 错误处理完整（DNS/SSL/超时） | ✅ curl 超时 + 重试 + 状态码匹配 |
| 幂等操作 | ✅ 状态文件防重复标记 + OneAPI API 可重复调用 |
