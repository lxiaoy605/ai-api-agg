package apikey

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"fmt"
	"strconv"
	"time"

	"github.com/ai-api-agg/backend/internal/audit"
	"github.com/ai-api-agg/backend/internal/middleware"
	"github.com/ai-api-agg/backend/internal/models"
	"github.com/gin-gonic/gin"
)

// Handler API Key 管理处理器
type Handler struct {
	db            *sql.DB
	encryptionKey []byte
}

// NewHandler 创建 API Key 处理器
func NewHandler(db *sql.DB, encryptionKey string) *Handler {
	return &Handler{
		db:            db,
		encryptionKey: []byte(encryptionKey),
	}
}

// Create 创建 API Key POST /api-keys
func (h *Handler) Create(c *gin.Context) {
	userID := c.GetInt64("user_id")

	var req models.CreateApiKeyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		// allow empty name
		req.Name = ""
	}

	// 如果未指定工作组，使用用户的默认工作组
	wgID := req.WorkgroupID
	if wgID == nil {
		var defaultWgID int64
		err := h.db.QueryRow("SELECT id FROM workgroups WHERE user_id = ? ORDER BY id LIMIT 1", userID).Scan(&defaultWgID)
		if err == nil {
			wgID = &defaultWgID
		}
	}

	// 如果指定了工作组，验证归属权
	if wgID != nil {
		var ownerID int64
		err := h.db.QueryRow("SELECT user_id FROM workgroups WHERE id = ?", *wgID).Scan(&ownerID)
		if err == sql.ErrNoRows {
			middleware.BadRequest(c, "Workgroup not found")
			return
		}
		if ownerID != userID {
			middleware.BadRequest(c, "Workgroup does not belong to current user")
			return
		}
	}

	// 生成随机 Key
	fullKey, err := generateAPIKey()
	if err != nil {
		middleware.InternalError(c, "Failed to generate key")
		return
	}

	// AES-256-GCM 加密
	encryptedKey, err := encrypt(fullKey, h.encryptionKey)
	if err != nil {
		middleware.InternalError(c, "Failed to encrypt key")
		return
	}

	// 计算前缀（用于列表展示）
	prefix := fullKey[:12] + "..."

	now := time.Now().Unix()
	result, err := h.db.Exec(
		"INSERT INTO api_keys (user_id, name, key_prefix, encrypted_key, status, workgroup_id, created_at) VALUES (?, ?, ?, ?, 'active', ?, ?)",
		userID, req.Name, prefix, encryptedKey, wgID, now,
	)
	if err != nil {
		middleware.InternalError(c, "Failed to create key")
		return
	}

	keyID, _ := result.LastInsertId()

	// 审计日志
	actor := "user:" + strconv.FormatInt(userID, 10)
	audit.Log(h.db, "apikey.create", actor, "key:"+strconv.FormatInt(keyID, 10),
		"name:"+req.Name, c.ClientIP())

	middleware.Success(c, models.CreateApiKeyResponse{
		ID:        keyID,
		Name:      req.Name,
		Key:       fullKey, // 仅此一次返回完整 Key
		Prefix:    prefix,
		CreatedAt: now,
	})
}

// List 列出用户的 Key GET /api-keys
func (h *Handler) List(c *gin.Context) {
	userID := c.GetInt64("user_id")

	rows, err := h.db.Query(
		`SELECT k.id, k.user_id, k.name, k.key_prefix, k.status, k.workgroup_id,
		        COALESCE(w.name, ''), k.created_at, k.last_used_at
		 FROM api_keys k
		 LEFT JOIN workgroups w ON k.workgroup_id = w.id
		 WHERE k.user_id = ?
		 ORDER BY k.created_at DESC`,
		userID,
	)
	if err != nil {
		middleware.InternalError(c, "Failed to list keys")
		return
	}
	defer rows.Close()

	keys := make([]models.ApiKey, 0)
	for rows.Next() {
		var key models.ApiKey
		if err := rows.Scan(&key.ID, &key.UserID, &key.Name, &key.KeyPrefix, &key.Status, &key.WorkgroupID, &key.WorkgroupName, &key.CreatedAt, &key.LastUsedAt); err != nil {
			middleware.InternalError(c, "Failed to read key data")
			return
		}
		keys = append(keys, key)
	}

	middleware.Success(c, keys)
}

