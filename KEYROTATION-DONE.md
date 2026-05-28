# KEYROTATION-DONE.md — API Key 轮换系统完成记录

> 完成日期：2026-05-28
> 对应章节：MASTER-PLAN 5.2
> 状态：✅ 已完成

## 产出清单

| 文件 | 说明 | 大小 |
|------|------|------|
| `scripts/rotate-channel-key.sh` | Key 轮换核心脚本（手动 + 自动双模式） | ~18 KB |
| `scripts/key-rotation.timer` | systemd 定时器（每 90 天自动触发） | 0.5 KB |
| `scripts/key-rotation.service` | systemd 服务单元 | 0.8 KB |
| `channels/CHANNELS-DONE.md` | 已追加 Key 轮换说明 | — |

## 轮换流程

```
1. 读取旧渠道配置 → 备份到 logs/channel_*_backup_*.json
2. 创建新渠道（相同配置 + 新 Key + 权重=0）
   ├─ 失败 → rollback（退出）
3. 健康检查新渠道（最多 3 次重试，间隔 10s）
   ├─ 失败 → rollback（删除临时渠道）
4. 逐步提权（0 → 1 → 2 → 目标权重，每步等 30s）
   ├─ 失败 → rollback
5. 观察窗口 5 分钟（每 60s 健康检查）
   ├─ 失败 → rollback
6. 旧渠道权重 → 0
7. 最终观察 5 分钟（每 60s 健康检查）
   ├─ 失败 → 恢复旧渠道权重 + rollback
8. 删除旧渠道 → 重命名新渠道（去掉 -new 后缀）
```

## 命令行接口

| 参数 | 说明 |
|------|------|
| `--channel-id N` | 要轮换的旧渠道 ID |
| `--channel-name NAME` | 渠道名称（如 "DeepSeek"）|
| `--new-key "sk-xxx"` | 新的 API Key |
| `--target-weight N` | 目标权重（默认 3）|
| `--dry-run` | 预演模式，仅检查不执行 |
| `--auto` | 自动模式：从 docker/.env 读取 Key，自动扫描所有渠道 |
| `--status` | 显示当前轮换状态 |

## systemd 定时器

```bash
# 安装
sudo cp scripts/key-rotation.service /etc/systemd/system/
sudo cp scripts/key-rotation.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now key-rotation.timer

# 查看状态
sudo systemctl status key-rotation.timer
sudo systemctl list-timers | grep key-rotation

# 手动触发一次
sudo systemctl start key-rotation.service

# 查看日志
sudo journalctl -u key-rotation.service -f
```

## 安全机制

| 机制 | 说明 |
|------|------|
| **幂等性** | 相同 Key 不重复轮换；autoskip 未变化的渠道 |
| **失败回滚** | 任何阶段失败 → 自动删除临时渠道，恢复旧渠道权重 |
| **灰度提权** | 权重分步提升（0→1→2→target），非一次性切换 |
| **双观察窗口** | 新渠道上线 5min + 旧渠道下线 5min，健康检查失败立即回滚 |
| **Telegram 通知** | 新渠道上线 / 旧渠道下线 / 完成 / 失败回滚 都会通知 |
| **日志审计** | 全流程写入 `logs/key-rotation.log` |
| **配置备份** | 旧渠道完整配置保存到 `logs/channel_*_backup_*.json` |
| **状态追踪** | `logs/key-rotation.state` 记录每次轮换时间 + Key 哈希 |

## 操作场景

### 日常轮换

```bash
# 1. 更新 docker/.env 中的 API Key
vim docker/.env  # 修改 DEEPSEEK_API_KEY=sk-new-key

# 2. 执行轮换
./scripts/rotate-channel-key.sh --channel-name "DeepSeek" --new-key "sk-new-key"

# 3. 验证
./scripts/rotate-channel-key.sh --status
```

### 紧急轮换（Key 泄露）

```bash
# 1. 立即下线旧渠道（权重 → 0）
# 可通过 OneAPI 面板手动操作，或：
./scripts/failover.sh --reset-channel "DeepSeek"  # 恢复默认权重

# 2. 生成新 Key 并轮换
./scripts/rotate-channel-key.sh --channel-id 1 --new-key "sk-emergency-key"
```

### 自动轮换

```bash
# 1. 在厂商后台生成新 Key
# 2. 更新 docker/.env 中的新 Key
# 3. 运行自动模式（或在定时器触发时自动执行）
./scripts/rotate-channel-key.sh --auto
```
