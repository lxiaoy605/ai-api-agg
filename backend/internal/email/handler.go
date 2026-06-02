package email

import (
	"bytes"
	"crypto/subtle"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/ai-api-agg/backend/internal/middleware"
	"github.com/gin-gonic/gin"
)

// Handler 邮件模块处理器
type Handler struct {
	db         *sql.DB
	dataDir    string
	inbSecret  string
	mgDomain   string
	mgAPIKey   string
	mgAPIBase  string
	tgNotifier interface{ Send(string) } // 通知接口
}

// NewHandler 创建邮件处理器
func NewHandler(db *sql.DB, dataDir string, tgNotifier interface{ Send(string) }) *Handler {
	mgDomain := os.Getenv("MAILGUN_DOMAIN")
	if mgDomain == "" {
		mgDomain = "aiflowhub.ai"
	}
	return &Handler{
		db:         db,
		dataDir:    dataDir,
		inbSecret:  os.Getenv("EMAIL_INBOUND_SECRET"),
		mgDomain:   mgDomain,
		mgAPIKey:   os.Getenv("MAILGUN_API_KEY"),
		mgAPIBase:  "https://api.eu.mailgun.net/v3",
		tgNotifier: tgNotifier,
	}
}

// InboundAuth 检查入站密钥
func (h *Handler) InboundAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		if h.inbSecret == "" {
			middleware.InternalError(c, "inbound secret not configured")
			c.Abort()
			return
		}
		auth := c.GetHeader("Authorization")
		expected := "Bearer " + h.inbSecret
		if subtle.ConstantTimeCompare([]byte(auth), []byte(expected)) != 1 {
			middleware.Unauthorized(c, "invalid inbound secret")
			c.Abort()
			return
		}
		c.Next()
	}
}

// Receive 接收 Worker 转发来的邮件并存储
func (h *Handler) Receive(c *gin.Context) {
	var req InboundRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		middleware.BadRequest(c, "invalid request body: "+err.Error())
		return
	}

	now := time.Now().Unix()
	monthDir := time.Now().Format("2006-01")
	emailDir := filepath.Join(h.dataDir, "emails", monthDir)
	if err := os.MkdirAll(emailDir, 0755); err != nil {
		middleware.InternalError(c, "创建邮件目录失败")
		return
	}

	// 保存 .eml 文件
	emlName := sanitizeMessageID(req.MessageID) + ".eml"
	emlPath := filepath.Join(emailDir, emlName)
	if req.RawEML != "" {
		if err := os.WriteFile(emlPath, []byte(req.RawEML), 0644); err != nil {
			log.Printf("[email] 保存 .eml 失败: %v", err)
		}
	}

	// 写入 SQLite
	res, err := h.db.Exec(
		`INSERT INTO emails (message_id, "from", "to", subject, body_text, body_html, attach_count, eml_path, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		req.MessageID, req.From, req.To,
		truncateForDB(req.Subject, 500),
		req.BodyText, req.BodyHTML, req.AttachCount,
		emlPath, now,
	)
	if err != nil {
		log.Printf("[email] 写入数据库失败: %v", err)
		middleware.InternalError(c, "保存邮件失败")
		return
	}

	emailID, _ := res.LastInsertId()
	log.Printf("[email] 已接收 #%d: %s — %s", emailID, req.Subject, req.From)

	// 异步提取附件
	go func() {
		attachDir := filepath.Join(h.dataDir, "attachments", monthDir, fmt.Sprintf("%d", emailID))
		n, warns := extractAttachments(emlPath, attachDir, emailID)
		for _, w := range warns {
			log.Printf("[email] 附件警告 #%d: %s", emailID, w)
		}
		if n > 0 {
			if _, err := h.db.Exec(`UPDATE emails SET attach_count = ? WHERE id = ?`, n, emailID); err != nil {
				log.Printf("[email] 更新 attach_count #%d 失败: %v", emailID, err)
			}
		}
	}()

	middleware.Success(c, gin.H{"id": emailID, "stored": true})

	// 关键词监听（异步，不阻塞响应）
	go h.checkKeywords(req)
}

// ReceiveRaw 接收原始 EML（Worker 极简模式），后端完成全部解析
func (h *Handler) ReceiveRaw(c *gin.Context) {
	raw, err := io.ReadAll(c.Request.Body)
	if err != nil || len(raw) < 50 {
		middleware.BadRequest(c, "empty or invalid raw email")
		return
	}

	parsed := ParseRawEML(string(raw))
	if parsed == nil {
		middleware.BadRequest(c, "failed to parse email")
		return
	}

	now := time.Now().Unix()
	monthDir := time.Now().Format("2006-01")
	emailDir := filepath.Join(h.dataDir, "emails", monthDir)
	os.MkdirAll(emailDir, 0755)

	// 保存 .eml
	emlName := sanitizeMessageID(parsed.MessageID) + ".eml"
	emlPath := filepath.Join(emailDir, emlName)
	os.WriteFile(emlPath, raw, 0644)

	from := strings.Join(parsed.From, ", ")
	to := strings.Join(parsed.To, ", ")

	res, err := h.db.Exec(
		`INSERT INTO emails (message_id, "from", "to", subject, body_text, body_html, attach_count, eml_path, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		parsed.MessageID, from, to,
		truncateForDB(parsed.Subject, 500),
		parsed.BodyText, parsed.BodyHTML, parsed.AttachCount,
		emlPath, now,
	)
	if err != nil {
		log.Printf("[email] 写入数据库失败: %v", err)
		middleware.InternalError(c, "保存邮件失败")
		return
	}

	emailID, _ := res.LastInsertId()
	log.Printf("[email] 已接收 #%d: %s — %s", emailID, parsed.Subject, from)

	// 异步提取附件
	go func() {
		attachDir := filepath.Join(h.dataDir, "attachments", monthDir, fmt.Sprintf("%d", emailID))
		n, warns := extractAttachments(emlPath, attachDir, emailID)
		for _, w := range warns {
			log.Printf("[email] 附件警告 #%d: %s", emailID, w)
		}
		if n > 0 {
			if _, err := h.db.Exec(`UPDATE emails SET attach_count = ? WHERE id = ?`, n, emailID); err != nil {
				log.Printf("[email] 更新 attach_count #%d 失败: %v", emailID, err)
			}
		}
	}()

	// 异步 Telegram 通知
	go h.notifyNewEmail(parsed, emailID)

	middleware.Success(c, gin.H{"id": emailID, "stored": true})
}

