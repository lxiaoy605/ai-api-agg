# Keepalived VIP 高可用 — 部署就绪说明

> 状态: **配置已准备，等待第二台 VPS**

## 何时启用

当前环境只有 **1 台 VPS**，Keepalived 需要 **2 台 VPS 组成 VRRP 集群**才能工作。以下场景出现时部署:

| 触发条件 | 说明 |
|---------|------|
| 新增第二台 VPS | 与当前 VPS 同 VPC/子网，共享虚拟 IP |
| HAProxy 单点故障风险 | 当前 HAProxy 单实例，无故障转移 |
| 正式生产上线 | 需要 SLA 保障（99.9%+） |

---

## 工作原理

```
          客户端
            │
     ┌──────▼──────┐
     │  虚拟 IP     │  ← Keepalived 管理的漂移 IP
     │  10.0.0.100 │
     └──────┬──────┘
            │
   ┌────────┼────────┐
   ▼                 ▼
┌──────────┐    ┌──────────┐
│  VPS #1  │    │  VPS #2  │
│  MASTER  │◄──►│  BACKUP  │  VRRP 心跳
│ priority │    │ priority │
│   100    │    │    50    │
└────┬─────┘    └────┬─────┘
     │               │
  HAProxy         HAProxy
     │               │
  OneAPI          OneAPI
  Blue/Green      Blue/Green
```

- **正常状态**: Master 持有虚拟 IP，所有流量走 VPS #1
- **故障转移**: Master HAProxy 宕机 → VIP 自动漂移到 Backup → VPS #2 接管流量
- **恢复**: Master 恢复后，VIP 自动回到 VPS #1（需配置抢占）

---

## 部署步骤

### 1. 准备两台 VPS

确保两台 VPS:
- 在同一 VPC/子网内（可共享虚拟 IP）
- 已安装 Docker 并运行 HAProxy 容器
- 网络互通（VRRP 协议需要组播或单播通信）

### 2. 配置环境变量

在两台 VPS 的 `docker/.env` 中添加:

```bash
# Keepalived VIP 高可用
KEEPALIVED_VIP=10.0.0.100/24
KEEPALIVED_ROLE=MASTER    # 或 BACKUP
KEEPALIVED_INTERFACE=eth0 # 网卡接口（可选，自动检测）
```

> **重要**: 两台机器的 `KEEPALIVED_VIP` 必须相同，`KEEPALIVED_ROLE` 必须不同。

### 3. VPS #1 (Master) 部署

```bash
sudo KEEPALIVED_VIP=10.0.0.100/24 KEEPALIVED_ROLE=MASTER ./scripts/setup-keepalived.sh
```

### 4. VPS #2 (Backup) 部署

```bash
sudo KEEPALIVED_VIP=10.0.0.100/24 KEEPALIVED_ROLE=BACKUP ./scripts/setup-keepalived.sh
```

### 5. 更新 DNS/Nginx

将域名 A 记录指向虚拟 IP (10.0.0.100)，或者更新上游负载均衡器配置。

---

## 测试流程

### 1. 验证 VIP 绑定

```bash
# 在 Master 上应看到 VIP
ip addr show | grep 10.0.0.100

# 在 Backup 上应看不到 VIP
ssh backup "ip addr show | grep 10.0.0.100"  # 应无输出
```

### 2. 验证 VRRP 状态

```bash
# Master
systemctl status keepalived
journalctl -u keepalived | grep -i "VRRP\|state"

# Backup
ssh backup "journalctl -u keepalived | grep -i 'VRRP\|state'"
```

### 3. 模拟故障转移

```bash
# 在 Master 上停止 HAProxy 或 keepalived
sudo systemctl stop keepalived

# 检查 Backup 是否接管 VIP
ssh backup "ip addr show | grep 10.0.0.100"  # 应能看到 VIP

# 检查 Telegram 通知是否收到故障转移告警
```

### 4. 模拟恢复

```bash
# 重新启动 Master
sudo systemctl start keepalived

# 检查 VIP 是否漂回 Master
ip addr show | grep 10.0.0.100  # 应能看到 VIP
```

### 5. 端到端测试

```bash
# 通过虚拟 IP 测试 API（HAProxy 端口 8080）
curl -s http://10.0.0.100:8080/health

# 在故障转移期间持续测试（应无明显中断）
while true; do
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://10.0.0.100:8080/api/status
  sleep 0.2
done
```

---

## 文件清单

| 文件 | 说明 |
|------|------|
| `docker/keepalived/keepalived.conf` | Keepalived 配置模板（含占位符） |
| `scripts/setup-keepalived.sh` | 一键部署脚本 |
| `/usr/local/bin/check-haproxy.sh` | HAProxy 健康检查脚本（部署时生成） |
| `/usr/local/bin/keepalived-notify.sh` | 状态转换通知脚本（部署时生成） |
| `KEEPALIVED-READY.md` | 本文件 |

---

## 注意事项

- **云服务器限制**: 部分云厂商（AWS、阿里云）不支持 VRRP 组播，需改用单播模式或使用云商提供的浮动 IP 服务
- **安全组**: 确保 VRRP 协议（IP 协议号 112）在安全组/防火墙中放行
- **通知**: 故障转移时自动通过 `ops-notify.sh` 发送 Telegram 告警
- **抢占模式**: 当前配置 `nopreempt`（不抢占），Master 恢复后不会自动夺回 VIP，避免不必要漂移
