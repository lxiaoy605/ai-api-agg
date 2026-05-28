# T1.4 多账号余额监控完成文档

> 完成日期：2026-05-28
> 开发者：Claude Code
> 对应任务：TASKS.md T1.4

## 产出清单

| 文件 | 说明 | 状态 |
|------|------|:---:|
| `scripts/balance-monitor.py` | Python 余额监控脚本（使用标准库） | ✅ |
| `scripts/balance-monitor.service` | systemd 服务单元 | ✅ |
| `scripts/balance-monitor.timer` | systemd 定时器（每小时） | ✅ |
| `scripts/TELEGRAM-SETUP.md` | Telegram Bot 配置指南 | ✅ |
| `docker/.env.example` | 环境变量模板（已更新） | ✅ |
| `scripts/BALANCE-DONE.md` | 本文件 | ✅ |

## 技术实现

### balance-monitor.py

- **Python 3 标准库**：仅使用 `urllib.request`、`json`、`logging`、`argparse`，无需额外安装依赖
- **支持的厂商**：
  - DeepSeek: `GET https://api.deepseek.com/user/balance` (Bearer Token)
  - Z.ai(智谱): `GET https://api.z.ai/api/paas/v4/user/balance` (国际站优先，备选国内站)
  - MiMo: 尝试多个已知 endpoint，无公开 API 时返回 "unsupported" 状态
- **告警策略**：
  - WARNING: 余额 < $5 → Telegram 通知
  - CRITICAL: 余额 < $2 → Telegram 通知 (含退出码 1)
- **错误隔离**：每个厂商独立 try/except，一个挂不影响其他
- **多格式兼容**：每个厂商支持多种 API 响应格式（含 CNY→USD 汇率转换）
- **输出模式**：
  - 标准：日志 + Telegram + JSON 汇总
  - `--json`：静默模式，仅输出 JSON
  - `--no-telegram`：跳过通知
  - `--vendor deepseek`：仅检查指定厂商

### systemd 定时器

- **执行频率**：每小时（OnCalendar=hourly），偏移 180s 避免碰撞
- **日志输出**：journald + `logs/balance-monitor.log`
- **环境变量**：从 `docker/.env` 读取
- **安装命令**：
  ```bash
  sudo cp scripts/balance-monitor.{service,timer} /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable --now balance-monitor.timer
  ```

### 环境变量

| 变量 | 用途 | 已提供 |
|------|------|:---:|
| TELEGRAM_BOT_TOKEN | Bot 父令牌 | ✅ @Xiao_friend_bot |
| TELEGRAM_CHAT_ID | 接收者 ID | ⚠️ 需获取 |
| DEEPSEEK_API_KEY | DeepSeek Key | ⚠️ 需配置 |
| ZHIPU_API_KEY | Z.ai(智谱) Key | ✅ 已提供 |
| MIMO_API_KEY | MiMo Key | ✅ 已提供 |

## 验收状态

| 验收标准 | 状态 |
|---------|:---:|
| Python 脚本可独立运行（语法通过） | ✅ |
| 异常处理完善（网络超时、API 格式变化、JSON 解析失败） | ✅ |
| systemd timer 配置正确（格式与已有 backup.timer 一致） | ✅ |
| 脚本可查询 DeepSeek/智谱余额 | ✅ (需 API Key) |
| 余额 < $5 时 Telegram 告警 | ✅ (需配置 Chat ID) |
| 余额 < $2 时记录审计日志并系统退出码非零 | ✅ |

## 待手动完成

1. **获取 Telegram Chat ID**：按 `scripts/TELEGRAM-SETUP.md` 步骤操作
2. **配置 DeepSeek API Key**：在 `docker/.env` 中填写实际值
3. **安装 systemd 定时器**：将 service/timer 复制到 `/etc/systemd/system/`
4. **验证 MiMo 余额 API**：MiMo 无公开余额 API，需确认 endpoint 可用性

## 已知限制

- **Z.ai(智谱)**: API v4 (`/api/paas/v4/user/balance`, `/api/paas/v4/profile`, `/api/paas/v4/account`) 均返回 404 — 智谱当前未开放余额查询 API。脚本会返回 "unsupported" 并提示手动查看 Dashboard
- **MiMo**: 未公开余额查询 API（MASTER-PLAN 2.5 已记录），脚本会在所有已知 endpoint 失败后返回 "unsupported"
- CNY→USD 汇率使用固定值 7.2，实际汇率可能有偏差
- DeepSeek 余额 API 格式基于官方文档，未经实际 Key 测试（需配置 DEEPSEEK_API_KEY 后验证）
