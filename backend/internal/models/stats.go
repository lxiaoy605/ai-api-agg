package models

// StatsResponse 系统统计响应
type StatsResponse struct {
	TotalUsers       int64 `json:"total_users"`
	ActiveUsers24h   int64 `json:"active_users_24h"`
	TotalRequests24h int64 `json:"total_requests_24h"`
	TotalTokens24h   int64 `json:"total_tokens_24h"`
}

// TopupRequest 管理员手动充值请求
type TopupRequest struct {
	UserID      int64  `json:"user_id" binding:"required"`
	AmountCents int64  `json:"amount_cents" binding:"required"`
	Note        string `json:"note"`
}

// ChannelInfo 渠道信息
type ChannelInfo struct {
	Name     string `json:"name"`
	BaseURL  string `json:"base_url"`
	Models   string `json:"models"`
	Status   string `json:"status"`
	Priority int    `json:"priority"`
	Weight   int    `json:"weight"`
}
