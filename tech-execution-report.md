# AI 模型 API 聚合平台 — 技术落地执行报告

**提交人：** 华（DeerFlow）  
**提交日期：** 2026-05-27  
**版本：** v4（替代 v3 网络故障中断版本）  
**状态：** 完整产出

---

## 0. 执行摘要

本报告基于 proposal-v2.md（精准需求方案）和 tech-memo.md（技术备忘），给出可直接执行的技术落地计划。核心架构：**OneAPI 开源网关 + Docker Compose + 8 家国内模型源**，部署在法兰克福/伊斯坦布尔 VPS，面向亚美尼亚周边开发者。

**关键约束回顾：**
- 单人团队，月运维 ≤ $50
- MVP 1 个月上线，3 个月验证
- 不做自建算力、不做模型研发、不做多语言 UI

---

## 1. 技术架构总览

```
┌─────────────────────────────────────────────────┐
│                   Nginx (反向代理)                │
│              SSL termination + 限流               │
└────────────────────┬────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────┐
│              OneAPI (核心网关)                     │
│  ┌─────────┐ ┌─────────┐ ┌──────────┐           │
│  │ 渠道管理 │ │ Key管理  │ │ 余额/计费 │           │
│  └─────────┘ └─────────┘ └──────────┘           │
│  ┌─────────────────────────────────────┐         │
│  │        OpenAI 兼容 API 层           │         │
│  └─────────────────────────────────────┘         │
└────────────────────┬────────────────────────────┘
                     │
    ┌────────┬───────┼───────┬────────┬───────────┐
    ▼        ▼       ▼       ▼        ▼           ▼
 阿里Qwen  小米MiMo  DeepSeek  字节豆包  智谱GLM  月暗Moonshot
    ▼        ▼
 零一Yi   腾讯混元
```

**技术栈：**
| 组件 | 选型 | 理由 |
|------|------|------|
| API 网关 | OneAPI (v0.6.x) | 开源、OpenAI 兼容、多渠道管理、社区活跃 |
| 容器化 | Docker Compose | 单机部署足够，运维简单 |
| 反向代理 | Nginx | SSL、限流、日志 |
| 数据库 | SQLite (OneAPI 内置) | 单机场景无需 MySQL |
| 监控 | OneAPI 内置 + 简单脚本 | 不引入 Prometheus/Grafana，控制复杂度 |
| 域名/SSL | Let's Encrypt + Certbot | 免费，自动续期 |

---

## 2. 服务器部署方案

### 2.1 服务器规格

| 项目 | 推荐配置 | 月费 |
|------|----------|------|
| VPS | 2 vCPU / 2GB RAM / 40GB SSD | $12-15 |
| 位置 | 法兰克福 (Hetzner) 或 伊斯坦布尔 | — |
| 操作系统 | Ubuntu 24.04 LTS | — |
| 域名 | api-agg.dev 或类似 | ~$10/年 |

**选择法兰克福的理由：** Hetzner 性价比最高，到亚美尼亚延迟 ~60ms，到中国 ~200ms（模型源 API 调用可接受）。

### 2.2 Docker Compose 部署

```yaml
# docker-compose.yml
version: '3.8'

services:
  oneapi:
    image: justsong/one-api:latest
    container_name: oneapi
    restart: always
    ports:
      - "3000:3000"
    volumes:
      - ./oneapi-data:/data
    environment:
      - TZ=Asia/Yerevan
      - SQL_DSN=/data/oneapi.db
      - SESSION_SECRET=<random-32-chars>
      - CHANNEL_UPDATE_FREQUENCY=60
      - CHANNEL_TEST_FREQUENCY=120
    networks:
      - api-net

  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/ssl:/etc/nginx/ssl
      - ./logs/nginx:/var/log/nginx
    depends_on:
      - oneapi
    networks:
      - api-net

networks:
  api-net:
    driver: bridge
```

### 2.3 Nginx 配置

```nginx
# nginx/conf.d/oneapi.conf
server {
    listen 443 ssl http2;
    server_name api.example.com;

    ssl_certificate     /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;

    # 限流：每 IP 每秒 10 请求
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;

    location / {
        limit_req zone=api burst=20 nodelay;
        proxy_pass http://oneapi:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
```

