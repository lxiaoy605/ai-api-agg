# BACKUP-DONE.md — T4.2 自动备份脚本完成报告

> 日期：2026-05-28
> 执行者：Claude Code
> 阶段：运维与验证（阶段 4）

---

## 一、文件清单

| 文件 | 说明 |
|------|------|
| `scripts/backup.sh` | 主备份脚本 |
| `scripts/restore.sh` | 恢复脚本 |
| `scripts/backup.service` | systemd 服务定义 |
| `scripts/backup.timer` | systemd 定时器（每天 3:00） |

---

## 二、使用方法

### 手动备份

```bash
cd /mnt/d/WSL/openclawWorkspace/workspace/projects/ai-api-agg
bash scripts/backup.sh
```

备份文件生成在 `backups/` 目录，格式：`backup-2026-05-28-143022.tar.gz`

### 查看备份

```bash
ls -lh backups/
```

每个备份包含：数据库文件 + 配置文件 + Docker 配置。

### 恢复备份

```bash
# 交互模式（列出备份，选择恢复）
bash scripts/restore.sh

# 直接指定备份文件
bash scripts/restore.sh backup-2026-05-28-143022.tar.gz
```

恢复前会自动备份当前状态到 `backups/pre-restore-safety/`，防止误操作。

### 启用 systemd 定时备份

```bash
# 复制 service 和 timer 到 systemd 目录
sudo cp scripts/backup.service /etc/systemd/system/
sudo cp scripts/backup.timer /etc/systemd/system/

# 启用并启动定时器
sudo systemctl daemon-reload
sudo systemctl enable backup.timer
sudo systemctl start backup.timer

# 查看定时器状态
sudo systemctl status backup.timer

# 手动触发一次备份（测试）
sudo systemctl start backup.service
```

---

## 三、异地备份配置（可选）

### rsync 方式

```bash
export BACKUP_RSYNC_DEST="user@backup-server:/path/to/backups/"
bash scripts/backup.sh
```

修改 `backup.service` 中的 `Environment=` 行来持久化配置。

### scp 方式

```bash
export BACKUP_SCP_DEST="user@backup-server:/path/to/backups/"
bash scripts/backup.sh
```

两种方式可同时配置，异地备份失败不影响本地备份。

---

## 四、安全特性

- **恢复前安全备份**：执行 restore.sh 时自动备份当前状态，防止误操作覆盖
- **异地备份容错**：rsync/scp 失败仅记录错误，不中断本地备份流程
- **WAL Checkpoint**：备份前执行 `PRAGMA wal_checkpoint(TRUNCATE)` 确保数据一致性
- **systemd 安全限制**：`NoNewPrivileges=yes` + `PrivateTmp=yes`
- **文件不存在容错**：数据库或配置文件不存在时跳过并记录警告，不中断流程

---

## 五、备份内容

| 内容 | 路径 | 说明 |
|------|------|------|
| SQLite 数据库 | `backend/data/app.db` | 含 WAL/SHM 文件 |
| 应用配置 | `config/config.yaml` | 主配置文件 |
| 配置模板 | `config/config.example.yaml` | 配置示例 |
| Docker 环境变量 | `docker/.env` | 环境变量 |
| Docker Compose | `docker/docker-compose.yml` | 编排文件 |

---

## 六、日志

所有操作记录到 `backups/backup.log`，包括：
- 备份/恢复开始和结束时间
- WAL checkpoint 状态
- 每个文件的备份状态
- 旧文件清理记录
- 异地备份结果
- 错误和警告信息
