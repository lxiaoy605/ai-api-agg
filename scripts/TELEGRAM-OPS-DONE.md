# Telegram 运维通知通道完成文档

> 完成日期：2026-05-28
> 对应章节：MASTER-PLAN.md 第 8 章（AI 自动运维 → 轻量级 Telegram Bot 替代方案）

## 背景

原 MASTER-PLAN 第 8 章的 AI 运维引擎（异常检测/自愈/成本优化）成本太高，改为轻量级 Telegram Bot 通知方案。所有运维事件统一走 Telegram Bot 通道，分级通知，桥可接收转发事件主动跟进。

## 产出清单

| 文件 | 说明 | 状态 |
|------|------|:---:|
| `scripts/ops-notify.sh` | 统一运维通知脚本（核心） | ✅ |
| `scripts/ops-daily-report.sh` | 每日运维摘要脚本 | ✅ |
| `scripts/bridge-webhook.sh` | 桥（AI 助手）监听通道 | ✅ |
| `scripts/ops-daily-report.service` | 每日报告 systemd 服务 | ✅ |
| `scripts/ops-daily-report.timer` | 每日报告 systemd 定时器 | ✅ |
| `scripts/bridge-webhook.service` | 桥轮询 systemd 服务 | ✅ |
| `scripts/bridge-webhook.timer` | 桥轮询 systemd 定时器 | ✅ |
| `docker/.env.example` | 环境变量模板（新增 TELEGRAM_BRIDGE_CHAT_ID） | ✅ |
| `scripts/TELEGRAM-OPS-DONE.md` | 本文件 | ✅ |

## 设计理念

```
所有运维事件 → ops-notify.sh → 分级推送
                                ├── critical: 即时推送 + 🔔
                                ├── warning:  即时推送 + 🔕
                                └── info:     静默记录 → 每日汇总推送
                                         ↓
                                ops-notify.log (所有事件)
                                         ↓
                              bridge-webhook.sh (桥事件轮询)
```

## ops-notify.sh 接口

```bash
# 基本用法
ops-notify.sh --level critical|warning|info \
              --title "事件标题" \
              --message "事件详情" \
              [--channel bridge] \
              [--silent]

# 示例
ops-notify.sh --level critical --title "渠道故障" \
  --message "DeepSeek 连续 3 次健康检查失败" --channel bridge
ops-notify.sh --level info --title "备份完成" \
  --message "每日全量备份完成，大小 2.3MB"
```

## 通知分级规则

| 级别 | 事件 | 推送时间 | 声音 |
|------|------|------|:--:|
| critical | 渠道连续故障、余额<$2、备份超24h、支付对账差异 | 即时 | 🔔 |
| warning | 余额<$5、渠道单次故障、备份超12h、蓝绿切换 | 即时(静默) | 🔕 |
| info | 余额<$10、备份成功、日常统计 | 汇总(daily) | ❌ |

## 已更新的现有脚本

| 脚本 | 原通知方式 | 更新方式 |
|------|-----------|---------|
| `balance-monitor.py` | 内置 `send_telegram()` | 调用 `ops-notify.sh` via subprocess |
| `healthcheck.sh` | `send_telegram()` | 替换为 `send_notify()` 调用 ops-notify.sh |
| `failover.sh` | `send_telegram()` | 替换为 `send_notify()` 调用 ops-notify.sh |
| `backup.sh` | 无 | 新增 `notify_backup()` 调用 ops-notify.sh |
| `restore.sh` | 无 | 新增 `notify_restore()` 调用 ops-notify.sh |
| `reconcile-payments.sh` | `send_telegram()` | 替换为 `send_notify()` 调用 ops-notify.sh |
| `bluegreen-switch.sh` | `send_telegram()` | 替换为 `send_notify()` 调用 ops-notify.sh |
| `rollback.sh` | `send_telegram()` | 替换为 `send_notify()` 调用 ops-notify.sh |
| `rotate-channel-key.sh` | `send_telegram()` | 替换为兼容包装调用 ops-notify.sh |
| `backup-health.sh` | `tg_notify()` | 替换为兼容包装调用 ops-notify.sh |
| `dr-failover.sh` | `tg_notify()` | 替换为兼容包装调用 ops-notify.sh |

## 脚本目录结构

