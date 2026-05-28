# E2E-DONE.md — T4.3 端到端测试脚本完成报告

> 日期：2026-05-28
> 执行者：Claude Code
> 阶段：运维与验证（阶段 4）

---

## 一、文件清单

```
tests/e2e/
├── test-api.sh          # 核心测试脚本（12 个测试步骤）
├── run-all.sh           # 测试入口（统一退出码）
└── E2E-DONE.md          # 本报告
```

## 二、测试覆盖范围

| # | 测试步骤 | 端点 | 预期状态码 | 验证点 |
|:--:|---------|------|:---------:|--------|
| 1 | 健康检查 | `GET /health` | 200 | 服务正常响应 |
| 2 | 用户注册 | `POST /auth/register` | 201 | 注册成功，提取 JWT token |
| 3 | 用户登录 | `POST /auth/login` | 200 | 登录成功，返回新 token |
| 4 | 重复注册 | `POST /auth/register` | 409 | 同邮箱注册被拒绝 |
| 5 | 错误密码登录 | `POST /auth/login` | 401 | 错误密码登录被拒绝 |
| 6 | 未认证访问 | `GET /api-keys` | 401 | 无 token 访问被拒绝 |
| 7 | 创建 API Key | `POST /api-keys` | 201 | 创建成功，返回完整 Key |
| 8 | 列出 API Key | `GET /api-keys` | 200 | 列表不暴露完整 Key |
| 9 | 查看 Key 用量 | `GET /api-keys/:id/usage` | 200 | 用量统计正常返回 |
| 10 | 删除 API Key | `DELETE /api-keys/:id` | 200 | 删除成功 |
| 11 | 删除不存在的 Key | `DELETE /api-keys/nonexistent` | 404 | 不存在的 Key 返回 404 |
| 12 | 获取当前用户 | `GET /auth/me` | 200 | 返回用户信息，不含密码 |

## 三、使用方法

### 前提条件
- 后端服务已启动（默认 `http://localhost:8080`）
- `curl` 和 `bash` 可用

### 运行测试

```bash
# 默认连接 localhost:8080
bash tests/e2e/run-all.sh

# 指定目标服务
BASE_URL=https://api.example.com bash tests/e2e/run-all.sh

# 直接运行测试脚本
BASE_URL=http://localhost:3000 bash tests/e2e/test-api.sh
```

### 退出码
- `0` = 全部测试通过
- `1-255` = 失败测试数量（上限 255）

## 四、设计特性

- **失败继续执行**：任何步骤失败不会中断后续测试，最后汇报总计
- **颜色输出**：绿色 PASS / 红色 FAIL / 黄色 SKIP
- **时间戳日志**：每步带 `[HH:MM:SS]` 时间标记
- **自动跳过**：缺少前置条件时（如 token 获取失败），后续依赖步骤自动 SKIP
- **可配置目标**：通过 `BASE_URL` 环境变量切换测试目标
- **唯一邮箱**：每次运行使用带时间戳的邮箱，避免与历史测试冲突

## 五、已知限制

- JSON 解析基于 `grep`/`sed`/`cut` 文本匹配，不依赖 `jq`（保证最小依赖）
- 需要后端服务处于运行状态
- 测试会在数据库中产生残留数据（测试用户 + Key），建议在测试环境运行
