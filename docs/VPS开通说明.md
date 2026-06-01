# Hetzner VPS 开通说明

## 选购

1. 打开 https://www.hetzner.com/cloud
2. 选 **CX22** — 2 vCPU / 4 GB RAM / 40 GB NVMe / 20 TB 流量
3. 地区选 **Frankfurt (FRA1)** — 欧洲中心，延迟最优
4. 操作系统选 **Ubuntu 24.04 LTS**
5. SSH Key 建议上传（或选密码）

## 价格

- **€4.35/月**（约 $4.70）
- 按小时计费，随时可删

## 开通后需要的信息

服务器开通后把以下信息发我：
1. **IPv4 地址**
2. **SSH 登录方式**（key 或密码）
3. **root 密码**（如果选的密码登录）

## 推荐操作（开通后我来做）

- Docker + Docker Compose 安装
- 防火墙配置（只开 22/80/443）
- 域名 aiflowhub.ai DNS → VPS IP
- Nginx + Let's Encrypt SSL
- 项目部署 + 健康检查

Hetzner 欧洲客户更信任

如果你以后做官网：

可以写：

> Hosted in Germany

或者：

> EU Infrastructure

这对：

- 德国
- 法国
- 东欧

用户是加分项。