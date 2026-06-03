package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/ai-api-agg/backend/internal/admin"
	"github.com/ai-api-agg/backend/internal/apikey"
	"github.com/ai-api-agg/backend/internal/auth"
	"github.com/ai-api-agg/backend/internal/config"
	"github.com/ai-api-agg/backend/internal/cron"
	"github.com/ai-api-agg/backend/internal/database"
	"github.com/ai-api-agg/backend/internal/email"
	"github.com/ai-api-agg/backend/internal/middleware"
	"github.com/ai-api-agg/backend/internal/notify"
	"github.com/ai-api-agg/backend/internal/payment"
	"github.com/ai-api-agg/backend/internal/proxy"
	"github.com/ai-api-agg/backend/internal/scheduler"
	"github.com/ai-api-agg/backend/internal/usage"
	"github.com/ai-api-agg/backend/internal/usdt"
	"github.com/ai-api-agg/backend/internal/workgroup"
	"github.com/gin-contrib/cors"
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

	// 创建邮件发送器
	emailSender := notify.NewEmailSender(cfg.MailgunAPIKey, cfg.MailgunDomain, "")

	// 创建统一通知中心
	notifCenter := notify.NewCenter()
	notifCenter.Register(notify.NewTelegramChannel(tg))       // Telegram → 后台管理通知
	notifCenter.Register(notify.NewEmailChannel(emailSender)) // 邮件 → 用户通知
	notifCenter.Register(&notify.LogChannel{})                // 日志 → 开发调试
	log.Println("通知中心已初始化")

	// 创建处理器
	authHandler := auth.NewHandler(db, cfg.JWTSecret, emailSender)

	// OAuth handler
	oauthConfig := auth.OAuthConfig{
		Google: auth.OAuthProvider{
			ClientID:     cfg.GoogleClientID,
			ClientSecret: cfg.GoogleClientSecret,
			RedirectURL:  strings.TrimRight(cfg.PublicURL, "/") + "/auth/oauth/google/callback",
		},
		GitHub: auth.OAuthProvider{
			ClientID:     cfg.GitHubClientID,
			ClientSecret: cfg.GitHubClientSecret,
			RedirectURL:  strings.TrimRight(cfg.PublicURL, "/") + "/auth/oauth/github/callback",
		},
	}
	oauthHandler := auth.NewOAuthHandler(db, cfg.JWTSecret, oauthConfig, cfg.FrontendURL)
	apikeyHandler := apikey.NewHandler(db, cfg.EncryptionKey)
	workgroupHandler := workgroup.NewHandler(db)
	usageHandler := usage.NewHandler(db)

	// 确定项目根目录（从 backend/ 运行，项目根是 ..）
	projectDir := filepath.Join(filepath.Dir(os.Args[0]), "..")
	if cwd, err := os.Getwd(); err == nil {
		projectDir = filepath.Join(cwd, "..")
	}
	adminHandler := admin.NewHandler(db, projectDir)

	// 邮件处理器
	emailHandler := email.NewHandler(db, filepath.Join(projectDir, "data"), tg, emailSender)

	// 定时任务处理器（由外部 cron 触发）
	cronHandler := cron.NewHandler(db, emailSender, tg)

	// Telegram Bot 命令处理器
	botHandler := notify.NewBotHandler(tg, db, emailSender)
	botHandler.StartPolling() // 轮询模式，不依赖 webhook

	// 创建支付处理器（NOWPayments）
	paymentHandler := payment.NewHandler(db, cfg.NowPaymentsAPIKey, cfg.NowPaymentsSecret, cfg.NowPaymentsURL, notifCenter)

	// 创建代理处理器（OneAPI 转发）
	proxyHandler := proxy.NewHandler(db, cfg.EncryptionKey, cfg.OneAPIURL, cfg.OneAPIKey)

	// 内置任务调度器（替代外部 OpenClaw cron）
	scheduler.Start(cronHandler)

	// 启动 USDT 监听引擎（goroutine）
	usdtMonitor := usdt.NewMonitor(db, tg, notifCenter)
	go usdtMonitor.Start(30 * time.Second) // 每 30 秒轮询

	// 创建 Gin 引擎（启用方法不匹配告警以处理 OPTIONS preflight）
	r := gin.New()
	r.HandleMethodNotAllowed = true
	r.Use(gin.Logger())
	r.Use(gin.Recovery())

	// CORS 跨域（允许前端 dev server 及线上域名）
	r.Use(cors.New(cors.Config{
		AllowOrigins:     []string{"http://localhost:3333", "http://localhost:3000", "http://localhost:3001", "http://localhost:3002", "http://localhost:3003", "http://localhost:3456", "https://aiflowhub.ai", "http://aiflowhub.ai"},
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization", "X-Requested-With"},
		AllowCredentials: true,
	}))

	// 处理 OPTIONS preflight（CORS 中间件处理前 headers 已设置，这里返回 204）
	r.NoMethod(func(c *gin.Context) {
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		middleware.NotFound(c, "method not allowed")
	})

	// 健康检查端点
	r.GET("/health", func(c *gin.Context) {
		middleware.Success(c, gin.H{
			"status":  "ok",
			"service": "ai-api-agg",
		})
	})

	// 认证路由（无需 JWT）
	authGroup := r.Group("/api/auth")
	{
		authGroup.POST("/register", authHandler.Register)
		authGroup.POST("/login", authHandler.Login)
		authGroup.POST("/forgot-password", authHandler.ForgotPassword)
		authGroup.POST("/reset-password", authHandler.ResetPassword)

		// OAuth 路由
		oauthGroup := authGroup.Group("/oauth")
		{
			oauthGroup.GET("/google", oauthHandler.LoginGoogle)
			oauthGroup.GET("/google/callback", oauthHandler.CallbackGoogle)
			oauthGroup.GET("/github", oauthHandler.LoginGitHub)
			oauthGroup.GET("/github/callback", oauthHandler.CallbackGitHub)
		}
	}

	// 需要 JWT 认证的路由
	authRequired := r.Group("")
	authRequired.Use(middleware.JWTAuth(cfg.JWTSecret))
	{
		// 用户信息
		authRequired.GET("/api/auth/me", authHandler.Me)

		// API Key 管理
		authRequired.POST("/api/api-keys", apikeyHandler.Create)
		authRequired.GET("/api/api-keys", apikeyHandler.List)
		authRequired.DELETE("/api/api-keys/:id", apikeyHandler.Delete)
		authRequired.GET("/api/api-keys/:id/usage", apikeyHandler.Usage)
		authRequired.PATCH("/api/api-keys/:id/toggle", apikeyHandler.Toggle)

		// 工作组管理
		authRequired.GET("/api/workgroups", workgroupHandler.List)
		authRequired.POST("/api/workgroups", workgroupHandler.Create)
		authRequired.PUT("/api/workgroups/:id", workgroupHandler.Update)
		authRequired.DELETE("/api/workgroups/:id", workgroupHandler.Delete)

		// 用量统计
		authRequired.GET("/api/user/usage", usageHandler.Overview)
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

		// Provider 管理
		adminGroup.GET("/admin/providers", adminHandler.ListProviders)
		adminGroup.POST("/admin/providers", adminHandler.AddProvider)
		adminGroup.PUT("/admin/providers/:name/balance", adminHandler.UpdateProviderBalance)
		adminGroup.DELETE("/admin/providers/:name", adminHandler.DeleteProvider)
	}

	// Cron 端点（使用共享密钥 x-cron-secret 认证，不走 JWT）
	r.GET("/admin/cron/balance-check", cronHandler.BalanceCheck)
	r.POST("/admin/cron/balance-check", cronHandler.BalanceCheck)
	r.GET("/admin/cron/balance-warning", cronHandler.UserBalanceWarning)
	r.GET("/admin/cron/provider-check", cronHandler.ProviderCheck)

	// 支付路由（部分需要 JWT，webhook 不需要）
	paymentGroup := r.Group("/api/payment")
	{
		// 公开端点（无需认证）
		paymentGroup.GET("/currencies", paymentHandler.Currencies)
		paymentGroup.GET("/min-amount", paymentHandler.MinAmount)
		paymentGroup.GET("/estimate", paymentHandler.EstimateAmount)
		paymentGroup.POST("/webhook", paymentHandler.Webhook)

		// 需要 JWT 认证
		paymentAuth := paymentGroup.Group("")
		paymentAuth.Use(middleware.JWTAuth(cfg.JWTSecret))
		{
			paymentAuth.POST("/create", paymentHandler.CreatePayment)
			paymentAuth.GET("/status/:payment_id", paymentHandler.PaymentStatus)
		}
	}

	// 邮件接收（Worker → 后端，使用共享密钥）
	r.POST("/api/email/inbound", emailHandler.InboundAuth(), emailHandler.Receive)
	r.POST("/api/email/raw", emailHandler.InboundAuth(), emailHandler.ReceiveRaw)

	// Telegram Bot webhook（由 Telegram 服务器调用）
	r.POST("/api/telegram/webhook", botHandler.HandleWebhook)

	// 邮件管理（JWT + 管理员）
	emailGroup := r.Group("/api/email")
	emailGroup.Use(middleware.JWTAuth(cfg.JWTSecret))
	emailGroup.Use(middleware.AdminAuth())
	{
		emailGroup.GET("/list", emailHandler.List)
		emailGroup.GET("/search", emailHandler.Search)
		emailGroup.GET("/:id", emailHandler.Show)
		emailGroup.POST("/reply", emailHandler.Reply)
		emailGroup.GET("/keywords", emailHandler.ListKeywords)
		emailGroup.POST("/keywords", emailHandler.AddKeyword)
		emailGroup.DELETE("/keywords/:id", emailHandler.DeleteKeyword)
	}

	// 模型代理路由（通过 API Key 认证，不需要 JWT）
	r.POST("/v1/chat/completions", proxyHandler.ChatCompletions)

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
