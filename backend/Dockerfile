# =============================================
# AI API 聚合平台 — Go 后端 Dockerfile
# =============================================
# 多阶段构建: 编译 → 最小运行时镜像
# =============================================

# ==========================================
# Stage 1: 编译 Go 二进制
# ==========================================
FROM golang:1.25-alpine AS builder

WORKDIR /build

# 安装编译依赖
RUN apk add --no-cache gcc musl-dev

# 复制依赖文件并下载模块
COPY go.mod go.sum ./
RUN go mod download

# 复制源码并编译
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" -o server ./cmd/server

# ==========================================
# Stage 2: 最小运行时镜像
# ==========================================
FROM alpine:3.21

# 安装健康检查依赖和 ca-certificates
RUN apk add --no-cache curl ca-certificates tzdata

# 设置时区
ENV TZ=Asia/Shanghai

WORKDIR /app

# 从编译阶段复制二进制
COPY --from=builder /build/server .

# 创建数据目录
RUN mkdir -p /app/data

# 默认端口（可通过环境变量 PORT 覆盖）
ENV PORT=8080
EXPOSE 8080

# 健康检查
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
    CMD curl -f http://localhost:${PORT}/health || exit 1

ENTRYPOINT ["./server"]
