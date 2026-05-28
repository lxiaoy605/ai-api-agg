# Go 后端蓝绿部署 — 完成

## 时间
2026-05-28

## 产出清单

### 新建文件
| 文件 | 说明 |
|------|------|
| `backend/Dockerfile` | 多阶段构建：golang:1.25-alpine 编译 → alpine:3.21 运行时，HEALTHCHECK /health |
| `scripts/build-backend.sh` | Go 后端构建与蓝绿发布脚本（构建→启动 inactive→灰度切换→完成） |
| `scripts/deploy.sh` | 一键全栈部署：oneapi/backend/haproxy/nginx/prometheus/grafana |

### 修改文件
| 文件 | 变更 |
|------|------|
| `backend/cmd/server/main.go` | 监听地址从硬编码 `:8080` → `os.Getenv("PORT")`，默认 `"8080"` |
| `docker/haproxy/haproxy.cfg` | 添加 backend_pool（路由 /auth/* /api-keys/* /api/payment/* /api/stats 等到 Go 后端）；mgmt_front 添加 /status（Keepalived） |
| `docker/docker-compose.yml` | backend → backend-blue + backend-green 蓝绿双实例；更新 depends_on；添加 backend_data 卷 |
| `scripts/bluegreen-switch.sh` | 添加 `--pool oneapi|backend` 参数，双池管理；status 显示所有池 |
| `scripts/healthcheck.sh` | 添加 Go 后端 Blue/Green 实例健康检查 |
| `docker/.env` | 添加 BACKEND_BLUE_PORT=8082 / BACKEND_GREEN_PORT=8083 |
| `docker/.env.example` | 同上 |

## 架构

```
HAProxy api_front :8080
  ├── /auth/* /api-keys/* /api/payment/* /api/stats ... /health
  │     └── backend_pool
  │           ├── backend-blue:8080 (weight=100, active)
  │           └── backend-green:8080 (weight=0, standby)
  └── 所有其他路径
        └── oneapi_pool
              ├── oneapi-blue:3000 (weight=100, active)
              └── oneapi-green:3000 (weight=0, standby)

HAProxy mgmt_front :8081
  ├── /stats → HAProxy 状态页
  ├── /health → 200 OK
  └── /status → 200 OK (Keepalived)
```

## 端口规划
| 服务 | 宿主机端口 | 容器内端口 |
|------|-----------|-----------|
| OneAPI Blue | 3001 | 3000 |
| OneAPI Green | 3002 | 3000 |
| Backend Blue | 8082 | 8080 |
| Backend Green | 8083 | 8080 |
| HAProxy API | 8080 | 8080 |
| HAProxy Mgmt | 8081 | 8081 |

## 运维命令

```bash
# 查看全部状态
./scripts/bluegreen-switch.sh status

# 后端蓝绿切换
./scripts/bluegreen-switch.sh --pool backend --target green --mode instant
./scripts/bluegreen-switch.sh --pool backend --target blue --mode gradual --weight 30

# 一键全栈部署
./scripts/deploy.sh

# 后端发布（构建+切换）
./scripts/build-backend.sh

# 健康检查（包含后端蓝绿）
./scripts/healthcheck.sh
```

## 验证
- [x] bluegreen-switch.sh: bash -n 通过
- [x] build-backend.sh: bash -n 通过
- [x] deploy.sh: bash -n 通过
- [x] healthcheck.sh: bash -n 通过
- [x] main.go: `os.Getenv("PORT")` 逻辑正确，默认 "8080"
- [x] Dockerfile: 多阶段构建，HEALTHCHECK 配置
- [x] HAProxy: 路由 ACL 覆盖所有 Go 后端路径，backend_pool 配置完整
- [x] docker-compose.yml: backend-blue/backend-green 双实例，共享 backend_data 卷
- [x] .env / .env.example: BACKEND_BLUE_PORT/BACKEND_GREEN_PORT 已添加