// notifyNewEmail 发送新邮件 Telegram 通知
func (h *Handler) notifyNewEmail(e *ParsedEmail, emailID int64) {
	if h.tgNotifier == nil {
		return
	}
	tg, ok := h.tgNotifier.(interface{ Send(string) })
	if !ok || tg == nil {
		return
	}

	from := strings.Join(e.From, ", ")
	to := strings.Join(e.To, ", ")

	body := e.BodyText
	if body == "" && e.BodyHTML != "" {
		body = stripHTML(e.BodyHTML)
	}

	lines := []string{}
	lines = append(lines, fmt.Sprintf("📧 <b>%s</b>", escapeHTML(truncateStr(e.Subject, 100))))
	lines = append(lines, fmt.Sprintf("<b>From:</b> %s", escapeHTML(truncateStr(from, 80))))
	lines = append(lines, fmt.Sprintf("<b>To:</b> %s", escapeHTML(truncateStr(to, 80))))
	if e.AttachCount > 0 {
		lines = append(lines, fmt.Sprintf("<b>附件:</b> %d 个", e.AttachCount))
	}
	lines = append(lines, "")
	lines = append(lines, escapeHTML(truncateStr(body, 1500)))
	lines = append(lines, "")
	lines = append(lines, fmt.Sprintf("/emails_show_%d", emailID))

	tg.Send(strings.Join(lines, "\n"))
}

func escapeHTML(s string) string {
	s = strings.ReplaceAll(s, "&", "&amp;")
	s = strings.ReplaceAll(s, "<", "&lt;")
	s = strings.ReplaceAll(s, ">", "&gt;")
	return s
}

func truncateStr(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max] + "…"
}

