# Spaceship DNS 配置指南 — aiflowhub.ai

> 域名注册商：Spaceship (spaceship.com)
> 目标：将 aiflowhub.ai 指向服务器 IP，配置 SSL 证书所需的 DNS 解析

---

## 前置条件

- Spaceship 账号（已注册 aiflowhub.ai）
- 服务器公网 IP 地址
- Spaceship 控制台登录权限

---

## DNS 记录配置

### 1. 登录 Spaceship 控制台

1. 打开 https://www.spaceship.com/
2. 登录你的账号
3. 进入 **Domain List** → 找到 `aiflowhub.ai` → 点击 **Manage**

### 2. 进入 DNS 管理

1. 在域名管理页面，找到 **DNS** 或 **Advanced DNS** / **Name Servers** 区域
2. 确保使用 **Spaceship 默认 Name Server**（而非第三方 DNS）
   - 如果已使用 Cloudflare 等第三方 DNS，请在对应平台配置以下记录

### 3. 添加 DNS 记录

在 DNS 记录管理页面，添加以下记录：

#### 记录 1：根域名 A 记录（主）

| 字段 | 值 |
|------|-----|
| **Type** | A |
| **Host/Name** | @ |
| **Value/Points to** | `<你的服务器 IP>` |
| **TTL** | 3600 (或保持默认) |

#### 记录 2：WWW 子域名 CNAME 记录

| 字段 | 值 |
|------|-----|
| **Type** | CNAME |
| **Host/Name** | www |
| **Value/Points to** | aiflowhub.ai |
| **TTL** | 3600 (或保持默认) |

#### 可选：通配符 A 记录（如需要子域名）

| 字段 | 值 |
|------|-----|
| **Type** | A |
| **Host/Name** | * |
| **Value/Points to** | `<你的服务器 IP>` |
| **TTL** | 3600 |

> **注意**：通配符记录可能导致 Let's Encrypt 通配符证书需求（需 DNS-01 验证）。当前方案使用 HTTP-01 验证，只需要根域名解析即可。

---

## 配置后验证

### 等待 DNS 生效

DNS 修改后需要时间全球传播（通常 5-30 分钟，最长 48 小时）。

### 验证解析

```bash
# 方法 1：dig 查询（Linux/macOS）
dig +short aiflowhub.ai A
# 应返回你的服务器 IP

dig +short www.aiflowhub.ai
# 应返回 aiflowhub.ai 的 IP

# 方法 2：nslookup（Windows）
nslookup aiflowhub.ai

# 方法 3：在线工具
# https://dnschecker.org → 输入 aiflowhub.ai → 选择 A 记录
```

### 验证 HTTP 可访问

```bash
# DNS 生效后测试端口 80
curl -I http://aiflowhub.ai/health
# 应返回: HTTP/1.1 301 Moved Permanently (重定向到 HTTPS)
# 或: HTTP/1.1 200 OK
```

---

## DNS 配置确认后下一步

DNS 生效后，执行 SSL 证书签发：

```bash
cd /path/to/ai-api-agg/docker/

# 1. 启动服务（如未启动）
docker compose -f docker-compose.yml up -d

# 2. 测试模式签发（避免频率限制）
sudo bash ssl-setup-real.sh --staging

# 3. 正式签发
sudo bash ssl-setup-real.sh
```

---

## 故障排查

### DNS 不生效
- **检查 Name Server**：确认使用 Spaceship 默认 NS 或你配置的第三方 NS
- **TTL 等待**：旧 TTL 值过期后才能看到新记录
- **本地 DNS 缓存**：`sudo systemctl restart systemd-resolved` (Linux) 或 `ipconfig /flushdns` (Windows)
- **浏览器 DNS 缓存**：Chrome 访问 `chrome://net-internals/#dns` 清除

### 部分地域解析异常
- 使用 https://dnschecker.org 检查全球解析状态
- 部分 ISP 的 DNS 服务器更新较慢，通常在 1-2 小时内完成

### Spaceship 界面找不到 DNS 设置
- Spaceship 的 DNS 管理有时叫 **"Advanced DNS"** 或 **"DNS Records"**
- 如果域名使用了外部 Name Server（如 Cloudflare），Spaceship 的 DNS 设置会被禁用，需要到对应的 DNS 平台配置

### 服务器 IP 不确定
```bash
# 在服务器上运行
curl -s https://ifconfig.me
# 或
curl -s https://api.ipify.org
```

---

## 记录清单

| 记录类型 | 主机名 | 值 | TTL | 状态 |
|---------|--------|-----|-----|:--:|
| A | @ | 服务器 IP | 3600 | ⬜ |
| CNAME | www | aiflowhub.ai | 3600 | ⬜ |

> 配置完成后，在状态栏打勾确认。
