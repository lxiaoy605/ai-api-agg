# MONITORING-DONE.md — T4.1 Prometheus 监控配置

> 日期：2026-05-28
> 执行者：Claude Code
> 阶段：运维与验证（阶段 4）

---

## 一、实现了什么

### 核心配置

| 文件 | 用途 |
|------|------|
| `prometheus.yml` | Prometheus v3.x 主配置，抓取后端/OneAPI/Nginx 指标 |
| `alerting-rules.yml` | 告警规则，覆盖 6 大类共 11 条规则 |
| `alertmanager.yml` | 告警路由+通知（Telegram + 本地日志） |
| `blackbox.yml` | Blackbox Exporter HTTP/TCP 探针配置 |
| `prometheus-entrypoint.sh` | Prometheus 容器入口，处理 `${ENV}` 环境变量注入 |
| `alertmanager-entrypoint.sh` | Alertmanager 容器入口，处理 Telegram 配置注入 |
| `grafana-datasources.yml` | Grafana Prometheus 数据源自动配置 |
| `grafana-dashboards.yml` | Grafana 仪表盘自动加载配置 |
| `grafana-dashboards/ai-api-agg-overview.json` | 系统概览仪表盘（导入即用） |

### Docker Compose 新增服务

| 服务 | 端口 | 镜像 |
|------|:---:|------|
| `prometheus` | 9090 | `prom/prometheus:latest` |
| `alertmanager` | 9093 | `prom/alertmanager:latest` |
| `blackbox-exporter` | 9115 | `prom/blackbox-exporter:latest` |
| `grafana` | 3030 | `grafana/grafana:latest` |

---

## 二、抓取架构

```
Prometheus (9090)
  ├── self                 localhost:9090         自身指标
  ├── ai-api-agg-backend   backend:8080/metrics   后端 API 指标 (Go promhttp)
  ├── ai-api-agg-oneapi    → Blackbox:9115        OneAPI HTTP 探测
  ├── ai-api-agg-nginx     → Blackbox:9115        Nginx HTTP 探测
  └── blackbox-exporter    blackbox:9115          Blackbox 自身指标
```

- **抓取间隔**：15s
- **评估间隔**：15s
- **环境标签**：`env=${ENV}` 通过 `external_labels` 注入（默认 `production`）
- **数据保留**：15 天

---

## 三、告警规则清单

### 1. 渠道故障告警

| 告警名称 | 级别 | 触发条件 | 持续时间 |
|---------|:----:|---------|:------:|
| `ai_api_agg_channel_failure` | critical | OneAPI 健康检查连续失败 | 30s (3次) |
| `ai_api_agg_upstream_channel_down` | warning | 上游 AI 渠道标记为不可用 | 1m |

### 2. API 错误率告警

| 告警名称 | 级别 | 触发条件 | 持续时间 |
|---------|:----:|---------|:------:|
| `ai_api_agg_high_error_rate` | critical | 5xx 错误率 > 5% | 5m |
| `ai_api_agg_high_4xx_rate` | warning | 4xx 错误率 > 20% | 5m |

### 3. 延迟告警

| 告警名称 | 级别 | 触发条件 | 持续时间 |
|---------|:----:|---------|:------:|
| `ai_api_agg_high_latency_warning` | warning | P95 > 2000ms | 5m |
| `ai_api_agg_high_latency_critical` | critical | P95 > 5000ms | 5m |

### 4. 余额不足告警

| 告警名称 | 级别 | 触发条件 | 持续时间 |
|---------|:----:|---------|:------:|
| `ai_api_agg_low_balance_warning` | warning | 渠道余额 < $10 | 5m |
| `ai_api_agg_low_balance_critical` | critical | 渠道余额 < $5 | 5m |

### 5. 服务宕机告警

| 告警名称 | 级别 | 触发条件 | 持续时间 |
|---------|:----:|---------|:------:|
| `ai_api_agg_service_down` | critical | 任何服务下线 | 1m |
| `ai_api_agg_service_flapping` | warning | 服务 10 分钟内重启 > 1 次 | 5m |

### 6. 流量异常告警

| 告警名称 | 级别 | 触发条件 | 持续时间 |
|---------|:----:|---------|:------:|
| `ai_api_agg_request_drop` | warning | 请求量下降 > 50% | 10m |
| `ai_api_agg_request_surge` | warning | 请求量激增 > 200% | 5m |

---

## 四、通知路由

```
告警触发
  ├── severity=critical
  │   ├── 分组等待: 5s
  │   ├── 组内间隔: 2m
  │   ├── 重复间隔: 15m
  │   └── 通知: Telegram (disable_notification=false) + 本地日志
  │
  ├── severity=warning
  │   ├── 分组等待: 10s
  │   ├── 组内间隔: 5m
  │   ├── 重复间隔: 30m
  │   └── 通知: Telegram (disable_notification=true) + 本地日志
  │
  └── 恢复通知: 所有级别均发送恢复通知
```

