# T1.2 完成记录 — OneAPI 渠道配置

> 完成日期：2026-05-28
> 状态：✅ 已完成

## 产出清单

| 文件 | 说明 | 大小 |
|------|------|------|
| `channels/channel-configs.json` | 3 渠道 JSON 配置（含模型详情 + 价格） | 5.6 KB |
| `channels/channel-setup.sh` | 一键自动配置脚本（幂等 + 健康检查） | 10 KB |
| `channels/MODELS.md` | 模型目录 + 价格对比表 + 推荐默认模型 | 4.7 KB |
| `docker/.env.example` | 已更新：添加 3 个厂商 API Key 占位变量 | — |

## 渠道配置详情

| 渠道 | Base URL | 权重 | 模型数 | 状态 |
|------|---------|:---:|:-----:|:----:|
| DeepSeek | `https://api.deepseek.com` | 3 | 2 | ✅ |
| 智谱 Z.ai | `https://open.bigmodel.cn/api/paas/v4` | 3 | 3 | ✅ |
| 小米 MiMo | `https://token-plan-sgp.xiaomimimo.com/v1` | 2 | 4 | ✅ |

权重分配：DeepSeek 3 : 智谱 3 : MiMo 2

## 一键部署步骤

```bash
# 1. 配置环境变量
cp docker/.env.example docker/.env
# 编辑 docker/.env，填入实际 API Key：
#   DEEPSEEK_API_KEY=sk-xxx
#   ZHIPU_ZAI_API_KEY=xxx
#   MIMO_API_KEY=sk-xxx
#   ONEAPI_ADMIN_TOKEN=xxx (从 OneAPI 面板获取)

# 2. 启动 OneAPI（如未启动）
docker compose -f docker/docker-compose.yml up -d oneapi

# 3. 执行渠道配置脚本
source docker/.env
export ONEAPI_ROOT_TOKEN="$ONEAPI_ADMIN_TOKEN"
export DEEPSEEK_API_KEY
export ZHIPU_ZAI_API_KEY
export MIMO_API_KEY

./channels/channel-setup.sh

# 4. 验证
# 打开 OneAPI 管理面板 → 渠道管理 → 查看 3 个渠道状态
```

## 关键设计决策

1. **渠道类型**：全部使用 custom (type=3)，OpenAI 兼容模式
2. **智谱 Base URL**：使用国内站 `open.bigmodel.cn`，保留国际站 `api.z.ai` 作为备选注释
3. **MiMo Base URL**：使用 Token Plan SGP 端点 `token-plan-sgp.xiaomimimo.com`
4. **API Key 存储**：不在 JSON 中硬编码，通过环境变量 `${VAR}` 占位，脚本运行时替换
5. **幂等设计**：脚本先检查渠道名是否存在，已存在则跳过创建
6. **健康检查**：创建后自动调用 OneAPI `/api/channel/test/:id` 端点验证

## 模型覆盖

- DeepSeek：`deepseek-v4-flash`（对话）、`deepseek-v4-pro`（推理 CoT）
- 智谱 Z.ai：`GLM-5.1`（旗舰）、`GLM-5`（高性能）、`GLM-4.7-Flash`（免费）
- 小米 MiMo：`MiMo-V2.5-Pro`、`MiMo-V2-Pro`、`MiMo-V2-Omni`（多模态）、`MiMo-V2-Flash`

## Key 轮换系统（MASTER-PLAN 5.2）

> 完成日期：2026-05-28
> 关联脚本：`scripts/rotate-channel-key.sh`

### 轮换流程（8 步）

```
1. 读取旧渠道配置 → 备份到 logs/
2. 创建新渠道（相同配置，新 Key，权重=0）
3. 健康检查（最多 3 次重试）
4. 逐步提权（0 → 1 → 2 → 目标权重）
5. 观察窗口 5 分钟（每 60s 检查健康）
6. 旧渠道权重 → 0
7. 最终观察 5 分钟
8. 删除旧渠道 → 重命名新渠道（去掉 -new 后缀）
```

### 使用方式

```bash
# 手动轮换指定渠道
./scripts/rotate-channel-key.sh --channel-id 1 --new-key "sk-xxx"

# 按名称轮换
./scripts/rotate-channel-key.sh --channel-name "DeepSeek" --new-key "sk-xxx"

# 预演模式（仅检查不执行）
./scripts/rotate-channel-key.sh --channel-id 1 --new-key "sk-xxx" --dry-run

# 自动模式（从 docker/.env 读取，检测变更并自动轮换）
./scripts/rotate-channel-key.sh --auto

# 查看轮换状态
./scripts/rotate-channel-key.sh --status

# 安装 systemd 定时器（每 90 天自动触发）
sudo cp scripts/key-rotation.service /etc/systemd/system/
sudo cp scripts/key-rotation.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now key-rotation.timer
```

### 安全机制

| 机制 | 说明 |
|------|------|
| 幂等性 | 相同 Key 不会重复轮换 |
| 失败回滚 | 任何阶段失败自动删除临时渠道 |
| 观察窗口 | 2 次 5 分钟观察，健康检查失败立即回滚 |
| 灰度提权 | 权重从 0 逐步提升，非一次性全量切换 |
| Telegram 通知 | 每个阶段完成/失败都有通知 |
| 日志审计 | 全流程写入 `logs/key-rotation.log` |
| 配置备份 | 旧渠道配置保存到 `logs/channel_*_backup_*.json` |
