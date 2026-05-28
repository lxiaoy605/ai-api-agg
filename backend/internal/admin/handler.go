package admin

import (
	"database/sql"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"time"

	"github.com/ai-api-agg/backend/internal/audit"
	"github.com/ai-api-agg/backend/internal/middleware"
	"github.com/ai-api-agg/backend/internal/models"
	"github.com/gin-gonic/gin"
)

// Handler 管理 API 处理器
type Handler struct {
	db         *sql.DB
	projectDir string // 项目根目录（用于定位 scripts/ 和 channels/）
}

// NewHandler 创建管理 API 处理器
func NewHandler(db *sql.DB, projectDir string) *Handler {
	return &Handler{db: db, projectDir: projectDir}
}

// clientIP 获取客户端 IP
func clientIP(c *gin.Context) string {
	return c.ClientIP()
}

// Stats 系统统计 GET /api/stats
func (h *Handler) Stats(c *gin.Context) {
	var stats models.StatsResponse

	// 总用户数
	h.db.QueryRow("SELECT COUNT(*) FROM users").Scan(&stats.TotalUsers)

	// 24h 活跃用户（有最近使用的 API Key）
	cutoff := time.Now().Add(-24 * time.Hour).Unix()
	h.db.QueryRow(
		"SELECT COUNT(DISTINCT user_id) FROM api_keys WHERE last_used_at > ?",
		cutoff,
	).Scan(&stats.ActiveUsers24h)

	// 24h 请求数和 token 消耗
	h.db.QueryRow(
		"SELECT COALESCE(SUM(request_count), 0), COALESCE(SUM(token_count), 0) FROM usage_logs WHERE recorded_at > ?",
		cutoff,
	).Scan(&stats.TotalRequests24h, &stats.TotalTokens24h)

	middleware.Success(c, stats)
}

// Topup 管理员手动充值 POST /api/topup
func (h *Handler) Topup(c *gin.Context) {
	var req models.TopupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		middleware.BadRequest(c, "请提供 user_id 和 amount_cents")
		return
	}

	if req.AmountCents <= 0 {
		middleware.BadRequest(c, "充值金额必须大于0")
		return
	}

	// 检查用户是否存在
	var email string
	err := h.db.QueryRow("SELECT email FROM users WHERE id = ?", req.UserID).Scan(&email)
	if err == sql.ErrNoRows {
		middleware.NotFound(c, "用户不存在")
		return
	}
	if err != nil {
		middleware.InternalError(c, "查询用户失败")
		return
	}

	// 更新配额
	_, err = h.db.Exec("UPDATE users SET quota = quota + ?, updated_at = ? WHERE id = ?",
		req.AmountCents, time.Now().Unix(), req.UserID)
	if err != nil {
		middleware.InternalError(c, "充值失败")
		return
	}

	// 获取当前角色作为 actor
	actor := "admin:" + strconv.FormatInt(c.GetInt64("user_id"), 10)

	// 审计日志
	audit.Log(h.db, "topup", actor, "user:"+strconv.FormatInt(req.UserID, 10),
		"金额:"+strconv.FormatInt(req.AmountCents, 10)+"分 备注:"+req.Note, clientIP(c))

	middleware.Success(c, gin.H{
		"user_id":      req.UserID,
		"amount_cents": req.AmountCents,
		"note":         req.Note,
	})
}

// Channels 渠道状态 GET /api/channels
func (h *Handler) Channels(c *gin.Context) {
	configPath := filepath.Join(h.projectDir, "channels", "channel-configs.json")

	data, err := os.ReadFile(configPath)
	if err != nil {
		middleware.InternalError(c, "渠道配置文件读取失败")
		return
	}

	var config struct {
		Channels []map[string]interface{} `json:"channels"`
	}
	if err := json.Unmarshal(data, &config); err != nil {
		middleware.InternalError(c, "渠道配置解析失败")
		return
	}

	// 尝试读取故障日志
	type ChannelStatus struct {
		Name        string `json:"name"`
		BaseURL     string `json:"base_url"`
		Models      string `json:"models"`
		Status      string `json:"status"`
		Priority    int    `json:"priority"`
		Weight      int    `json:"weight"`
		FailoverNote string `json:"failover_note,omitempty"`
	}

	channels := make([]ChannelStatus, 0, len(config.Channels))
	for _, ch := range config.Channels {
		name, _ := ch["name"].(string)
		baseURL, _ := ch["base_url"].(string)
		models, _ := ch["models"].(string)
		status := "active"
		if s, ok := ch["status"].(float64); ok && s != 1 {
			status = "inactive"
		}
		priority := 0
		if p, ok := ch["priority"].(float64); ok {
			priority = int(p)
		}
		weight := 0
		if w, ok := ch["weight"].(float64); ok {
			weight = int(w)
		}

		channels = append(channels, ChannelStatus{
			Name:     name,
			BaseURL:  baseURL,
			Models:   models,
			Status:   status,
			Priority: priority,
			Weight:   weight,
		})
	}

	middleware.Success(c, channels)
}

