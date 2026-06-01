package proxy

import (
	"bufio"
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/ai-api-agg/backend/internal/apikey"
	"github.com/ai-api-agg/backend/internal/audit"
	"github.com/gin-gonic/gin"
)

// Handler 模型代理处理器
type Handler struct {
	db            *sql.DB
	encryptionKey []byte
	oneapiURL     string
	oneapiKey     string // OneAPI 系统访问令牌
}

// NewHandler 创建代理处理器
func NewHandler(db *sql.DB, encryptionKey, oneapiURL, oneapiKey string) *Handler {
	return &Handler{
		db:            db,
		encryptionKey: []byte(encryptionKey),
		oneapiURL:     strings.TrimRight(oneapiURL, "/"),
		oneapiKey:     oneapiKey,
	}
}

// ChatCompletions 处理 POST /v1/chat/completions
// 认证方式：Authorization: Bearer sk-...
func (h *Handler) ChatCompletions(c *gin.Context) {
	// 1. 提取并校验 API Key
	authHeader := c.GetHeader("Authorization")
	if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer sk-") {
		h.openAIError(c, http.StatusUnauthorized, "invalid_api_key",
			"Invalid API key. Use Authorization: Bearer sk-...")
		return
	}

	apiKeyStr := strings.TrimPrefix(authHeader, "Bearer ")

	// 2. 按前缀匹配活跃 key，逐一解密比对
	prefix := apiKeyStr[:12] + "..."
	rows, err := h.db.Query(
		"SELECT id, user_id, encrypted_key FROM api_keys WHERE key_prefix = ? AND status = 'active'",
		prefix,
	)
	if err != nil {
		h.openAIError(c, http.StatusInternalServerError, "server_error", "Internal error")
		return
	}
	defer rows.Close()

	var keyID, userID int64
	found := false

	for rows.Next() {
		var kid, uid int64
		var ek string
		if err := rows.Scan(&kid, &uid, &ek); err != nil {
			continue
		}
		plain, err := apikey.Decrypt(ek, h.encryptionKey)
		if err != nil {
			continue
		}
		if plain == apiKeyStr {
			keyID, userID, found = kid, uid, true
			break
		}
	}

	if !found {
		h.openAIError(c, http.StatusUnauthorized, "invalid_api_key", "Invalid API key")
		return
	}

	// 3. 检查用户配额
	var quota int64
	err = h.db.QueryRow("SELECT quota FROM users WHERE id = ?", userID).Scan(&quota)
	if err != nil {
		h.openAIError(c, http.StatusInternalServerError, "server_error", "Internal error")
		return
	}

	if quota <= 0 {
		h.openAIError(c, http.StatusTooManyRequests, "insufficient_quota",
			"You have exhausted your quota. Please top up to continue using AiFlowHub.")
		return
	}

	// 4. 读取请求体
	bodyBytes, err := io.ReadAll(c.Request.Body)
	if err != nil {
		h.openAIError(c, http.StatusBadRequest, "invalid_request", "Failed to read request body")
		return
	}

	// 判断是否 streaming
	var reqBody map[string]interface{}
	isStream := false
	if json.Unmarshal(bodyBytes, &reqBody) == nil {
		if s, ok := reqBody["stream"]; ok {
			if b, ok := s.(bool); ok {
				isStream = b
			}
		}
	}

	// 5. 转发到 OneAPI（用 OneAPI 自身的系统 token）
	oneapiReq, err := http.NewRequest("POST", h.oneapiURL+"/v1/chat/completions", bytes.NewReader(bodyBytes))
	if err != nil {
		h.openAIError(c, http.StatusInternalServerError, "server_error", "Failed to create proxy request")
		return
	}
	oneapiReq.Header.Set("Content-Type", "application/json")
	oneapiReq.Header.Set("Authorization", "Bearer "+h.oneapiKey)

	client := &http.Client{Timeout: 120 * time.Second}
	resp, err := client.Do(oneapiReq)
	if err != nil {
		h.openAIError(c, http.StatusBadGateway, "proxy_error",
			"Upstream model service is temporarily unavailable. Please try again later.")
		return
	}
	defer resp.Body.Close()

	// 6. 更新使用记录
	h.db.Exec("UPDATE api_keys SET last_used_at = ? WHERE id = ?", time.Now().Unix(), keyID)
	// 每次调用扣 1 配额（实际 token 计数后续完善）
	h.db.Exec("UPDATE users SET quota = quota - 1 WHERE id = ? AND quota > 0", userID)
	h.db.Exec(
		"INSERT INTO usage_logs (api_key_id, request_count, token_count, recorded_at) VALUES (?, 1, 0, ?)",
		keyID, time.Now().Unix(),
	)

	// 审计
	audit.Log(h.db, "proxy.call", fmt.Sprintf("key:%d user:%d", keyID, userID),
		fmt.Sprintf("stream=%v", isStream), "", c.ClientIP())

	// 7. 返回响应（支持 streaming）
	if isStream {
		h.proxyStream(c, resp)
	} else {
		h.proxyNonStream(c, resp)
	}
}

// proxyNonStream 非流式代理响应
func (h *Handler) proxyNonStream(c *gin.Context, resp *http.Response) {
	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		h.openAIError(c, http.StatusInternalServerError, "server_error", "Failed to read upstream response")
		return
	}
	for k, v := range resp.Header {
		for _, vv := range v {
			c.Header(k, vv)
		}
	}
	c.Data(resp.StatusCode, "application/json", bodyBytes)
}

// proxyStream 流式 SSE 代理
func (h *Handler) proxyStream(c *gin.Context, resp *http.Response) {
	c.Header("Content-Type", "text/event-stream")
	c.Header("Cache-Control", "no-cache")
	c.Header("Connection", "keep-alive")
	c.Header("X-Accel-Buffering", "no")
	c.Status(resp.StatusCode)

	reader := bufio.NewReader(resp.Body)
	flusher, ok := c.Writer.(http.Flusher)
	if !ok {
		return
	}

	buf := make([]byte, 4096)
	for {
		n, err := reader.Read(buf)
		if n > 0 {
			c.Writer.Write(buf[:n])
			flusher.Flush()
		}
		if err != nil {
			if err != io.EOF {
				return
			}
			break
		}
	}
}

// openAIError 返回 OpenAI 兼容格式的错误
func (h *Handler) openAIError(c *gin.Context, statusCode int, code, message string) {
	c.JSON(statusCode, gin.H{
		"error": gin.H{
			"message": message,
			"type":    code,
			"code":    code,
		},
	})
}