// List 列出最近邮件
func (h *Handler) List(c *gin.Context) {
	limit := 20
	if l, err := strconv.Atoi(c.DefaultQuery("limit", "20")); err == nil && l > 0 && l <= 100 {
		limit = l
	}
	offset := 0
	if o, err := strconv.Atoi(c.DefaultQuery("offset", "0")); err == nil && o >= 0 {
		offset = o
	}

	rows, err := h.db.Query(
		`SELECT id, message_id, "from", "to", subject, body_text, eml_path, attach_count, created_at
		 FROM emails ORDER BY created_at DESC LIMIT ? OFFSET ?`,
		limit, offset,
	)
	if err != nil {
		middleware.InternalError(c, "查询失败")
		return
	}
	defer rows.Close()

	var emails []Email
	for rows.Next() {
		var e Email
		if err := rows.Scan(&e.ID, &e.MessageID, &e.From, &e.To, &e.Subject,
			&e.BodyText, &e.EmlPath, &e.AttachCount, &e.CreatedAt); err != nil {
			continue
		}
		emails = append(emails, e)
	}

	// 总数
	var total int
	h.db.QueryRow("SELECT COUNT(*) FROM emails").Scan(&total)

	middleware.Success(c, gin.H{"emails": emails, "total": total, "limit": limit, "offset": offset})
}

// Search 搜索邮件
func (h *Handler) Search(c *gin.Context) {
	q := strings.TrimSpace(c.Query("q"))
	if q == "" {
		middleware.BadRequest(c, "缺少搜索词 q")
		return
	}

	like := "%" + q + "%"
	rows, err := h.db.Query(
		`SELECT id, message_id, "from", "to", subject, body_text, eml_path, attach_count, created_at
		 FROM emails
		 WHERE subject LIKE ? OR body_text LIKE ? OR "from" LIKE ? OR "to" LIKE ?
		 ORDER BY created_at DESC LIMIT 50`,
		like, like, like, like,
	)
	if err != nil {
		middleware.InternalError(c, "搜索失败")
		return
	}
	defer rows.Close()

	var emails []Email
	for rows.Next() {
		var e Email
		if err := rows.Scan(&e.ID, &e.MessageID, &e.From, &e.To, &e.Subject,
			&e.BodyText, &e.EmlPath, &e.AttachCount, &e.CreatedAt); err != nil {
			continue
		}
		emails = append(emails, e)
	}

	middleware.Success(c, gin.H{"emails": emails, "query": q, "count": len(emails)})
}

// Show 查看单封邮件详情
func (h *Handler) Show(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		middleware.BadRequest(c, "无效的邮件ID")
		return
	}

	var e Email
	err = h.db.QueryRow(
		`SELECT id, message_id, "from", "to", subject, body_text, body_html, eml_path, attach_count, created_at
		 FROM emails WHERE id = ?`, id,
	).Scan(&e.ID, &e.MessageID, &e.From, &e.To, &e.Subject, &e.BodyText,
		&e.BodyHTML, &e.EmlPath, &e.AttachCount, &e.CreatedAt)
	if err == sql.ErrNoRows {
		middleware.NotFound(c, "邮件不存在")
		return
	}
	if err != nil {
		middleware.InternalError(c, "查询失败")
		return
	}

	middleware.Success(c, e)
}

// Reply 通过 Mailgun HTTP API 回复邮件
func (h *Handler) Reply(c *gin.Context) {
	var req ReplyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		middleware.BadRequest(c, "invalid request body")
		return
	}

	if h.mgAPIKey == "" {
		middleware.InternalError(c, "MAILGUN_API_KEY 未配置")
		return
	}

	// 查询原邮件信息
	var origFrom, origSubj, origMsgID string
	err := h.db.QueryRow(
		`SELECT "from", subject, message_id FROM emails WHERE id = ?`, req.EmailID,
	).Scan(&origFrom, &origSubj, &origMsgID)
	if err == sql.ErrNoRows {
		middleware.NotFound(c, "原邮件不存在")
		return
	}
	if err != nil {
		middleware.InternalError(c, "查询原邮件失败")
		return
	}

	// 调用 Mailgun API
	from := fmt.Sprintf("AiFlowHub <noreply@%s>", h.mgDomain)
	replySubject := origSubj
	if !strings.HasPrefix(strings.ToLower(replySubject), "re:") {
		replySubject = "Re: " + replySubject
	}

	payload := map[string]string{
		"from":       from,
		"to":         origFrom,
		"subject":    replySubject,
		"text":       req.Body,
		"h:In-Reply-To": origMsgID,
		"h:References":  origMsgID,
	}

	body, _ := json.Marshal(payload)
	url := fmt.Sprintf("%s/%s/messages", h.mgAPIBase, h.mgDomain)
	httpReq, _ := http.NewRequest("POST", url, bytes.NewReader(body))
	httpReq.SetBasicAuth("api", h.mgAPIKey)
	httpReq.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(httpReq)
	if err != nil {
		log.Printf("[email] Mailgun API 调用失败: %v", err)
		middleware.InternalError(c, "发送失败: "+err.Error())
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		var errBody bytes.Buffer
		errBody.ReadFrom(resp.Body)
		log.Printf("[email] Mailgun 返回 %d: %s", resp.StatusCode, errBody.String())
		middleware.InternalError(c, fmt.Sprintf("Mailgun 返回 %d", resp.StatusCode))
		return
	}

	log.Printf("[email] 已回复 #%d → %s", req.EmailID, origFrom)
	middleware.Success(c, gin.H{"sent": true, "to": origFrom})
}

