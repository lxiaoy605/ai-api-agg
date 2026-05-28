# Telegram Bot 告警配置指南

> ai-api-agg 余额监控脚本 (balance-monitor.py) 的 Telegram 通知配置

## 1. 获取 Bot Token

### 1.1 创建 Bot

1. 在 Telegram 搜索 `@BotFather`（带蓝色认证勾的官方账号）
2. 发送命令 `/newbot`
3. 输入 Bot 名称，例如：`AI API 余额监控`
4. 输入 Bot 用户名，必须以 `bot` 结尾，例如：`ai_api_balance_bot`
5. BotFather 会返回一段消息，其中包含 **Bot Token**，类似：
   ```
   1234567890:AAHxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   ```

### 1.2 已有 Bot

如果已有 Bot（如 `@Xiao_friend_bot`），在 BotFather 发送 `/mybots` → 选择 Bot → `API Token` 即可查看或重新生成。

## 2. 获取 Chat ID

Chat ID 是接收告警消息的 Telegram 用户/群组/频道的唯一标识。

### 方法一：使用 @getidsbot（推荐）

1. 搜索 `@getidsbot`
2. 发送 `/start`
3. Bot 会直接回复你的 Chat ID（纯数字，如 `123456789`）

### 方法二：通过 API 查询

1. 先给刚创建的 Bot 发送一条任意消息（如 `hello`）
2. 浏览器访问（替换 YOUR_BOT_TOKEN）：
   ```
   https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates
   ```
3. 在返回的 JSON 中找到 `"chat":{"id":123456789}`，其中 `123456789` 就是 Chat ID

### 方法三：群组/频道告警

如果想将告警发送到群组：

1. 创建群组，将 Bot 拉入群组
2. 在群组中发送一条消息
3. 访问 `https://api.telegram.org/bot<TOKEN>/getUpdates`
4. 找到 `"chat":{"id":-123456789}` （群组 Chat ID 是负数）

## 3. 配置环境变量

### 3.1 写入 docker/.env

编辑 `docker/.env` 文件（从 `.env.example` 复制）：

```bash
# Telegram Bot 告警通知
TELEGRAM_BOT_TOKEN=8812183039:AAHOB6OkhQVrSQy40ijeE_GHwoqz-FlELK8
TELEGRAM_CHAT_ID=123456789
```

### 3.2 写入厂商 API Key

```bash
# 厂商 API Key（用于余额查询）
DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ZHIPU_API_KEY=8296db62bbd3491094c96d40a61bc0cf.l1ROUTvGXd4WHzFl
MIMO_API_KEY=sk-sk0fq36gp0av5l3eqnmcntaaehhsnjeldqm2o4x1m6oka1dg
```

## 4. 测试告警

### 4.1 手动触发测试

```bash
# 测试脚本是否可正常运行
cd /mnt/d/WSL/openclawWorkspace/workspace/projects/ai-api-agg
python3 scripts/balance-monitor.py

# 仅输出 JSON（不发送 Telegram）
python3 scripts/balance-monitor.py --json

# 跳过 Telegram 通知
python3 scripts/balance-monitor.py --no-telegram

# 仅检查单个厂商
python3 scripts/balance-monitor.py --vendor deepseek
```

### 4.2 发送测试消息（验证 Telegram 连通性）

```bash
# 使用 curl 直接测试 Telegram Bot
curl -X POST "https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/sendMessage" \
  -H "Content-Type: application/json" \
  -d '{"chat_id":"<YOUR_CHAT_ID>","text":"✅ 余额监控告警测试 — Bot 连通性正常"}'
```

### 4.3 安装 systemd 定时器

```bash
# 复制 systemd 文件
sudo cp scripts/balance-monitor.service /etc/systemd/system/
sudo cp scripts/balance-monitor.timer /etc/systemd/system/

# 重载配置
sudo systemctl daemon-reload

# 启用并启动定时器
sudo systemctl enable balance-monitor.timer
sudo systemctl start balance-monitor.timer

# 查看状态
sudo systemctl status balance-monitor.timer
sudo systemctl status balance-monitor.service

# 手动触发一次（测试用）
sudo systemctl start balance-monitor.service

# 查看日志
sudo journalctl -u balance-monitor.service -f
```

## 5. 告警消息格式

正常情况下不会收到消息。当余额低于阈值时会收到：

### 预警（余额 < $5）

```
⚠️ DeepSeek: $4.50 — WARNING
⚠️ Z.ai(智谱): $3.20 — WARNING
```

### 紧急（余额 < $2）

```
🚨 DeepSeek: $1.50 — CRITICAL
```

### 混合告警

```
⚠️ DeepSeek: $4.50 — WARNING
🚨 Z.ai(智谱): $1.20 — CRITICAL
```

## 6. 故障排查

| 现象 | 原因 | 解决方案 |
|------|------|---------|
| Telegram 无消息 | Bot Token 或 Chat ID 错误 | 重新获取并在 .env 中更新 |
| Telegram 无消息 | 未给 Bot 发过消息 | 给 Bot 发送 `/start` 后再试 |
| 余额查询失败 | API Key 过期 | 登录厂商 Dashboard 更新 Key |
| 网络超时 | VPS 到厂商 API 不通 | 检查防火墙/DNS，或增加超时时间 |
| systemd timer 未执行 | timer 未 enable | `sudo systemctl enable balance-monitor.timer` |
| MiMo 始终 unsupported | MiMo 未公开余额 API | 正常现象，手动在 Dashboard 查看 |
