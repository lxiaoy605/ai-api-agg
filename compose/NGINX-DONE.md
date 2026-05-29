# T2.4 — Nginx 反代 + SSL 自动配置（完成）

> 任务：TASKS.md T2.4
> 完成日期：2026-05-28
> 目标 SSL 评级：SSL Labs A+

---

## 改动清单

### 新建文件

| 文件 | 说明 |
|------|------|
| `nginx/conf.d/https.conf.template` | HTTPS 站点模板（`${DOMAIN_NAME}` 由 entrypoint envsubst 替换） |
| `nginx/docker-entrypoint.sh` | 容器入口脚本（envsubst 处理模板 + DH 生成 + nginx 启动） |
| `ssl-setup.sh` | 宿主机 Certbot 自动签发/续期脚本（webroot + cron） |

### 修改文件

| 文件 | 变更 |
|------|------|
| `nginx/nginx.conf` | 注释说明 conf.d 加载机制 |
| `nginx/conf.d/http.conf` | 无变更（HTTP-01 验证 + HTTPS 重定向） |
| `docker-compose.yml` | Nginx 服务完善（entrypoint、env_file、SSL 卷挂载、nginx_ssl_data） |
| `.env.example` | 补充 DOMAIN_NAME、SSL_EMAIL、SSL_STAGING、NGINX_CONTAINER |

---

## 架构

```
用户浏览器
    │
    ▼
┌──────────────────────────────────────────────────┐
│  Nginx (ai-api-agg-nginx) :80 / :443             │
│                                                   │
│  HTTP (80)  → 301 → HTTPS (443)                  │
│  HTTPS (443):                                     │
│    /               → frontend:3000 (Next.js)      │
│    /_next/static/* → frontend:3000 (缓存 1 年)     │
│    /static/*       → frontend:3000 (缓存 7 天)     │
│    /v1/*           → oneapi:3000  (模型网关+CORS) │
│    /api/auth/*     → backend:8080 (严格限流 5r/s) │
│    /api/stripe/*   → backend:8080 (Webhook不限流) │
│    /api/*          → backend:8080 (管理 API)      │
│    /health         → 200 OK                       │
└──────────────────────────────────────────────────┘
         │              │              │
    ┌────▼────┐   ┌────▼────┐   ┌────▼────┐
    │ OneAPI  │   │ Backend │   │Frontend │
    │ :3000   │   │ :8080   │   │ :3000   │
    └─────────┘   └─────────┘   └─────────┘
```

## 启动流程

```
docker compose up -d
    │
    ▼
docker-entrypoint.sh
    ├── 1. envsubst 处理 https.conf.template → https.conf
    ├── 2. 检查 SSL 证书（/etc/letsencrypt/live/）
    ├── 3. 生成 DH 参数（如果不存在，约 30-60s，仅首次）
    ├── 4. nginx -t 验证配置
    └── 5. 启动 nginx
         │
         ├── HTTP (80) → 始终可用（serve acme + redirect）
         └── HTTPS (443) → 需要 SSL 证书（运行 ssl-setup.sh 后可用）
```

## 安全配置

| 安全措施 | 实现 |
|---------|------|
| HSTS | `max-age=63072000; includeSubDomains; preload`（仅 HTTPS） |
| X-Frame-Options | `DENY` |
| X-Content-Type-Options | `nosniff` |
| X-XSS-Protection | `1; mode=block` |
| Referrer-Policy | `strict-origin-when-cross-origin` |
| CSP | `/` 页面: `default-src 'self'; frame-src 'none'; object-src 'none'` |
| Permissions-Policy | 禁用 camera/microphone/geolocation/payment/usb/display-capture |
| CORS | `/v1/*` 路径允许任意来源（API 端点需要） |
| TLS | 仅 TLSv1.2 + TLSv1.3，Mozilla Intermediate 密码套件 |
| OCSP Stapling | 已启用 |
| ECDH 曲线 | X25519:secp384r1:prime256v1 |
| DH 参数 | 2048-bit（docker-entrypoint.sh 首次自动生成） |
| 版本隐藏 | `server_tokens off` |
| 限流 | API 100r/s + burst 200, Auth 5r/s + burst 10, 通用 30r/s + burst 50 |
| 连接限制 | 每 IP 最多 20 并发连接 |
| 隐藏文件 | `location ~ /\.` 拒绝访问 |

## 部署步骤

### 1. 准备环境变量

```bash
cd docker/
cp .env.example .env
# 编辑 .env，填入实际值：
#   DOMAIN_NAME=api.your-domain.com
#   SSL_EMAIL=admin@your-domain.com
```

### 2. 创建必要目录并启动

```bash
# 宿主机创建 Certbot webroot 和 SSL 目录
sudo mkdir -p /var/www/certbot /etc/letsencrypt

# 启动服务（仅 HTTP）
docker compose -f docker/docker-compose.yml up -d
```

### 3. 签发 SSL 证书

```bash
# 首次签发（建议先用 staging 测试）
sudo SSL_STAGING=1 DOMAIN_NAME=api.example.com SSL_EMAIL=admin@example.com ./docker/ssl-setup.sh

# 确认无误后正式签发
sudo DOMAIN_NAME=api.example.com SSL_EMAIL=admin@example.com ./docker/ssl-setup.sh
```

脚本自动执行：
1. 安装 certbot（如未安装）
2. 准备 HTTP-01 webroot 验证目录
3. 通过 certbot webroot 模式签发 Let's Encrypt 证书
4. 配置每天 03:23 + 15:23 自动续期 cron
5. 验证 HTTPS 可访问性
6. 验证 HTTP → HTTPS 重定向

### 4. 验证部署

```bash
# 验证重定向
curl -I http://your-domain.com
# → 301 Location: https://your-domain.com/

# 验证 HTTPS
curl -I https://your-domain.com/health
# → 200 OK

# 查看证书状态
sudo ./docker/ssl-setup.sh --status

# SSL Labs 检测
# https://www.ssllabs.com/ssltest/analyze.html?d=your-domain.com
```

## 手动操作

### 查看证书信息

```bash
sudo certbot certificates
sudo ./docker/ssl-setup.sh --status
```

### 手动续期

```bash
sudo ./docker/ssl-setup.sh --renew
```

### 模拟续期（不实际签发）

```bash
sudo certbot renew --dry-run
```

### 重新配置自动续期

```bash
sudo ./docker/ssl-setup.sh --setup-cron
```

### 启用后端/前端服务

1. 在 `docker-compose.yml` 中取消注释 `backend` 和 `frontend` 服务块
2. 确保 `backend_upstream` 和 `frontend_upstream` 已在 `nginx.conf` 中定义（已预配置）
3. `docker compose -f docker/docker-compose.yml up -d`

### 切换前端模式（反代 vs 静态文件）

编辑 `conf.d/https.conf.template` 的 `/` location 块，切换代理目标。

---

## 安全检测清单

- [ ] SSL Labs 评级达到 A+（https://ssllabs.com）
- [ ] HTTP 自动 301 到 HTTPS
- [ ] HSTS 头正确下发（仅 HTTPS）
- [ ] 安全头全部存在且值正确
- [ ] 隐藏文件（`/.git` 等）被拒绝访问
- [ ] Nginx 版本号不暴露
- [ ] API 限流生效（ab 压测验证）
- [ ] CORS 头正确（`/v1/*` 允许跨域）
- [ ] 静态资源缓存头正确（`/_next/static/*` immutable 1y）
