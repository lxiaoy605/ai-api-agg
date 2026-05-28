package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/ai-api-agg/backend/internal/admin"
	"github.com/ai-api-agg/backend/internal/apikey"
	"github.com/ai-api-agg/backend/internal/auth"
	"github.com/ai-api-agg/backend/internal/config"
	"github.com/ai-api-agg/backend/internal/database"
	"github.com/ai-api-agg/backend/internal/middleware"
	"github.com/ai-api-agg/backend/internal/notify"
	"github.com/ai-api-agg/backend/internal/payment"
	"github.com/ai-api-agg/backend/internal/usdt"
	"github.com/gin-gonic/gin"
)

func main() {
	// 加载配置
	cfg := config.Load()

	// 初始化数据库
	db, err := database.Init(cfg.DatabasePath)
	if err != nil {
		log.Fatalf("数据库初始化失败: %v", err)
	}
	defer db.Close()
	log.Println("数据库初始化完成")

	// 创建 Telegram 通知器（全局共享）
	tg := notify.NewTelegram()
	if tg.Enabled() {
		log.Println("Telegram 通知已启用")
	} else {
		log.Println("Telegram 通知未配置（缺少 TELEGRAM_BOT_TOKEN 或 TELEGRAM_CHAT_ID）")
	}

	// 创建处理器
	authHandler := auth.NewHandler(db, cfg.JWTSecret)
	apikeyHandler := apikey.NewHandler(db, cfg.EncryptionKey)

	// 确定项目根目录（从 backend/ 运行，项目根是 ..）
	projectDir := filepath.Join(filepath.Dir(os.Args[0]), "..")
	if cwd, err := os.Getwd(); err == nil {
		projectDir = filepath.Join(cwd, "..")
	}
	adminHandler := admin.NewHandler(db, projectDir)

	// 创建支付处理器（NOWPayments）
	paymentHandler := payment.NewHandler(db, cfg.NowPaymentsAPIKey, cfg.NowPaymentsSecret, cfg.NowPaymentsURL)

	// 启动 USDT 监听引擎（goroutine）
	usdtMonitor := usdt.NewMonitor(db, tg)
	go usdtMonitor.Start(30 * time.Second) // 每 30 秒轮询

	// 创建 Gin 引擎
	r := gin.Default()

	// 健康检查端点
	r.GET("/health", func(c *gin.Context) {
		middleware.Success(c, gin.H{
			"status":  "ok",
			"service": "ai-api-agg",
		})
	})

	// 认证路由（无需 JWT）
	authGroup := r.Group("/auth")
	{
		authGroup.POST("/register", authHandler.Register)
		authGroup.POST("/login", authHandler.Login)
	}

	// 需要 JWT 认证的路由
	authRequired := r.Group("")
	authRequired.Use(middleware.JWTAuth(cfg.JWTSecret))
	{
		// 用户信息
		authRequired.GET("/auth/me", authHandler.Me)

		// API Key 管理
		authRequired.POST("/api-keys", apikeyHandler.Create)
		authRequired.GET("/api-keys", apikeyHandler.List)
		authRequired.DELETE("/api-keys/:id", apikeyHandler.Delete)
		authRequired.GET("/api-keys/:id/usage", apikeyHandler.Usage)
	}

	// 需要管理员权限的路由（JWT + admin role）
	adminGroup := r.Group("/api")
	adminGroup.Use(middleware.JWTAuth(cfg.JWTSecret))
	adminGroup.Use(middleware.AdminAuth())
	{
		adminGroup.GET("/stats", adminHandler.Stats)
		adminGroup.POST("/topup", adminHandler.Topup)
		adminGroup.GET("/channels", adminHandler.Channels)
		adminGroup.GET("/audit-log", adminHandler.AuditLog)
		adminGroup.POST("/backup", adminHandler.Backup)
		adminGroup.POST("/restore", adminHandler.Restore)
	}

	// 支付路由（部分需要 JWT，webhook 不需要）
	paymentGroup := r.Group("/api/payment")
	{
		// 公开端点（无需认证）
		paymentGroup.GET("/currencies", paymentHandler.Currencies)
		paymentGroup.POST("/webhook", paymentHandler.Webhook)

		// 需要 JWT 认证
		paymentAuth := paymentGroup.Group("")
		paymentAuth.Use(middleware.JWTAuth(cfg.JWTSecret))
		{
			paymentAuth.POST("/create", paymentHandler.CreatePayment)
			paymentAuth.GET("/status/:payment_id", paymentHandler.PaymentStatus)
		}
	}

	// 监听端口（通过环境变量 PORT 配置，默认 8080）
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// 优雅关闭
	srv := &http.Server{
		Addr:    ":" + port,
		Handler: r,
	}

	go func() {
		log.Printf("ai-api-agg 后端服务启动，监听 %s", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("服务启动失败: %v", err)
		}
	}()

	// 等待中断信号
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("正在关闭服务...")
	usdtMonitor.Stop()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("服务关闭失败: %v", err)
	}
	log.Println("服务已关闭")
}
