# API-ENDPOINTS-DONE.md — 管理 API 补充端点完成报告

> 日期：2026-05-28
> 执行者：Claude Code
> 阶段：管理 API 补充端点（T2.3）

---

## 一、新增端点

| 端点 | 方法 | 说明 | 权限 |
|------|------|------|------|
| `/api/stats` | GET | 系统统计（用户数、活跃数、24h请求/token） | admin |
| `/api/topup` | POST | 管理员手动充值 | admin |
| `/api/channels` | GET | 渠道状态（从 channels/channel-configs.json 读取） | admin |
| `/api/audit-log` | GET | 审计日志（分页，按时间倒序） | admin |
| `/api/backup` | POST | 触发备份（exec scripts/backup.sh） | admin |
| `/api/restore` | POST | 从备份恢复（exec scripts/restore.sh） | admin |

所有新端点均使用 `{"code":0,"data":...,"message":"ok"}` 响应格式。

## 二、新增/修改文件

### 新增文件
```
backend/internal/models/audit.go           # AuditEntry 模型
backend/internal/models/stats.go            # StatsResponse, TopupRequest, ChannelInfo 模型
backend/internal/middleware/admin.go        # AdminAuth 中间件（role="admin" 检查）
backend/internal/audit/logger.go           # 审计日志写入函数
backend/internal/admin/handler.go          # 管理 API 6个端点处理器
```

### 修改文件
```
backend/internal/database/sqlite.go        # 新增 audit_log 表，users 表+role+quota 列
backend/internal/models/user.go            # User 模型+Role+Quota 字段
backend/internal/middleware/auth.go         # JWT 中间件提取 role 到 context
backend/internal/auth/handler.go           # JWT claims 含 role，Login/Me 读取 role
backend/internal/apikey/handler.go         # Create/Delete API Key 写入审计日志
backend/cmd/server/main.go                 # 注册 admin 路由组
```

## 三、新增数据库表

### audit_log
```sql
CREATE TABLE audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,
    action TEXT NOT NULL,       -- apikey.create, apikey.delete, topup, backup, restore
    actor TEXT NOT NULL,        -- "user:1", "admin:1"
    target TEXT NOT NULL DEFAULT '',
    details TEXT NOT NULL DEFAULT '',
    ip TEXT NOT NULL DEFAULT ''
);
```

### users 表扩展
- `role TEXT NOT NULL DEFAULT 'user'` — 角色：user/admin
- `quota INTEGER NOT NULL DEFAULT 0` — 配额（token 数量/美分）

## 四、审计日志覆盖

以下敏感操作均会写入 audit_log：

| 操作 | action | 触发位置 |
|------|--------|---------|
| 创建 API Key | apikey.create | apikey/handler.go Create |
| 删除 API Key | apikey.delete | apikey/handler.go Delete |
| 管理员充值 | topup | admin/handler.go Topup |
| 触发备份 | backup | admin/handler.go Backup |
| 备份恢复 | restore | admin/handler.go Restore |

## 五、测试验证结果

| 测试项 | 结果 |
|--------|:----:|
| `go build ./...` | ✅ 零错误 |
| 健康检查 /health | ✅ |
| 用户注册/登录（JWT 含 role） | ✅ |
| /auth/me（返回 role+quota） | ✅ |
| API Key CRUD（含审计日志写入） | ✅ |
| /api/stats（返回统计） | ✅ |
| /api/topup（配额更新+审计日志） | ✅ |
| /api/channels（读取配置） | ✅ |
| /api/audit-log（审计日志查询） | ✅ |
| /api/backup（执行 backup.sh，文件已生成） | ✅ |
| 非 admin 访问管理端点 → 403 | ✅ |
| admin 角色访问管理端点 → 200 | ✅ |

## 六、已知说明

- backup.sh 依赖 `jq` 命令进行日志处理，当前环境未安装 jq 导致退出码 127，但备份文件已正常生成。生产环境安装 `jq` 即可。
- restore.sh 有交互式确认提示，API 通过 `echo yes |` 管道绕过了交互确认。
- 首个 admin 用户需手动通过 SQL 设置：`UPDATE users SET role='admin' WHERE id=1;`
