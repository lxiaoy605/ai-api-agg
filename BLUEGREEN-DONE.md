# 蓝绿部署 + 回滚 — 完成报告

> **任务来源:** MASTER-PLAN 5.1 + 5.3
> **完成日期:** 2026-05-28
> **对应章节:** 蓝绿部署 (5.1) + 三层回滚 (5.3)

---

## 产出物清单

| # | 文件 | 用途 |
|---|------|------|
| 1 | `docker/haproxy/haproxy.cfg` | HAProxy 流量调度配置 |
| 2 | `scripts/bluegreen-switch.sh` | 蓝绿切换引擎 |
| 3 | `scripts/rollback.sh` | 三层回滚执行器 |
| 4 | `docker/docker-compose.yml` | 更新：新增 haproxy + blue + green 服务 |
| 5 | `docker/bluegreen-docker-compose.override.yml` | 蓝绿模式生产配置覆盖 |
| 6 | `scripts/bluegreen-deploy.sh` | 一键蓝绿环境部署 |

---

## 1. HAProxy 配置 (`docker/haproxy/haproxy.cfg`)

**架构:** HAProxy 作为前端负载均衡，将流量分发到两个 OneAPI 实例。

```
用户请求 → HAProxy :8080
                ├──→ oneapi-blue:3000 (weight=100, active)
                └──→ oneapi-green:3000 (weight=0, standby)

管理请求 → HAProxy :8081/stats (状态页面)
```

**关键配置：**
- 前端 `api_front` 绑定 `0.0.0.0:8080`，接收所有 API 流量
- 前端 `mgmt_front` 绑定 `0.0.0.0:8081`，提供 HAProxy 状态页
- 后端 `oneapi_pool` 使用 roundrobin + 主动健康检查 (`GET /api/status`)
- Blue 初始 weight=100，Green 初始 weight=0（热备）
- Unix socket 运行时管理 (`/var/run/haproxy.sock`)

**使用方式：**
```bash
docker compose -f docker/docker-compose.yml up -d haproxy
# 状态页: http://localhost:8081/stats (admin / ${HAPROXY_STATS_PASSWORD})
```

---

## 2. 蓝绿切换脚本 (`scripts/bluegreen-switch.sh`)

**两种切换模式：**

| 模式 | 参数 | 说明 | 停机时间 |
|------|------|------|---------|
| 完全切换 | `--mode instant` | 瞬间将 100% 流量切到目标实例 | 0（零停机） |
| 灰度迁移 | `--mode gradual --weight N` | 逐步增加目标权重，每步观察 30s | 0（零停机） |

**使用示例：**
```bash
# 查看当前状态
./scripts/bluegreen-switch.sh status

# 完全切换到 Green
./scripts/bluegreen-switch.sh --target green --mode instant

# 灰度 30% 流量到 Green
./scripts/bluegreen-switch.sh --target green --mode gradual --weight 30

# 紧急回滚
./scripts/bluegreen-switch.sh rollback
```

**切换流程（instant 模式）：**
1. 确保目标实例运行 (`docker compose up -d oneapi-{target}`)
2. 目标实例健康检查（最多重试 6 次，每次 5s）
3. 通过 HAProxy socket 动态调整权重（target→100, current→0）
4. 验证权重生效
5. 最终服务验证 + 通知

**灰度流程（gradual 模式）：**
1. 每步增加 20% 权重（可配置 GRADUAL_STEP）
2. 每步间隔 30s 观察（可配置 GRADUAL_INTERVAL）
3. 每步后检查目标实例状态，异常则自动回滚
4. 到达目标权重后最终验证 + 通知

---

## 3. 三层回滚脚本 (`scripts/rollback.sh`)

| 层级 | 触发条件 | 恢复时间 | 影响范围 |
|------|---------|---------|---------|
| **L1 流量回滚** | 新版错误/人工触发 | 秒级 | 无（零停机） |
| **L2 容器回滚** | L1 后旧版不可用 | 分钟级 | 短暂中断 |
| **L3 数据回滚** | 数据库迁移失败 | 分钟级 | 数据回退到备份点 |