### 2.4 初始化脚本

```bash
#!/bin/bash
# deploy.sh — 一键部署

set -e

# 1. 安装 Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# 2. 安装 Docker Compose
sudo apt install -y docker-compose-plugin

# 3. 创建目录结构
mkdir -p ~/oneapi/{oneapi-data,nginx/conf.d,nginx/ssl,logs/nginx}

# 4. 配置 SSL
sudo apt install -y certbot
sudo certbot certonly --standalone -d api.example.com

# 5. 复制证书
sudo cp /etc/letsencrypt/live/api.example.com/fullchain.pem ~/oneapi/nginx/ssl/
sudo cp /etc/letsencrypt/live/api.example.com/privkey.pem ~/oneapi/nginx/ssl/

# 6. 启动
cd ~/oneapi && docker compose up -d

# 7. 初始化 OneAPI 管理员
echo "访问 https://api.example.com 完成初始设置"
echo "默认用户名: root  密码: 123456  (请立即修改)"
```

---

## 3. 模型渠道对接方案

### 3.1 八家模型源接入详情

| # | 厂商 | 模型 | API Base URL | API Key 获取 | 定价 (输入/输出 /百万tokens) | 备注 |
|---|------|------|-------------|-------------|--------------------------|------|
| 1 | 阿里 | Qwen-Max / Qwen-Plus | `https://dashscope.aliyuncs.com/compatible-mode/v1` | 阿里云控制台 → DashScope | ¥0.02/¥0.06 (Plus) | 兼容 OpenAI 格式 |
| 2 | 小米 | MiMo-7B | `https://api.xiaomi.com/v1` (待确认) | 小米开放平台 | 待定价 | 新上线，可能免费/低价 |
| 3 | DeepSeek | DeepSeek-V3 / Chat | `https://api.deepseek.com/v1` | platform.deepseek.com | ¥1/¥2 (V3) | 最高性价比 |
| 4 | 字节 | 豆包 (Doubao) | `https://ark.cn-beijing.volces.com/api/v3` | 火山引擎控制台 | ¥0.8/¥2 (Pro) | 需创建推理接入点 |
| 5 | 智谱 | GLM-4-Plus | `https://open.bigmodel.cn/api/paas/v4` | open.bigmodel.cn | ¥5/¥5 (GLM-4-Plus) | OpenAI 兼容格式 |
| 6 | 月暗 | Moonshot-v1-128k | `https://api.moonshot.cn/v1` | platform.moonshot.cn | ¥60/¥60 (128k) | 长上下文优势 |
| 7 | 零一 | Yi-Lightning | `https://api.lingyiwanwu.com/v1` | platform.lingyiwanwu.com | ¥0.99/¥0.99 | 性价比不错 |
| 8 | 腾讯 | 混元 Turbo | `https://api.hunyuan.cloud.tencent.com/v1` | 腾讯云控制台 | ¥4.5/¥5 | 格式兼容 OpenAI |

### 3.2 OneAPI 渠道配置步骤

在 OneAPI 管理面板 (`/channel`) 逐一添加：

1. **阿里 DashScope**
   - 类型：OpenAI (兼容)
   - Base URL：`https://dashscope.aliyuncs.com/compatible-mode/v1`
   - Key：从 DashScope 控制台获取
   - 模型：`qwen-max`, `qwen-plus`, `qwen-turbo`
   - 优先级：1 (主力)

2. **DeepSeek**
   - 类型：OpenAI (兼容)
   - Base URL：`https://api.deepseek.com`
   - Key：从 platform.deepseek.com 获取
   - 模型：`deepseek-chat`, `deepseek-coder`, `deepseek-reasoner`
   - 优先级：1 (主力)

3. **字节豆包**
   - 类型：OpenAI (兼容)
   - Base URL：`https://ark.cn-beijing.volces.com/api/v3`
   - Key：火山引擎 API Key
   - 模型：`doubao-pro-32k`, `doubao-lite-32k`
   - 注意：需在火山引擎创建推理接入点，接入点 ID 即为模型名
   - 优先级：2

