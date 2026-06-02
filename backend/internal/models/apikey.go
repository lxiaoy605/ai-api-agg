package models

// ApiKey API 密钥模型
type ApiKey struct {
	ID           int64   `json:"id"`
	UserID       int64   `json:"user_id"`
	Name         string  `json:"name"`
	KeyPrefix    string  `json:"key_prefix"`
	EncryptedKey string  `json:"-"` // 永远不暴露
	Status       string  `json:"status"`
	WorkgroupID  *int64  `json:"workgroup_id"`
	WorkgroupName string `json:"workgroup_name,omitempty"`
	CreatedAt    int64   `json:"created_at"`
	LastUsedAt   *int64  `json:"last_used_at"`
}

// CreateApiKeyRequest 创建 API Key 请求
type CreateApiKeyRequest struct {
	Name        string `json:"name"`
	WorkgroupID *int64 `json:"workgroup_id,omitempty"`
}

// CreateApiKeyResponse 创建 API Key 响应（含完整 Key，仅返回一次）
type CreateApiKeyResponse struct {
	ID        int64  `json:"id"`
	Name      string `json:"name"`
	Key       string `json:"key"` // 完整 Key，仅返回一次
	Prefix    string `json:"prefix"`
	CreatedAt int64  `json:"created_at"`
}

// UsageStats 用量统计
type UsageStats struct {
	TotalRequests int64 `json:"total_requests"`
	TotalTokens   int64 `json:"total_tokens"`
}
