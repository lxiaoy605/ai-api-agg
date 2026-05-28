package payment

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/ai-api-agg/backend/internal/audit"
	"github.com/ai-api-agg/backend/internal/middleware"
	"github.com/gin-gonic/gin"
)

// ========== 处理器 ==========

// Handler 支付 HTTP 处理器
type Handler struct {
	db     *sql.DB
	client *Client
}

// NewHandler 创建支付处理器
func NewHandler(db *sql.DB, apiKey, ipnSecret, baseURL string) *Handler {
	return &Handler{
		db:     db,
		client: NewClient(apiKey, ipnSecret, baseURL),
	}
}

// ========== 请求/响应类型 ==========

// CreatePaymentReq 创建支付请求
type CreatePaymentReq struct {
	AmountCents int    `json:"amount_cents" binding:"required,min=500"`
	PayCurrency string `json:"pay_currency"`
}

// CurrencyItem 前端币种展示
type CurrencyItem struct {
	Code     string `json:"code"`
	Name     string `json:"name"`
	Network  string `json:"network"`
	LogoURL  string `json:"logo_url"`
	Precision int  `json:"precision"`
}

// PaymentInfo 支付信息（返回前端）
type PaymentInfo struct {
	PaymentID     int64   `json:"payment_id"`
	OrderID       string  `json:"order_id"`
	Status        string  `json:"status"`
	PayAddress    string  `json:"pay_address"`
	PayAmount     float64 `json:"pay_amount"`
	PayCurrency   string  `json:"pay_currency"`
	Network       string  `json:"network"`
	PriceAmount   float64 `json:"price_amount"`
	Tokens        int64   `json:"tokens"`
	Bonus         int64   `json:"bonus"`
	ExpiresAt     int64   `json:"expires_at"`
}

// ========== 端点 ==========

// CreatePayment POST /api/payment/create（需要 JWT）
func (h *Handler) CreatePayment(c *gin.Context) {
	userID := c.GetInt64("user_id")

	var req CreatePaymentReq
	if err := c.ShouldBindJSON(&req); err != nil {
		middleware.BadRequest(c, "请提供有效金额（最低 $5.00）")
		return
	}

	if h.client.apiKey == "" {
		middleware.InternalError(c, "支付服务未配置")
		return
	}

	// 默认币种
	payCurrency := req.PayCurrency
	if payCurrency == "" {
		payCurrency = "usdttrc20"
	}

	// 生成订单号
	orderID := fmt.Sprintf("NP-%d-%d", userID, time.Now().UnixMilli())
	priceAmount := float64(req.AmountCents) / 100.0
	description := fmt.Sprintf("AI API Top-up - $%.2f", priceAmount)

	ipnURL := getEnvOrDefault("NOWPAYMENTS_IPN_URL", "")
	successURL := getEnvOrDefault("NOWPAYMENTS_SUCCESS_URL", "")
	cancelURL := getEnvOrDefault("NOWPAYMENTS_CANCEL_URL", "")

	// 调用 NOWPayments 创建支付
	npResp, err := h.client.CreatePayment(priceAmount, payCurrency, orderID, description, ipnURL, successURL, cancelURL)
	if err != nil {
		log.Printf("[支付] 创建支付失败: user=%d amount=%.2f err=%v", userID, priceAmount, err)
		middleware.InternalError(c, "创建支付失败，请稍后重试")
		return
	}

	// 计算 token 和 bonus
	tokens := int64(float64(req.AmountCents) / getCentsPerToken())
	bonus := calculateBonus(req.AmountCents)
	totalTokens := tokens + bonus

	// 写入 payment_log
	now := time.Now().Unix()
	paymentIDStr := strconv.FormatInt(npResp.PaymentID, 10)
	_, dbErr := h.db.Exec(`
		INSERT INTO payment_log (user_id, payment_id, provider, amount_cents, currency, tokens, bonus, status, memo, created_at, updated_at)
		VALUES (?, ?, 'nowpayments', ?, 'USD', ?, ?, 'waiting', ?, ?, ?)`,
		userID, paymentIDStr, req.AmountCents, totalTokens, bonus, orderID, now, now)
	if dbErr != nil {
		log.Printf("[支付] 写入 payment_log 失败: %v", dbErr)
	}

	// 审计日志
	audit.Log(h.db, "payment_create", fmt.Sprintf("user:%d", userID), paymentIDStr,
		fmt.Sprintf("金额:$%.2f Token:%d 币种:%s 状态:%s", priceAmount, totalTokens, payCurrency, npResp.PaymentStatus), "")

	middleware.Success(c, PaymentInfo{
		PaymentID:   npResp.PaymentID,
		OrderID:     orderID,
		Status:      npResp.PaymentStatus,
		PayAddress:  npResp.PayAddress,
		PayAmount:   npResp.PayAmount,
		PayCurrency: npResp.PayCurrency,
		Network:     npResp.Network,
		PriceAmount: npResp.PriceAmount,
		Tokens:      totalTokens,
		Bonus:       bonus,
		ExpiresAt:   now + 3600, // 1 小时过期
	})
}