**使用示例：**
```bash
# L1: 流量回滚（交互确认）
./scripts/rollback.sh --layer 1

# L2: 容器回滚（自动执行）
./scripts/rollback.sh --layer 2 --auto

# L3: 从指定备份恢复
./scripts/rollback.sh --layer 3 --backup backups/full/20260528_120000.tar.gz

# 多层回滚
./scripts/rollback.sh --layer 1 --layer 2

# 查看回滚历史
./scripts/rollback.sh --status
```

**L3 数据回滚流程：**
1. 创建当前数据库安全副本
2. 暂停两个 OneAPI 实例
3. 从备份解压并校验数据库完整性 (`PRAGMA integrity_check`)
4. 恢复数据库到两个实例的数据卷
5. 重启 + 健康验证

**关键特性：**
- 所有回滚操作记录到 `logs/rollback.log`
- L3 回滚前自动创建安全副本，即使失败也可手动恢复
- 支持 `--auto` 模式跳过交互确认（适合自动化运维）

---

## 4. Docker Compose 更新

**新增服务：**

| 服务名 | 镜像 | 端口 | 数据卷 |
|--------|------|------|--------|
| `haproxy` | haproxy:3-alpine | 8080, 8081 | 无（配置文件挂载） |
| `oneapi-blue` | justsong/one-api:latest | 3001:3000 | oneapi_blue_data（独立） |
| `oneapi-green` | justsong/one-api:latest | 3002:3000 | oneapi_green_data（独立） |

**新增数据卷：** `oneapi_blue_data`, `oneapi_green_data`（local driver）

**现有兼容性：** 原有 `oneapi` 单实例服务未修改，向后兼容。蓝绿模式是可选增强。

---

## 5. 一键部署脚本 (`scripts/bluegreen-deploy.sh`)

**部署流程：**
1. 前置条件检查（Docker, Compose, 配置文件）
2. 拉取 HAProxy + OneAPI 镜像
3. 处理旧单实例冲突
4. 启动 Blue + Green 实例
5. 双端健康检查（最多 60s）
6. 启动 HAProxy + 路由验证

**使用示例：**
```bash
# 标准部署
./scripts/bluegreen-deploy.sh

# 使用生产 override 配置
./scripts/bluegreen-deploy.sh --with-override

# 查看环境状态
./scripts/bluegreen-deploy.sh --status

# 停止蓝绿环境
./scripts/bluegreen-deploy.sh --down
```

---

## 快速开始

```bash
# 1. 确保环境变量已配置
cp docker/.env.example docker/.env
cp docker/oneapi/.env.example docker/oneapi/.env
# 编辑 docker/.env 填入实际值（DOMAIN, API Key, Telegram 等）

# 2. 一键部署蓝绿环境
./scripts/bluegreen-deploy.sh

# 3. 验证部署
./scripts/bluegreen-switch.sh status

# 4. 使用 HAProxy 入口测试
curl http://localhost:8080/api/status
```

---

## 运维命令速查

```bash
# 状态查看
./scripts/bluegreen-switch.sh status                        # 蓝绿权重详情
./scripts/bluegreen-deploy.sh --status                      # 容器运行状态

# 切换操作
./scripts/bluegreen-switch.sh --target green --mode instant  # 切到 Green
./scripts/bluegreen-switch.sh --target blue --mode gradual --weight 30  # 灰度 30%

# 回滚
./scripts/bluegreen-switch.sh rollback                       # 快捷回滚
./scripts/rollback.sh --layer 1 --auto                      # L1 流量回滚
./scripts/rollback.sh --layer 3 --backup <file>             # L3 数据恢复

# 监控
# HAProxy 状态页: http://localhost:8081/stats
# 日志: logs/bluegreen.log, logs/rollback.log
```

---

## 环境变量

所有脚本从 `docker/.env` 读取：

| 变量 | 用途 |
|------|------|
| `HAPROXY_STATS_PASSWORD` | HAProxy 状态页密码 |
| `ONEAPI_ADMIN_TOKEN` | OneAPI 管理 API Token |
| `TELEGRAM_BOT_TOKEN` | Telegram Bot Token（通知） |
| `TELEGRAM_CHAT_ID` | Telegram 目标频道 ID |

---

## 下一步

- [ ] 在生产环境测试蓝绿切换
- [ ] 配置 Nginx 反代指向 HAProxy:8080（代替直连 oneapi:3000）
- [ ] 建立定时健康检查 cron，自动触发 L1 回滚
- [ ] 测试 Key 轮换脚本与蓝绿部署的配合