4. **智谱 GLM**
   - 类型：OpenAI (兼容)
   - Base URL：`https://open.bigmodel.cn/api/paas/v4`
   - 模型：`glm-4-plus`, `glm-4-flash`
   - 优先级：2

5. **其余四家** — 同理配置，Base URL 和 Key 各自对应。

### 3.3 模型分组与负载均衡

在 OneAPI 中创建**模型映射**：

| 用户请求模型 | 实际渠道 | 策略 |
|-------------|---------|------|
| `gpt-4-turbo` | qwen-max, deepseek-chat | 优先 qwen-max，fallback deepseek |
| `gpt-3.5-turbo` | qwen-turbo, deepseek-chat, doubao-lite | 轮询负载均衡 |
| `claude-3-sonnet` | glm-4-plus, yi-lightning | 优先 glm-4 |
| `deepseek` | deepseek-chat, deepseek-coder | 直连 |

---

## 4. 用户管理与计费

### 4.1 OneAPI 内置功能

OneAPI 原生支持：
- **Token 管理**：每个用户一个 API Key，支持设置额度上限
- **兑换码**：可批量生成，用于推广期赠送额度
- **计费模型**：按 token 计费，可设置倍率
- **用户分组**：可设置不同用户组看到不同模型

### 4.2 定价策略

| 层级 | 模型 | 定价 (每百万 tokens) | 对比原价 | 加价率 |
|------|------|---------------------|---------|-------|
| 基础 | Qwen-Turbo, DeepSeek-Chat | $0.05 / $0.15 | $0.03/$0.09 | ~60% |
| 标准 | Qwen-Max, GLM-4-Plus | $0.30 / $0.60 | $0.20/$0.40 | ~50% |
| 高级 | Moonshot-128k, DeepSeek-Reasoner | $1.00 / $1.50 | $0.60/$0.90 | ~60% |

**定价原则：** 比 OpenAI 便宜 70-80%，比国内原价贵 50-60%，利润空间足够覆盖成本。

### 4.3 注册与充值流程

**MVP 阶段不做自动化充值系统。** 流程如下：

1. 用户通过 Telegram Bot 或邮件申请 API Key
2. 管理员在 OneAPI 后台手动创建用户、分配 Key
3. 用户通过 USDT (TRC-20) 或银行转账付款
4. 管理员手动为用户充值额度
5. 后期可引入自动兑换码系统

**为什么不做自动支付：** 单人运营，用户量 <100 时手动管理更可控，避免支付集成的法律/技术风险。

---

## 5. 零停机升级方案

### 5.1 OneAPI 升级流程

```bash
#!/bin/bash
# upgrade.sh — 零停机升级 OneAPI

cd ~/oneapi

# 1. 拉取新镜像
docker compose pull oneapi

# 2. 重启容器 (Docker 会先停旧容器再启新容器，中断 <5s)
docker compose up -d oneapi

# 3. 验证
sleep 3
curl -s http://localhost:3000/api/status | jq .

# 4. 清理旧镜像
docker image prune -f
```

### 5.2 数据备份

```bash
#!/bin/bash
# backup.sh — 每日备份 (通过 crontab)

BACKUP_DIR=~/backups/$(date +%Y%m%d)
mkdir -p $BACKUP_DIR

# 备份 SQLite 数据库
cp ~/oneapi/oneapi-data/oneapi.db $BACKUP_DIR/

# 备份配置
cp ~/oneapi/docker-compose.yml $BACKUP_DIR/

# 保留最近 7 天
find ~/backups -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;
```

**Crontab：** `0 3 * * * /home/user/backup.sh >> /home/user/logs/backup.log 2>&1`

---

## 6. 监控与 AI 运维

### 6.1 健康检查脚本

```bash
#!/bin/bash
# health-check.sh — 每 5 分钟检查一次

# 检查 OneAPI 是否响应
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/status)

if [ "$HTTP_CODE" != "200" ]; then
    echo "[ALERT] OneAPI 无响应 (HTTP $HTTP_CODE), 正在重启..."
    cd ~/oneapi && docker compose restart oneapi
    # 通过 Telegram Bot 发送告警
    curl -s "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "text=⚠️ OneAPI 服务异常，已自动重启 (HTTP $HTTP_CODE)"
fi
```

