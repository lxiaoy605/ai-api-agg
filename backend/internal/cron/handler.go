package cron

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/ai-api-agg/backend/internal/notify"
	"github.com/gin-gonic/gin"
)

// Handler 定时任务处理器（由外部 cron 触发）
type Handler struct {
	db *sql.DB
	es *notify.EmailSender
	tg *notify.Telegram // 可选：通知管理员
}

// NewHandler 创建定时任务处理器
func NewHandler(db *sql.DB, es *notify.EmailSender, tg *notify.Telegram) *Handler {
	return &Handler{db: db, es: es, tg: tg}
}

// checkCronAuth 验证 cron 端点的共享密钥
func (h *Handler) checkCronAuth(c *gin.Context) bool {
	secret := c.GetHeader("x-cron-secret")
	if secret == "" {
		secret = c.GetHeader("Authorization")
		secret = strings.TrimPrefix(secret, "Bearer ")
	}
	if secret == "" || secret != os.Getenv("CRON_SECRET") {
		c.JSON(401, gin.H{"error": "unauthorized"})
		return false
	}
	return true
}

// RunBalanceCheck 执行管理端余额扫描（不依赖 gin.Context，供调度器调用）
func (h *Handler) RunBalanceCheck() {
	const warnThreshold int64 = 100_000

	rows, err := h.db.Query(`
		SELECT id, email, tokens FROM users WHERE tokens <= ? AND tokens > 0
		ORDER BY tokens ASC`, warnThreshold)
	if err != nil {
		log.Printf("[cron/balance-check] Query failed: %v", err)
		return
	}
	defer rows.Close()

	type warnUser struct {
		id     int64
		email  string
		tokens int64
	}
	var users []warnUser
	for rows.Next() {
		var u warnUser
		if err := rows.Scan(&u.id, &u.email, &u.tokens); err != nil {
			continue
		}
		users = append(users, u)
	}

	if len(users) == 0 {
		return
	}

	warned := 0
	for _, u := range users {
		estimatedDays := int(u.tokens / 50_000)
		if estimatedDays < 0 {
			estimatedDays = 0
		}
		subject, html := notify.BuildBalanceWarningEmail(u.email, u.tokens, estimatedDays)
		if err := h.es.Send(u.email, subject, html); err != nil {
			log.Printf("[cron/balance-check] Send failed: %s %v", u.email, err)
			continue
		}
		warned++
	}

	log.Printf("[cron/balance-check] Done: %d warned, %d checked", warned, len(users))
}

// RunUserBalanceWarning 执行用户余额预警（不依赖 gin.Context）
func (h *Handler) RunUserBalanceWarning() {
	const lowTokenThreshold int64 = 25_000_000 // ≈ $5

	rows, err := h.db.Query(`
		SELECT DISTINCT u.id, u.email, u.tokens
		FROM users u
		INNER JOIN payment_log pl ON pl.user_id = u.id AND pl.status = 'completed'
		WHERE u.tokens > 0 AND u.tokens <= ?
		ORDER BY u.tokens ASC`, lowTokenThreshold)
	if err != nil {
		log.Printf("[cron/balance-warning] Query failed: %v", err)
		return
	}
	defer rows.Close()

	type warnUser struct {
		id     int64
		email  string
		tokens int64
	}
	var users []warnUser
	for rows.Next() {
		var u warnUser
		if err := rows.Scan(&u.id, &u.email, &u.tokens); err != nil {
			continue
		}
		users = append(users, u)
	}

	if len(users) == 0 {
		return
	}

	warned := 0
	for _, u := range users {
		estimatedDays := int(u.tokens / 50_000)
		if estimatedDays < 0 {
			estimatedDays = 0
		}
		subject, html := notify.BuildBalanceWarningEmail(u.email, u.tokens, estimatedDays)
		if err := h.es.Send(u.email, subject, html); err != nil {
			log.Printf("[cron/balance-warning] Send failed: %s %v", u.email, err)
			continue
		}
		warned++
	}

	log.Printf("[cron/balance-warning] Done: %d warned", warned)
}

// RunProviderCheck 执行供应商余额扫描（不依赖 gin.Context）
func (h *Handler) RunProviderCheck() {
	rows, err := h.db.Query(`
		SELECT name, balance, alert_threshold FROM provider_balances ORDER BY balance ASC`)
	if err != nil {
		log.Printf("[cron/provider-check] Query failed: %v", err)
		return
	}
	defer rows.Close()

	type prov struct {
		name      string
		balance   float64
		threshold float64
	}
	var providers []prov
	for rows.Next() {
		var p prov
		if err := rows.Scan(&p.name, &p.balance, &p.threshold); err != nil {
			continue
		}
		providers = append(providers, p)
	}

	if len(providers) == 0 {
		return
	}

	alerts := 0
	for _, p := range providers {
		level := 0
		if p.balance <= 10 {
			level = 3
		} else if p.balance <= 50 {
			level = 2
		} else if p.balance <= p.threshold || p.balance <= 100 {
			level = 1
		}
		if level == 0 {
			continue
		}

		msg := formatProviderAlert(p.name, p.balance, level)
		if h.tg.Enabled() {
			h.tg.Sendf("%s", msg)
		}
		if level >= 2 && h.es.Enabled() {
			subj := fmt.Sprintf("[CRITICAL] Provider %s balance: $%.2f", p.name, p.balance)
			body := fmt.Sprintf(`<p>Provider <strong>%s</strong> balance critically low:</p>
				<p style="font-size:24px;color:#ef4444">$%.2f</p>
				<p>Alert level: %d | Threshold: $%.0f</p>
				<p style="color:#666">Add funds immediately to avoid service interruption.</p>`,
				p.name, p.balance, level, p.threshold)
			h.es.Send("admin@aiflowhub.ai", subj, body)
		}
		alerts++
	}

	log.Printf("[cron/provider-check] Done: %d alerts", alerts)
}

// BalanceCheck 低余额管理预警 GET/POST /admin/cron/balance-check
// 扫描所有余额低于阈值的用户，批量发送预警邮件 + TG 通知管理员
func (h *Handler) BalanceCheck(c *gin.Context) {
	if !h.checkCronAuth(c) {
		return
	}
	h.RunBalanceCheck()
	c.JSON(200, gin.H{"checked": true})
}

// UserBalanceWarning 用户侧余额预警 GET /admin/cron/balance-warning
// 每分钟扫描已充值用户（有 payment_log 记录），余额 < $5 的发邮件通知
// 此端点仅发邮件，不发 Telegram
func (h *Handler) UserBalanceWarning(c *gin.Context) {
	if !h.checkCronAuth(c) {
		return
	}
	h.RunUserBalanceWarning()
	c.JSON(200, gin.H{"checked": true})
}

// ProviderCheck 供应商余额预警 GET /admin/cron/provider-check
// 三级阈值：< $100 Telegram, < $50 TG+Email, < $10 TG+Email+重复
func (h *Handler) ProviderCheck(c *gin.Context) {
	if !h.checkCronAuth(c) {
		return
	}
	h.RunProviderCheck()
	c.JSON(200, gin.H{"checked": true})
}

func formatProviderAlert(name string, balance float64, level int) string {
	icon := "🟡"
	label := "WARNING"
	switch level {
	case 2:
		icon = "🟠"
		label = "SEVERE"
	case 3:
		icon = "🔴"
		label = "CRITICAL"
	}
	return fmt.Sprintf("%s [%s] Provider `%s` balance: **$%.2f** (Level %d)\nAdd funds to avoid 502 errors for end users.",
		icon, label, name, balance, level)
}