// AuditLog 审计日志 GET /api/audit-log?limit=50&offset=0
func (h *Handler) AuditLog(c *gin.Context) {
	limitStr := c.DefaultQuery("limit", "50")
	offsetStr := c.DefaultQuery("offset", "0")

	limit, _ := strconv.Atoi(limitStr)
	offset, _ := strconv.Atoi(offsetStr)

	if limit <= 0 || limit > 200 {
		limit = 50
	}

	rows, err := h.db.Query(
		"SELECT id, timestamp, action, actor, target, details, ip FROM audit_log ORDER BY timestamp DESC LIMIT ? OFFSET ?",
		limit, offset,
	)
	if err != nil {
		middleware.InternalError(c, "查询审计日志失败")
		return
	}
	defer rows.Close()

	entries := make([]models.AuditEntry, 0)
	for rows.Next() {
		var entry models.AuditEntry
		if err := rows.Scan(&entry.ID, &entry.Timestamp, &entry.Action, &entry.Actor, &entry.Target, &entry.Details, &entry.IP); err != nil {
			middleware.InternalError(c, "读取审计日志失败")
			return
		}
		entries = append(entries, entry)
	}

	middleware.Success(c, entries)
}

// Backup 触发备份 POST /api/backup
func (h *Handler) Backup(c *gin.Context) {
	scriptPath := filepath.Join(h.projectDir, "scripts", "backup.sh")

	cmd := exec.Command("bash", scriptPath)
	cmd.Dir = h.projectDir
	output, err := cmd.CombinedOutput()
	if err != nil {
		middleware.InternalError(c, "备份失败: "+err.Error()+" 输出: "+string(output))
		return
	}

	// 从输出中提取备份文件名
	outputStr := string(output)

	// 查找最新备份文件
	backupDir := filepath.Join(h.projectDir, "backups")
	entries, err := os.ReadDir(backupDir)
	if err != nil {
		middleware.InternalError(c, "备份目录读取失败")
		return
	}

	var latestName string
	var latestTime time.Time
	for _, e := range entries {
		if e.IsDir() || e.Name() == "backup-latest.tar.gz" {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		if info.ModTime().After(latestTime) {
			latestTime = info.ModTime()
			latestName = e.Name()
		}
	}

	// 审计日志
	actor := "admin:" + strconv.FormatInt(c.GetInt64("user_id"), 10)
	audit.Log(h.db, "backup", actor, "system", "备份文件:"+latestName, clientIP(c))

	middleware.Success(c, gin.H{
		"backup_file": latestName,
		"output":      outputStr,
	})
}

// Restore 从备份恢复 POST /api/restore
func (h *Handler) Restore(c *gin.Context) {
	var req struct {
		BackupID string `json:"backup_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		middleware.BadRequest(c, "请提供 backup_id")
		return
	}

	scriptPath := filepath.Join(h.projectDir, "scripts", "restore.sh")

	// 非交互式恢复：管道传入 "yes"
	cmd := exec.Command("bash", scriptPath, req.BackupID)
	cmd.Dir = h.projectDir
	cmd.Stdin = nil // restore.sh 需要 stdin 传入 "yes"

	// 使用 echo yes 管道
	cmd = exec.Command("bash", "-c",
		"echo yes | bash "+scriptPath+" "+req.BackupID)
	cmd.Dir = h.projectDir
	output, err := cmd.CombinedOutput()
	if err != nil {
		middleware.InternalError(c, "恢复失败: "+err.Error()+" 输出: "+string(output))
		return
	}

	// 审计日志
	actor := "admin:" + strconv.FormatInt(c.GetInt64("user_id"), 10)
	audit.Log(h.db, "restore", actor, "system", "备份ID:"+req.BackupID, clientIP(c))

	middleware.Success(c, gin.H{
		"backup_id": req.BackupID,
		"output":    string(output),
	})
}