### 6.2 模型渠道健康监控

```bash
#!/bin/bash
# channel-check.sh — 每小时测试各渠道

CHANNELS=("qwen-max" "deepseek-chat" "glm-4-plus" "doubao-pro-32k")

for MODEL in "${CHANNELS[@]}"; do
    RESULT=$(curl -s -X POST http://localhost:3000/v1/chat/completions \
        -H "Authorization: Bearer ${TEST_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":5}")
    
    if echo "$RESULT" | grep -q "error"; then
        echo "[WARN] 渠道 $MODEL 异常: $RESULT"
    else
        echo "[OK] 渠道 $MODEL 正常"
    fi
done
```

### 6.3 用量统计

OneAPI 内置 `/log` 页面可查看：
- 每日请求量
- 每模型调用量
- 每用户消耗
- 错误率

**关键指标：**
- 日活用户数 (DAU)
- 每日 API 调用次数
- 各渠道错误率（>5% 需排查）
- 月度成本 vs 收入

---

## 7. 安全加固

### 7.1 基础安全

```bash
# 1. 修改 SSH 端口 + 禁用密码登录
sudo sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# 2. 配置 UFW 防火墙
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp   # SSH
sudo ufw allow 80/tcp     # HTTP
sudo ufw allow 443/tcp    # HTTPS
sudo ufw enable

# 3. fail2ban
sudo apt install -y fail2ban
sudo systemctl enable fail2ban
```

### 7.2 OneAPI 安全

- 修改默认管理员密码（强密码 16+ 字符）
- 关闭公开注册（通过 `REGISTRATION_ENABLED=false` 环境变量）
- 为每个用户设置独立 Key 和额度上限
- 启用请求日志审计

---

## 8. 成本与收入模型

### 8.1 月度成本

| 项目 | 费用 |
|------|------|
| VPS (2C/2G) | $12-15 |
| 域名 (月均) | $1 |
| 模型 API 成本 | 按用量，起步 $0 |
| **合计** | **$13-16/月** |

### 8.2 收入预期 (3 个月 MVP)

| 阶段 | 用户数 | 月均消费 | 月收入 | 月利润 |
|------|--------|---------|--------|--------|
| 月 1 (获客) | 5-10 | $10 | $50-100 | $35-85 |
| 月 2 (增长) | 15-30 | $15 | $225-450 | $210-435 |
| 月 3 (验证) | 30-50 | $20 | $600-1000 | $585-985 |

### 8.3 盈亏平衡点

- 月成本 ~$15
- 平均加价率 ~50%
- 盈亏平衡：月 API 消耗 $30 即可覆盖
- 对应：3-5 个活跃用户

---

## 9. 4 周 MVP 执行路线图

### Week 1: 基础设施 + 核心渠道

| 天 | 任务 | 产出 |
|----|------|------|
| D1 | 购买 VPS (Hetzner CX21) + 域名 | 服务器可 SSH |
| D2 | 部署 Docker + OneAPI + Nginx | https://api.example.com 可访问 |
| D3 | 接入阿里 DashScope + DeepSeek | 2 个渠道在线 |
| D4 | 接入智谱 + 字节 | 4 个渠道在线 |
| D5 | 接入剩余 4 家 | 8 个渠道全部在线 |
| D6 | 配置模型映射 + 分组 | 用户可用统一 API 调用 |
| D7 | 安全加固 + 备份脚本 + 监控 | 生产环境可用 |

### Week 2: 用户系统 + 推广启动

| 天 | 任务 | 产出 |
|----|------|------|
| D8-9 | 创建 Telegram Bot (@AI_API_Agg_Bot) | 用户可通过 Bot 申请 Key |
| D10 | 手动创建 10 个测试 Key + 兑换码 | 内测邀请码就绪 |
| D11-12 | 撰写 2 篇技术博客 (中/英/俄) | 推广内容就绪 |
| D13-14 | 发布到 5 个目标社群 + 开源社区 | 获客启动 |

