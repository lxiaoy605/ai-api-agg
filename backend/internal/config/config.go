package config

import (
	"os"
	"strconv"
)

// Config 应用配置
type Config struct {
	JWTSecret         string // JWT 签名密钥
	EncryptionKey     string // AES-256 加密密钥（32 字节）
	DatabasePath      string // SQLite 数据库文件路径
	USDTTrc20Wallet   string // USDT TRC-20 收款地址
	TronProAPIKey     string // TronGrid Pro API Key（可选）
	USDTMinConfirm    int    // USDT 最小确认数
	TelegramBotToken  string // Telegram Bot Token
	TelegramChatID    string // Telegram Chat ID
	NowPaymentsAPIKey string // NOWPayments API Key
	NowPaymentsSecret string // NOWPayments IPN Secret（可选回调验证）
	NowPaymentsURL    string // NOWPayments API 基础 URL
	OneAPIURL         string // OneAPI 代理地址（如 http://oneapi-blue:3000）
	OneAPIKey         string // OneAPI 系统访问令牌
	GoogleClientID     string // Google OAuth Client ID
	GoogleClientSecret string // Google OAuth Client Secret
	GitHubClientID     string // GitHub OAuth Client ID
	GitHubClientSecret string // GitHub OAuth Client Secret
	PublicURL          string // 站点公开 URL（用于 OAuth 回调）
	FrontendURL        string // 前端 URL（OAuth 登入后重定向目标）
	MailgunDomain      string // Mailgun 发送域名
	MailgunAPIKey      string // Mailgun API Key
	EmailInboundSecret string // Worker → 后端的共享密钥
}

// Load 从环境变量加载配置
func Load() *Config {
	return &Config{
		JWTSecret:         getEnv("APP_JWT_SECRET", "dev-jwt-secret-change-in-production"),
		EncryptionKey:     getEnv("APP_ENCRYPTION_KEY", "0123456789abcdef0123456789abcdef"),
		DatabasePath:      getEnv("APP_DATABASE_PATH", "./data/app.db"),
		USDTTrc20Wallet:   getEnv("USDT_TRC20_WALLET", ""),
		TronProAPIKey:     getEnv("TRON_PRO_API_KEY", ""),
		USDTMinConfirm:    getEnvInt("USDT_MIN_CONFIRM", 12),
		TelegramBotToken:  getEnv("TELEGRAM_BOT_TOKEN", ""),
		TelegramChatID:    getEnv("TELEGRAM_CHAT_ID", ""),
		NowPaymentsAPIKey: getEnv("NOWPAYMENTS_API_KEY", ""),
		NowPaymentsSecret: getEnv("NOWPAYMENTS_IPN_SECRET", ""),
		NowPaymentsURL:    getEnv("NOWPAYMENTS_API_URL", "https://api.nowpayments.io/v1"),
		OneAPIURL:         getEnv("ONEAPI_URL", "http://localhost:3000"),
		OneAPIKey:         getEnv("ONEAPI_API_KEY", ""),
		GoogleClientID:     getEnv("GOOGLE_CLIENT_ID", ""),
		GoogleClientSecret: getEnv("GOOGLE_CLIENT_SECRET", ""),
		GitHubClientID:     getEnv("GITHUB_CLIENT_ID", ""),
		GitHubClientSecret: getEnv("GITHUB_CLIENT_SECRET", ""),
		PublicURL:          getEnv("PUBLIC_URL", "http://localhost:8082"),
		FrontendURL:        getEnv("FRONTEND_URL", "http://localhost:3000"),
		MailgunDomain:      getEnv("MAILGUN_DOMAIN", "aiflowhub.ai"),
		MailgunAPIKey:      getEnv("MAILGUN_API_KEY", ""),
		EmailInboundSecret: getEnv("EMAIL_INBOUND_SECRET", ""),
	}
}

func getEnv(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

func getEnvInt(key string, defaultVal int) int {
	if val := os.Getenv(key); val != "" {
		if n, err := strconv.Atoi(val); err == nil {
			return n
		}
	}
	return defaultVal
}
