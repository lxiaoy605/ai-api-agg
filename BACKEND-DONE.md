# BACKEND-DONE.md — T2.1 + T2.2 完成报告

> 日期：2026-05-28
> 执行者：Claude Code
> 阶段：后端服务（阶段 2）

---

## 一、实现了什么

### T2.1 — 用户注册/登录 API

| 端点 | 方法 | 说明 |
|------|------|------|
| `/auth/register` | POST | 邮箱 + 密码注册，bcrypt 哈希，返回 JWT token |
| `/auth/login` | POST | 邮箱 + 密码登录，验证密码，返回 JWT token |
| `/auth/me` | GET | JWT 认证后获取当前用户信息（不含密码） |

### T2.2 — API Key 管理 CRUD

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api-keys` | POST | 创建 API Key（自动生成 sk-xxx + AES-256-GCM 加密存储） |
| `/api-keys` | GET | 列出当前用户的所有 Key（不返回完整明文） |
| `/api-keys/:id` | DELETE | 删除 Key（验证归属权） |
| `/api-keys/:id/usage` | GET | 用量统计（请求数、token 消耗） |

## 二、文件清单

```
backend/
├── cmd/server/main.go              # 入口：加载配置、初始化DB、注册路由
├── go.mod                          # Go 模块 + 依赖定义
├── go.sum                          # 依赖校验
├── internal/
│   ├── config/
│   │   └── config.go               # 环境变量配置加载（JWT_SECRET, ENCRYPTION_KEY, DB_PATH）
│   ├── database/
│   │   └── sqlite.go               # SQLite 初始化 + DDL 迁移（users, api_keys, usage_logs）
│   ├── models/
│   │   ├── user.go                 # User 模型
│   │   └── apikey.go               # ApiKey 模型 + 请求/响应 DTO
│   ├── middleware/
│   │   ├── auth.go                 # JWT Bearer token 验证中间件
│   │   └── response.go            # 统一响应格式（code/data/message）
│   ├── auth/
│   │   └── handler.go              # 注册/登录/获取用户信息处理器
│   └── apikey/
│       └── handler.go              # API Key CRUD + AES-256-GCM 加密
└── data/                           # 运行后自动创建（SQLite 数据库文件）
```

## 三、数据库表

| 表名 | 用途 | 关键字段 |
|------|------|---------|
| `users` | 用户表 | id, email(UNIQUE), password_hash, created_at, updated_at |
| `api_keys` | API Key 表 | id, user_id(FK), name, key_prefix, encrypted_key, status, created_at, last_used_at |
| `usage_logs` | 用量日志表 | id, api_key_id(FK), request_count, token_count, recorded_at |

## 四、关键实现细节

- **密码哈希**：golang.org/x/crypto/bcrypt，cost=10
- **JWT**：golang-jwt/jwt/v5，HS256 签名，24 小时过期，含 user_id/exp/iat
- **API Key 加密**：crypto/aes + crypto/cipher，AES-256-GCM 模式，Key 从环境变量 `APP_ENCRYPTION_KEY` 读取
- **Key 格式**：`sk-` + 64 位随机 hex（32 字节随机数）
- **统一响应**：`{"code": 0, "data": ..., "message": "ok"}`
- **错误码**：0=成功, 400=参数错误, 401=未授权, 404=不存在, 500=服务器错误
- **SQLite**：modernc.org/sqlite（纯 Go，无 CGO），WAL 模式，外键约束启用
- **安全**：列表接口不返回完整 Key（仅前缀 sk-xxx...），密码永远不序列化

## 五、如何启动

```bash
cd /mnt/d/WSL/openclawWorkspace/workspace/projects/ai-api-agg/backend

# 设置环境变量（可选，有默认值）
export APP_JWT_SECRET="your-secret-key"
export APP_ENCRYPTION_KEY="your-32-byte-encryption-key"
export APP_DATABASE_PATH="./data/app.db"

# 启动服务
export GOROOT=/home/openclaw/go-sdk
export GOPATH=/home/openclaw/go-projects
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
go run ./cmd/server
```

服务监听 `:8080`。

## 六、测试流程

```bash
# 1. 注册
curl -X POST http://localhost:8080/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"123456"}'

# 2. 登录
curl -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"123456"}'

# 3. 获取用户信息（用上面返回的 token）
curl http://localhost:8080/auth/me \
  -H "Authorization: Bearer <token>"

# 4. 创建 API Key
curl -X POST http://localhost:8080/api-keys \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"name":"my-key"}'

# 5. 列出 Key
curl http://localhost:8080/api-keys \
  -H "Authorization: Bearer <token>"

# 6. 用量统计
curl http://localhost:8080/api-keys/1/usage \
  -H "Authorization: Bearer <token>"

# 7. 删除 Key
curl -X DELETE http://localhost:8080/api-keys/1 \
  -H "Authorization: Bearer <token>"
```

## 七、编译验证

```bash
go build ./...   # ✅ 通过，零错误
```