### Week 3: 获客 + 迭代

| 天 | 任务 | 产出 |
|----|------|------|
| D15-16 | 收集前 5 个用户反馈 | Bug 列表 + 需求列表 |
| D17-18 | 修复高优先级问题 | 稳定性提升 |
| D19-20 | 发布第二批推广内容 | 扩大触达 |
| D21 | 月度成本/收入核算 | 财务数据 |

### Week 4: 验证 + 决策

| 天 | 任务 | 产出 |
|----|------|------|
| D22-23 | 分析用户留存和使用模式 | 数据报告 |
| D24-25 | 优化定价和模型配置 | 调价方案 |
| D26-27 | 准备月度报告 | MVP 月报 |
| D28 | Go/No-Go 决策 | 是否继续 |

---

## 10. 风险与应对

| 风险 | 概率 | 影响 | 应对 |
|------|------|------|------|
| 模型源 API 变更/下线 | 中 | 高 | OneAPI 渠道快速切换；保持 2+ 备选渠道 |
| 模型源封号 (违反TOS) | 低 | 高 | 仔细阅读各家 TOS；不做明确禁止的转售；分散渠道 |
| 获客困难 | 中 | 中 | 调整推广渠道；降低价格；提供免费试用额度 |
| VPS 被封 | 低 | 中 | 备份数据；准备备用 VPS；使用非敏感域名 |
| 支付纠纷 | 低 | 低 | 使用 USDT 等不可逆支付方式；小额度充值 |
| 竞争对手出现 | 中 | 低 | 先发优势；社群关系；价格优势 |

---

## 11. 技术债务与后期优化

**MVP 阶段不做（明确排除）：**
- ❌ 自动化支付系统（Stripe/支付宝/USDT 自动充值）
- ❌ 多节点/高可用部署
- ❌ 自定义用户面板/前端
- ❌ 多语言 UI
- ❌ 企业级 SLA

**3 个月后如果验证成功，考虑：**
- ✅ 自动兑换码系统（减少手动充值工作量）
- ✅ Telegram Bot 自助充值
- ✅ 简单的用量仪表盘（给用户看）
- ✅ CDN 加速

---

## 12. 立即可执行的 Action Items

1. **今天：** 购买 Hetzner CX21 VPS ($4.5/月起) + 域名
2. **明天：** 按 deploy.sh 部署 OneAPI
3. **本周内：** 注册 8 家模型源 API Key
4. **下周：** 开始推广获客

---

## 附录 A: OneAPI 关键配置参考

### 环境变量

```env
# 必设
SESSION_SECRET=<32位随机字符串>
SQL_DSN=/data/oneapi.db

# 推荐
CHANNEL_UPDATE_FREQUENCY=60      # 渠道状态检查间隔(秒)
CHANNEL_TEST_FREQUENCY=120       # 渠道测试间隔(秒)
TOKEN_EXPIRED_ENABLED=true       # 启用 Token 过期
GLOBAL_API_RATE_LIMIT=100        # 全局 API 速率限制/分钟
```

### API 测试命令

```bash
# 测试连接
curl https://api.example.com/v1/chat/completions \
  -H "Authorization: Bearer sk-your-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-chat",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 50
  }'

# 测试流式输出
curl https://api.example.com/v1/chat/completions \
  -H "Authorization: Bearer sk-your-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen-max",
    "messages": [{"role": "user", "content": "Hi"}],
    "stream": true
  }'
```

---

## 附录 B: 故障排查速查

| 现象 | 可能原因 | 排查命令 |
|------|---------|---------|
| API 返回 502 | OneAPI 容器挂了 | `docker ps` → `docker logs oneapi` |
| 特定模型报错 | 该渠道 API Key 失效 | OneAPI 后台 → 渠道 → 测试 |
| 所有模型超时 | 网络问题或 VPS 被限速 | `curl -v https://api.deepseek.com` |
| 响应慢 | 模型源延迟高 | 检查 OneAPI 日志中的响应时间 |

---

**报告完毕。** 此报告可直接作为执行手册使用，无需额外技术评审。