// PaymentStatus GET /api/payment/status/:payment_id（需要 JWT）
func (h *Handler) PaymentStatus(c *gin.Context) {
	paymentID := c.Param("payment_id")
	if paymentID == "" {
		middleware.BadRequest(c, "缺少 payment_id")
		return
	}

	// 查询 NOWPayments 最新状态
	npResp, err := h.client.GetPaymentStatus(paymentID)
	if err != nil {
		log.Printf("[支付] 查询状态失败: payment_id=%s err=%v", paymentID, err)
		middleware.InternalError(c, "查询支付状态失败")
		return
	}

	// 检查本地记录是否需要更新
	if npResp.PaymentStatus == "finished" || npResp.PaymentStatus == "confirmed" {
		h.tryCompletePayment(paymentID, npResp)
	}

	middleware.Success(c, gin.H{
		"payment_id":     npResp.PaymentID,
		"order_id":       npResp.OrderID,
		"status":         npResp.PaymentStatus,
		"pay_address":    npResp.PayAddress,
		"pay_amount":     npResp.PayAmount,
		"pay_currency":   npResp.PayCurrency,
		"network":        npResp.Network,
		"price_amount":   npResp.PriceAmount,
		"price_currency": npResp.PriceCurrency,
	})
}

// Currencies GET /api/payment/currencies（无需认证）
func (h *Handler) Currencies(c *gin.Context) {
	// 优先从 NOWPayments 获取
	if h.client.apiKey != "" {
		currencies, err := h.client.GetCurrencies()
		if err != nil {
			log.Printf("[支付] 获取币种列表失败: %v", err)
		} else {
			var items []CurrencyItem
			for _, cur := range currencies {
				items = append(items, CurrencyItem{
					Code:      cur.Code,
					Name:      cur.Name,
					Network:   cur.Network,
					LogoURL:   cur.LogoURL,
					Precision: cur.Precision,
				})
			}
			middleware.Success(c, items)
			return
		}
	}

	// fallback：返回常用币种
	fallback := []CurrencyItem{
		{Code: "usdttrc20", Name: "USDT-TRC20", Network: "trc20", Precision: 6},
		{Code: "usdterc20", Name: "USDT-ERC20", Network: "erc20", Precision: 6},
		{Code: "usdtbep20", Name: "USDT-BEP20", Network: "bep20", Precision: 6},
		{Code: "trx", Name: "TRX", Network: "trc20", Precision: 6},
	}
	middleware.Success(c, fallback)
}

// Webhook POST /api/payment/webhook（IPN 回调，无需 JWT）
func (h *Handler) Webhook(c *gin.Context) {
	// 读取原始 body 用于签名验证
	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		log.Printf("[支付] IPN 读取 body 失败: %v", err)
		c.JSON(400, gin.H{"error": "invalid body"})
		return
	}

	// 验证 IPN 签名
	sigHeader := c.GetHeader("x-nowpayments-sig")
	if !h.client.VerifyIPNSignature(body, sigHeader) {
		log.Printf("[支付] IPN 签名验证失败")
		c.JSON(400, gin.H{"error": "invalid signature"})
		return
	}

	var ipnData PaymentResponse
	if err := json.Unmarshal(body, &ipnData); err != nil {
		log.Printf("[支付] IPN 解析 body 失败: %v", err)
		c.JSON(400, gin.H{"error": "invalid body"})
		return
	}

	log.Printf("[支付] IPN 回调: payment_id=%d order_id=%s status=%s",
		ipnData.PaymentID, ipnData.OrderID, ipnData.PaymentStatus)

	paymentIDStr := strconv.FormatInt(ipnData.PaymentID, 10)
	h.tryCompletePayment(paymentIDStr, &ipnData)

	c.JSON(200, gin.H{"status": "ok"})
}