```
scripts/
├── ops-notify.sh              ← 统一通知脚本（核心）
├── ops-daily-report.sh        ← 每日运维摘要
├── bridge-webhook.sh           ← 桥监听通道
├── ops-daily-report.service   ← systemd 每日报告服务
├── ops-daily-report.timer     ← systemd 每日报告定时器
├── bridge-webhook.service     ← systemd 桥轮询服务
├── bridge-webhook.timer       ← systemd 桥轮询定时器
├── balance-monitor.py         ← [已更新] 余额监控
├── healthcheck.sh             ← [已更新] 健康检查
├── failover.sh                ← [已更新] 故障切换
├── backup.sh                  ← [已更新] 数据库备份
├── restore.sh                 ← [已更新] 备份恢复
├── reconcile-payments.sh      ← [已更新] 支付对账
├── bluegreen-switch.sh        ← [已更新] 蓝绿切换
├── rollback.sh                ← [已更新] 三层回滚
├── rotate-channel-key.sh      ← [已更新] Key 轮换
├── backup-health.sh           ← [已更新] 备份健康检查
├── dr-failover.sh             ← [已更新] 灾难恢复
├── TELEGRAM-SETUP.md          ← Telegram Bot 配置指南
├── TELEGRAM-OPS-DONE.md       ← 本文件
├── BALANCE-DONE.md            ← 余额监控完成文档
├── BACKUP-DONE.md             ← 备份完成文档
└── HEALTH-DONE.md             ← 健康检查完成文档
```

## 环境变量

在 `docker/.env` 中需配置：

```bash
# Telegram Bot（已有 @Xiao_friend_bot）
TELEGRAM_BOT_TOKEN=8812183039:AAHOB6OkhQVrSQy40ijeE_GHwoqz-FlELK8

# 运维主频道 Chat ID（必填）
TELEGRAM_CHAT_ID=

# 桥（AI 助手）跟进频道 Chat ID（可选，用于 bridge-webhook.sh）
TELEGRAM_BRIDGE_CHAT_ID=
```

## 安装 systemd 定时器

```bash
# 每日运维摘要（每天早上 9:03）
sudo cp scripts/ops-daily-report.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now ops-daily-report.timer

# 桥事件轮询（每 10 分钟）
sudo cp scripts/bridge-webhook.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now bridge-webhook.timer

# 查看状态
systemctl status ops-daily-report.timer
systemctl status bridge-webhook.timer
```

## 日志文件

| 日志 | 路径 | 说明 |
|------|------|------|
| 运维通知日志 | `logs/ops-notify.log` | 所有通知事件记录 |
| 桥轮询日志 | `logs/bridge-webhook.log` | 桥事件推送记录 |
| 桥状态文件 | `logs/bridge-webhook.state` | 轮询游标位置 |

## 通知示例

### Critical（渠道故障）
```
🔴 渠道故障切换: DeepSeek
⏰ 2026-05-28 14:32:05

渠道 DeepSeek 连续失败 3 次，已自动切换。权重调为 0，流量已路由至其他渠道。请检查该渠道上游 API 是否正常。
```

### Warning（每日摘要）
```
📊 AI API 聚合平台 — 每日运维摘要
📅 2026-05-27

🏥 渠道健康
✅ DeepSeek: UP
✅ 智谱 Z.ai: UP
✅ 小米 MiMo: UP

💰 余额监控
OK=3 WARNING=0 CRITICAL=0 ERROR=0

💾 备份状态
全量备份完成: backup-full-2026-05-28-030003.tar.gz, 大小: 2.3M
```

## 待手动完成

1. **配置 TELEGRAM_CHAT_ID**：按 `scripts/TELEGRAM-SETUP.md` 步骤获取
2. **配置 TELEGRAM_BRIDGE_CHAT_ID**（可选）：创建桥专用频道/群组
3. **安装 systemd 定时器**：复制 service/timer 到 `/etc/systemd/system/`
4. **测试通知**：
   ```bash
   ./scripts/ops-notify.sh --level warning --title "测试通知" --message "Telegram 运维通知通道已就绪"
   ```

## 已知限制

- `info` 级别事件仅记录日志，不推送。通过 `ops-daily-report.sh` 每日汇总时展示
- 桥事件需要配置 `TELEGRAM_BRIDGE_CHAT_ID` 才能推送到独立频道
- `bridge-webhook.sh watch` 模式依赖 `tail -f`，需在后台持续运行