**抑制规则**：
- 服务宕机时抑制该服务的错误率/延迟告警（避免噪音）
- critical 延迟告警抑制 warning 延迟告警

---

## 五、Grafana 仪表盘

**访问方式**：`http://<host>:3030`，默认账号 `admin/admin`

### 仪表盘：AI API 聚合平台 — 系统概览

**面板布局**：

| 区域 | 面板 | 类型 |
|------|------|:--:|
| 概览总览 | 在线服务数、HTTP 探测成功率、5xx 错误率、P95 延迟、最低渠道余额 | Stat |
| 请求量与错误率 | API 请求量趋势（2xx/4xx/5xx 分色） | Time Series |
| 请求量与错误率 | 错误率趋势（4xx + 5xx 叠加） | Time Series |
| 延迟分析 | API 延迟分位数（P50/P90/P95/P99） | Time Series |
| 延迟分析 | 网关/代理响应时间（OneAPI + Nginx） | Time Series |
| 渠道健康 | 渠道健康与余额一览表 | Table |
| 服务实例 | Prometheus/Backend/OneAPI/Nginx 在线状态 | Stat |

---

## 六、后端集成清单

后端 Go 服务需要暴露以下 Prometheus 指标（已预留接口）：

### 标准 HTTP 指标（通过 `promhttp.Handler()` 自动生成）

```go
import "github.com/prometheus/client_golang/prometheus/promhttp"

// 在路由中注册 /metrics 端点
r.GET("/metrics", gin.WrapH(promhttp.Handler()))
```

### 自定义指标（需要后端实现）

```go
// 渠道健康状态 (0=离线, 1=在线)
channelUp := prometheus.NewGaugeVec(
    prometheus.GaugeOpts{
        Name: "channel_up",
        Help: "AI 渠道健康状态",
    },
    []string{"channel"},
)

// 渠道余额 (USD)
channelBalance := prometheus.NewGaugeVec(
    prometheus.GaugeOpts{
        Name: "channel_balance_usd",
        Help: "AI 渠道剩余额度 (USD)",
    },
    []string{"channel"},
)
```

### Nginx stub_status（可选，更细粒度指标）

在 Nginx 配置中添加：
```nginx
location /nginx_status {
    stub_status on;
    access_log off;
    allow 127.0.0.1;
    deny all;
}
```

然后配合 `nginx-prometheus-exporter` 抓取。

---

## 七、如何启动

### 1. 配置环境变量

```bash
cd docker/
cp .env.example .env
# 编辑 .env，设置：
#   ENV=production
#   GRAFANA_ADMIN_PASSWORD=<安全密码>
#   TELEGRAM_BOT_TOKEN=<Bot Token>      # 可选
#   TELEGRAM_CHAT_ID=<Chat ID>          # 可选
```

### 2. 启动监控栈

```bash
# 仅启动监控相关服务
docker compose -f docker/docker-compose.yml up -d prometheus alertmanager blackbox-exporter grafana

# 或启动全部服务
docker compose -f docker/docker-compose.yml up -d
```

### 3. 验证

| 组件 | 验证方式 |
|------|---------|
| Prometheus | `curl http://localhost:9090/-/healthy` |
| Alertmanager | `curl http://localhost:9093/-/healthy` |
| Blackbox | `curl http://localhost:9115/health` |
| Grafana | 浏览器打开 `http://localhost:3030` |

### 4. 验证告警规则语法

```bash
# 如果已安装 promtool
promtool check rules monitoring/alerting-rules.yml

# 或在 Prometheus 容器内验证
docker exec ai-api-agg-prometheus promtool check rules /etc/prometheus/alerting-rules.yml
```

---

## 八、生产环境注意事项

1. **Grafana 密码**：生产环境务必修改 `GRAFANA_ADMIN_PASSWORD` 默认值
2. **Telegram Bot**：首次使用需在 Telegram 创建 Bot 并获取 Token/Chat ID
3. **数据持久化**：Prometheus/Grafana 数据已通过 Docker 卷持久化，备份时需包含这些卷
4. **端口暴露**：Prometheus(9090) 和 Grafana(3030) 暴露在宿主机，建议生产环境加 Nginx 反代 + HTTP Basic Auth 或 IP 白名单
5. **后端指标**：告警规则依赖后端暴露的 Prometheus 指标，后端部署后需确认 `/metrics` 端点可用
6. **OneAPI 指标**：OneAPI 本身不暴露 Prometheus 格式指标，当前通过 Blackbox Exporter 做 HTTP 级探测，如需更细粒度的渠道指标（如单渠道 RPM/TPM），需要在 OneAPI 源码层面添加或通过 OneAPI 日志 API 提取