// ========== 内部方法 ==========

// tryCompletePayment 如果支付已完成且在本地未处理，自动为用户充值
func (h *Handler) tryCompletePayment(paymentID string, npResp *PaymentResponse) {
	// 查询本地记录状态
	var localStatus string
	var userID, amountCents, tokens, bonus int64
	err := h.db.QueryRow(
		"SELECT user_id, amount_cents, tokens, bonus, status FROM payment_log WHERE payment_id = ?",
		paymentID,
	).Scan(&userID, &amountCents, &tokens, &bonus, &localStatus)

	if err == sql.ErrNoRows {
		log.Printf("[支付] 未找到本地记录: payment_id=%s", paymentID)
		return
	}
	if err != nil {
		log.Printf("[支付] 查询本地记录失败: %v", err)
		return
	}

	// 已处理过，跳过
	if localStatus == "completed" {
		return
	}

	isFinished := npResp.PaymentStatus == "finished"

	// 更新 payment_log 状态
	now := time.Now().Unix()
	newStatus := mapStatus(npResp.PaymentStatus)
	completedAt := int64(0)
	if isFinished {
		completedAt = now
	}

	_, err = h.db.Exec(
		"UPDATE payment_log SET status = ?, updated_at = ?, completed_at = ? WHERE payment_id = ? AND status != 'completed'",
		newStatus, now, completedAt, paymentID)
	if err != nil {
		log.Printf("[支付] 更新 payment_log 失败: %v", err)
		return
	}

	// 只有 finished 状态才增加用户额度
	if isFinished {
		tx, err := h.db.Begin()
		if err != nil {
			log.Printf("[支付] 开启事务失败: %v", err)
			return
		}

		_, err = tx.Exec("UPDATE users SET quota = quota + ?, updated_at = ? WHERE id = ?",
			tokens, now, userID)
		if err != nil {
			log.Printf("[支付] 更新用户额度失败: %v", err)
			_ = tx.Rollback()
			return
		}

		if err := tx.Commit(); err != nil {
			log.Printf("[支付] 提交事务失败: %v", err)
			return
		}

		// 审计日志
		audit.Log(h.db, "payment_complete", fmt.Sprintf("user:%d", userID), paymentID,
			fmt.Sprintf("金额:$%.2f Token:%d(+%d) 状态:%s", float64(amountCents)/100.0, tokens, bonus, npResp.PaymentStatus), "")

		log.Printf("[支付] 自动到账: user=%d amount=$%.2f tokens=%d(+%d) payment_id=%s",
			userID, float64(amountCents)/100.0, tokens, bonus, paymentID)
	}
}

// ========== 辅助函数 ==========

// mapStatus 将 NOWPayments 状态映射为本地状态
func mapStatus(npStatus string) string {
	switch npStatus {
	case "finished":
		return "completed"
	case "failed", "expired":
		return "failed"
	case "refunded":
		return "refunded"
	case "partially_paid":
		return "pending"
	default:
		// waiting, confirming, confirmed, sending
		return npStatus
	}
}

// calculateBonus 根据充值金额计算赠送 Token
func calculateBonus(amountCents int) int64 {
	centsPerToken := getCentsPerToken()
	baseTokens := float64(amountCents) / centsPerToken
	usdAmount := float64(amountCents) / 100.0
	switch {
	case usdAmount >= 100:
		return int64(baseTokens * 20 / 100)
	case usdAmount >= 50:
		return int64(baseTokens * 15 / 100)
	case usdAmount >= 25:
		return int64(baseTokens * 10 / 100)
	case usdAmount >= 10:
		return int64(baseTokens * 5 / 100)
	default:
		return 0
	}
}

// getCentsPerToken 每 token 成本（美分），$0.01 = 1 cent → 100 tokens per $1
func getCentsPerToken() float64 {
	if val := os.Getenv("USDT_CENTS_PER_TOKEN"); val != "" {
		if f, err := strconv.ParseFloat(val, 64); err == nil && !math.IsNaN(f) {
			return f
		}
	}
	return 0.01
}

func getEnvOrDefault(key, defaultVal string) string {
	if val := strings.TrimSpace(os.Getenv(key)); val != "" {
		return val
	}
	return defaultVal
}
