package admin

import (
	"fmt"
	"log"
	"time"

	"github.com/gin-gonic/gin"
)

// ProviderBalance 供应商余额记录
type ProviderBalance struct {
	ID             int64   `json:"id"`
	Name           string  `json:"name"`
	Balance        float64 `json:"balance"`
	AlertThreshold float64 `json:"alert_threshold"`
	Notes          string  `json:"notes"`
	UpdatedAt      int64   `json:"updated_at"`
}

// ListProviders GET /admin/providers
func (h *Handler) ListProviders(c *gin.Context) {
	rows, err := h.db.Query(`
		SELECT id, name, balance, alert_threshold, notes, updated_at
		FROM provider_balances ORDER BY name`)
	if err != nil {
		c.JSON(500, gin.H{"error": "query failed"})
		return
	}
	defer rows.Close()

	var providers []ProviderBalance
	for rows.Next() {
		var p ProviderBalance
		if err := rows.Scan(&p.ID, &p.Name, &p.Balance, &p.AlertThreshold, &p.Notes, &p.UpdatedAt); err != nil {
			continue
		}
		providers = append(providers, p)
	}
	if providers == nil {
		providers = []ProviderBalance{}
	}

	c.JSON(200, gin.H{"providers": providers})
}

// UpdateProviderBalance PUT /admin/providers/:name/balance
// Body: {"balance": 500.0, "alert_threshold": 50}
func (h *Handler) UpdateProviderBalance(c *gin.Context) {
	name := c.Param("name")

	var req struct {
		Balance        *float64 `json:"balance"`
		AlertThreshold *float64 `json:"alert_threshold"`
		Notes          *string  `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "invalid request body"})
		return
	}

	now := time.Now().Unix()

	// 确保记录存在（不存在时创建默认记录）
	h.db.Exec(`INSERT OR IGNORE INTO provider_balances (name, balance, alert_threshold, notes, updated_at, created_at)
		VALUES (?, 0, 50, '', ?, ?)`, name, now, now)

	// 更新传入的字段
	if req.Balance != nil {
		h.db.Exec("UPDATE provider_balances SET balance = ?, updated_at = ? WHERE name = ?",
			*req.Balance, now, name)
	}
	if req.AlertThreshold != nil {
		h.db.Exec("UPDATE provider_balances SET alert_threshold = ?, updated_at = ? WHERE name = ?",
			*req.AlertThreshold, now, name)
	}
	if req.Notes != nil {
		h.db.Exec("UPDATE provider_balances SET notes = ?, updated_at = ? WHERE name = ?",
			*req.Notes, now, name)
	}

	// 返回更新后的记录
	var p ProviderBalance
	err := h.db.QueryRow(`
		SELECT id, name, balance, alert_threshold, notes, updated_at
		FROM provider_balances WHERE name = ?`, name).Scan(
		&p.ID, &p.Name, &p.Balance, &p.AlertThreshold, &p.Notes, &p.UpdatedAt)
	if err != nil {
		c.JSON(500, gin.H{"error": "read back failed"})
		return
	}

	log.Printf("[admin] Provider %s balance updated: $%.2f (threshold=$%.0f)", name, p.Balance, p.AlertThreshold)
	c.JSON(200, gin.H{"provider": p})
}

// AddProvider POST /admin/providers
// Body: {"name": "deepseek", "balance": 500.0, "alert_threshold": 100}
func (h *Handler) AddProvider(c *gin.Context) {
	var req struct {
		Name           string  `json:"name" binding:"required"`
		Balance        float64 `json:"balance"`
		AlertThreshold float64 `json:"alert_threshold"`
		Notes          string  `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}
	if req.AlertThreshold == 0 {
		req.AlertThreshold = 50
	}

	now := time.Now().Unix()
	_, err := h.db.Exec(`
		INSERT INTO provider_balances (name, balance, alert_threshold, notes, updated_at, created_at)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT(name) DO NOTHING`,
		req.Name, req.Balance, req.AlertThreshold, req.Notes, now, now)
	if err != nil {
		c.JSON(500, gin.H{"error": fmt.Sprintf("insert failed: %v", err)})
		return
	}

	c.JSON(201, gin.H{
		"name":            req.Name,
		"balance":         req.Balance,
		"alert_threshold": req.AlertThreshold,
	})
}

// DeleteProvider DELETE /admin/providers/:name
func (h *Handler) DeleteProvider(c *gin.Context) {
	name := c.Param("name")
	_, err := h.db.Exec("DELETE FROM provider_balances WHERE name = ?", name)
	if err != nil {
		c.JSON(500, gin.H{"error": "delete failed"})
		return
	}
	log.Printf("[admin] Provider %s deleted", name)
	c.JSON(200, gin.H{"deleted": true, "name": name})
}