// ListKeywords 列出配置的关键词规则
func (h *Handler) ListKeywords(c *gin.Context) {
	rows, err := h.db.Query(
		`SELECT id, keyword, action, enabled, created_at
		 FROM email_keywords ORDER BY id`,
	)
	if err != nil {
		middleware.InternalError(c, "查询失败")
		return
	}
	defer rows.Close()

	type KeywordRule struct {
		ID        int64  `json:"id"`
		Keyword   string `json:"keyword"`
		Action    string `json:"action"`
		Enabled   bool   `json:"enabled"`
		CreatedAt int64  `json:"created_at"`
	}
	var rules []KeywordRule
	for rows.Next() {
		var r KeywordRule
		if err := rows.Scan(&r.ID, &r.Keyword, &r.Action, &r.Enabled, &r.CreatedAt); err != nil {
			continue
		}
		rules = append(rules, r)
	}
	middleware.Success(c, gin.H{"keywords": rules})
}

// AddKeyword 添加关键词规则
func (h *Handler) AddKeyword(c *gin.Context) {
	var req struct {
		Keyword string `json:"keyword"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Keyword) == "" {
		middleware.BadRequest(c, "需要 keyword")
		return
	}
	now := time.Now().Unix()
	h.db.Exec(
		`INSERT INTO email_keywords (keyword, action, enabled, created_at) VALUES (?, 'alert', 1, ?)`,
		strings.TrimSpace(req.Keyword), now,
	)
	middleware.Success(c, gin.H{"added": true, "keyword": req.Keyword})
}

// DeleteKeyword 删除关键词规则
func (h *Handler) DeleteKeyword(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		middleware.BadRequest(c, "无效ID")
		return
	}
	h.db.Exec("DELETE FROM email_keywords WHERE id = ?", id)
	middleware.Success(c, gin.H{"deleted": true})
}

// checkKeywords 异步检查关键词匹配
func (h *Handler) checkKeywords(req InboundRequest) {
	rows, err := h.db.Query("SELECT keyword FROM email_keywords WHERE enabled = 1")
	if err != nil {
		return
	}
	defer rows.Close()

	text := strings.ToLower(req.Subject + " " + req.BodyText)
	for rows.Next() {
		var kw string
		if err := rows.Scan(&kw); err != nil {
			continue
		}
		if strings.Contains(text, strings.ToLower(kw)) {
			if tg, ok := h.tgNotifier.(interface{ Send(string) }); ok && tg != nil {
				tg.Send(fmt.Sprintf(
					"🔔 <b>关键词命中: %s</b>\n发件人: %s\n主题: %s\n关键词: %s",
					kw, req.From, req.Subject, kw,
				))
			}
		}
	}
}

// --- helpers ---

func sanitizeMessageID(msgID string) string {
	// 替换文件系统不安全字符
	s := strings.NewReplacer(
		"<", "", ">", "", "@", "_at_",
		"/", "_", "\\", "_", ":", "_",
		"*", "_", "?", "_", "\"", "_",
	).Replace(msgID)
	if len(s) > 200 {
		s = s[:200]
	}
	return s
}

func truncateForDB(s string, max int) string {
	if len(s) > max {
		return s[:max]
	}
	return s
}