// Delete 删除 Key DELETE /api-keys/:id
func (h *Handler) Delete(c *gin.Context) {
	userID := c.GetInt64("user_id")
	keyID := c.Param("id")

	// 验证归属权
	var ownerID int64
	err := h.db.QueryRow("SELECT user_id FROM api_keys WHERE id = ?", keyID).Scan(&ownerID)
	if err == sql.ErrNoRows {
		middleware.NotFound(c, "Key not found")
		return
	}
	if err != nil {
		middleware.InternalError(c, "Failed to query key")
		return
	}

	if ownerID != userID {
		middleware.NotFound(c, "Key not found")
		return
	}

	if _, err := h.db.Exec("DELETE FROM api_keys WHERE id = ?", keyID); err != nil {
		middleware.InternalError(c, "Failed to delete key")
		return
	}

	// 审计日志
	actor := "user:" + strconv.FormatInt(userID, 10)
	audit.Log(h.db, "apikey.delete", actor, "key:"+keyID,
		"", c.ClientIP())

	middleware.Success(c, gin.H{"deleted": true})
}

// Toggle 切换状态 PATCH /api-keys/:id/toggle
func (h *Handler) Toggle(c *gin.Context) {
	userID := c.GetInt64("user_id")
	keyID := c.Param("id")

	var ownerID int64
	var currentStatus string
	err := h.db.QueryRow("SELECT user_id, status FROM api_keys WHERE id = ?", keyID).Scan(&ownerID, &currentStatus)
	if err == sql.ErrNoRows {
		middleware.NotFound(c, "Key not found")
		return
	}
	if err != nil {
		middleware.InternalError(c, "Failed to query key")
		return
	}
	if ownerID != userID {
		middleware.NotFound(c, "Key not found")
		return
	}

	newStatus := "disabled"
	if currentStatus == "disabled" {
		newStatus = "active"
	}

	if _, err := h.db.Exec("UPDATE api_keys SET status = ? WHERE id = ?", newStatus, keyID); err != nil {
		middleware.InternalError(c, "Failed to toggle key status")
		return
	}

	middleware.Success(c, gin.H{"id": keyID, "status": newStatus})
}

// Usage 用量统计 GET /api-keys/:id/usage
func (h *Handler) Usage(c *gin.Context) {
	userID := c.GetInt64("user_id")
	keyID := c.Param("id")

	// 验证归属权
	var ownerID int64
	err := h.db.QueryRow("SELECT user_id FROM api_keys WHERE id = ?", keyID).Scan(&ownerID)
	if err == sql.ErrNoRows {
		middleware.NotFound(c, "Key not found")
		return
	}
	if err != nil {
		middleware.InternalError(c, "Failed to query key")
		return
	}

	if ownerID != userID {
		middleware.NotFound(c, "Key not found")
		return
	}

	// 从 usage_logs 聚合用量数据（如果没有真实数据，返回零值）
	var stats models.UsageStats
	err = h.db.QueryRow(
		"SELECT COALESCE(SUM(request_count), 0), COALESCE(SUM(token_count), 0) FROM usage_logs WHERE api_key_id = ?",
		keyID,
	).Scan(&stats.TotalRequests, &stats.TotalTokens)
	if err != nil {
		middleware.InternalError(c, "Failed to query usage")
		return
	}

	middleware.Success(c, stats)
}

// generateAPIKey 生成随机 API Key（格式：sk- + 64 位 hex）
func generateAPIKey() (string, error) {
	bytes := make([]byte, 32) // 256 bits
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return "sk-" + hex.EncodeToString(bytes), nil
}

// encrypt 使用 AES-256-GCM 加密明文
func encrypt(plaintext string, key []byte) (string, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	nonce := make([]byte, gcm.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return "", err
	}

	ciphertext := gcm.Seal(nonce, nonce, []byte(plaintext), nil)
	return hex.EncodeToString(ciphertext), nil
}

// Decrypt 使用 AES-256-GCM 解密密文
func Decrypt(cipherHex string, key []byte) (string, error) {
	ciphertext, err := hex.DecodeString(cipherHex)
	if err != nil {
		return "", err
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	nonceSize := gcm.NonceSize()
	if len(ciphertext) < nonceSize {
		return "", fmt.Errorf("Ciphertext too short")
	}

	nonce, ciphertext := ciphertext[:nonceSize], ciphertext[nonceSize:]
	plaintext, err := gcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return "", err
	}

	return string(plaintext), nil
}
