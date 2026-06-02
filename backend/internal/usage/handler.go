package usage

import (
	"database/sql"
	"time"

	"github.com/ai-api-agg/backend/internal/middleware"
	"github.com/gin-gonic/gin"
)

// Handler 用量统计处理器
type Handler struct {
	db *sql.DB
}

// NewHandler 创建用量处理器
func NewHandler(db *sql.DB) *Handler {
	return &Handler{db: db}
}

// UsageItem 单个模型用量项
type UsageItem struct {
	ModelID       string  `json:"model_id"`
	ModelName     string  `json:"model_name"`
	WorkgroupID   int64   `json:"workgroup_id"`
	WorkgroupName string  `json:"workgroup_name"`
	Requests      int64   `json:"requests"`
	Tokens        int64   `json:"tokens"`
	Cost          float64 `json:"cost"`
	Percentage    float64 `json:"percentage"`
}

// WorkgroupSummary 工作组汇总
type WorkgroupSummary struct {
	ID       int64  `json:"id"`
	Name     string `json:"name"`
	KeyCount int    `json:"key_count"`
	Requests int64  `json:"requests"`
	Tokens   int64  `json:"tokens"`
	Cost     float64 `json:"cost"`
}

// DailyPoint 每日用量数据点
type DailyPoint struct {
	Date   string `json:"date"`
	WgID   int64  `json:"workgroup_id"`
	WgName string `json:"workgroup_name"`
	Req    int64  `json:"requests"`
	Tokens int64  `json:"tokens"`
}

// OverviewResponse GET /user/usage 响应
type OverviewResponse struct {
	TotalRequests int64              `json:"total_requests"`
	TotalTokens   int64              `json:"total_tokens"`
	TotalCost     float64            `json:"total_cost"`
	Workgroups    []WorkgroupSummary `json:"workgroups"`
	Models        []UsageItem        `json:"models"`
	Daily         []DailyPoint       `json:"daily"`
}

// Overview 聚合用量 GET /user/usage?period=month&wg=x
func (h *Handler) Overview(c *gin.Context) {
	userID := c.GetInt64("user_id")
	// period 和 wg 参数暂留用于未来扩展

	// 获取所有工作组汇总
	wgRows, err := h.db.Query(
		`SELECT w.id, w.name,
		        (SELECT COUNT(*) FROM api_keys k WHERE k.workgroup_id = w.id) as key_count,
		        COALESCE((SELECT SUM(u.request_count) FROM usage_logs u
		          JOIN api_keys k ON u.api_key_id = k.id WHERE k.workgroup_id = w.id), 0) as requests,
		        COALESCE((SELECT SUM(u.token_count) FROM usage_logs u
		          JOIN api_keys k ON u.api_key_id = k.id WHERE k.workgroup_id = w.id), 0) as tokens
		 FROM workgroups w
		 WHERE w.user_id = ?
		 ORDER BY tokens DESC`,
		userID,
	)
	if err != nil {
		middleware.InternalError(c, "Failed to query workgroup summary")
		return
	}
	defer wgRows.Close()

	var totalReq int64
	var totalTok int64
	workgroups := make([]WorkgroupSummary, 0)
	for wgRows.Next() {
		var s WorkgroupSummary
		if err := wgRows.Scan(&s.ID, &s.Name, &s.KeyCount, &s.Requests, &s.Tokens); err != nil {
			continue
		}
		// Cost 计算：$0.50/1M tokens (平均暂估，未来按模型细分)
		s.Cost = float64(s.Tokens) * 0.50 / 1_000_000
		totalReq += s.Requests
		totalTok += s.Tokens
		workgroups = append(workgroups, s)
	}

	// 按工作组+模型的使用明细
	modelItems := make([]UsageItem, 0)

	// 时序数据（最近 30 天）
	dailyPoints := h.buildDaily(userID)

	totalCost := float64(totalTok) * 0.50 / 1_000_000

	middleware.Success(c, OverviewResponse{
		TotalRequests: totalReq,
		TotalTokens:   totalTok,
		TotalCost:     totalCost,
		Workgroups:    workgroups,
		Models:        modelItems,
		Daily:         dailyPoints,
	})
}

// buildDaily 构建最近 30 天按工作组+日的用量
func (h *Handler) buildDaily(userID int64) []DailyPoint {
	cutoff := time.Now().Unix() - 30*86400

	rows, err := h.db.Query(
		`SELECT DATE(u.recorded_at, 'unixepoch') as day,
		        COALESCE(k.workgroup_id, 0) as wg_id,
		        COALESCE(w.name, 'Default') as wg_name,
		        SUM(u.request_count) as req,
		        SUM(u.token_count) as tokens
		 FROM usage_logs u
		 JOIN api_keys k ON u.api_key_id = k.id
		 LEFT JOIN workgroups w ON k.workgroup_id = w.id
		 WHERE k.user_id = ? AND u.recorded_at >= ?
		 GROUP BY day, k.workgroup_id
		 ORDER BY day ASC`,
		userID, cutoff,
	)
	if err != nil {
		return []DailyPoint{}
	}
	defer rows.Close()

	points := make([]DailyPoint, 0)
	for rows.Next() {
		var p DailyPoint
		if err := rows.Scan(&p.Date, &p.WgID, &p.WgName, &p.Req, &p.Tokens); err != nil {
			continue
		}
		points = append(points, p)
	}
	return points
}
