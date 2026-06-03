package notify

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// BotHandler 处理 Telegram Bot 命令（轮询 + webhook 双模式）
type BotHandler struct {
	tg          *Telegram
	db          *sql.DB
	emailSender *EmailSender
	offset      int64 // getUpdates 偏移
}

// NewBotHandler 创建 Bot 命令处理器
func NewBotHandler(tg *Telegram, db *sql.DB, emailSender *EmailSender) *BotHandler {
	return &BotHandler{tg: tg, db: db, emailSender: emailSender}
}

// StartPolling 启动轮询方式监听命令（不依赖 webhook）
func (h *BotHandler) StartPolling() {
	if !h.tg.Enabled() {
		log.Println("[TG-bot] 未配置 Bot token，跳过轮询")
		return
	}
	log.Println("[TG-bot] 启动轮询模式...")
	go func() {
		for {
			updates, err := h.getUpdates()
			if err != nil {
				log.Printf("[TG-bot] getUpdates 失败: %v", err)
				time.Sleep(5 * time.Second)
				continue
			}
			for _, u := range updates {
				h.offset = u.UpdateID + 1
				if u.Message == nil || u.Message.Text == "" {
					continue
				}
				h.processCommand(u.Message.Chat.ID, u.Message.Text)
			}
			time.Sleep(2 * time.Second)
		}
	}()
}

type tgUpdate struct {
	UpdateID int64      `json:"update_id"`
	Message  *tgMessage `json:"message"`
}

type tgMessage struct {
	Chat tgChat `json:"chat"`
	Text string `json:"text"`
}

type tgChat struct {
	ID int64 `json:"id"`
}

func (h *BotHandler) getUpdates() ([]tgUpdate, error) {
	url := fmt.Sprintf("https://api.telegram.org/bot%s/getUpdates?timeout=30&offset=%d",
		h.tg.botToken, h.offset)
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result struct {
		OK     bool       `json:"ok"`
		Result []tgUpdate `json:"result"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}
	return result.Result, nil
}

// HandleWebhook 接收并路由 Telegram Bot 命令（webhook 方式，备用）
func (h *BotHandler) HandleWebhook(c *gin.Context) {
	var update struct {
		Message struct {
			Chat struct {
				ID int64 `json:"id"`
			} `json:"chat"`
			Text string `json:"text"`
		} `json:"message"`
	}
	if err := c.ShouldBindJSON(&update); err != nil {
		c.Status(http.StatusOK)
		return
	}

	text := strings.TrimSpace(update.Message.Text)
	if text == "" {
		c.Status(http.StatusOK)
		return
	}

	h.processCommand(update.Message.Chat.ID, text)
	c.Status(http.StatusOK)
}

func (h *BotHandler) processCommand(chatID int64, text string) {
	// 去掉 Telegram 客户端自动补上的 @bot_username
	text = stripBotUsername(text)

	// 只响应管理员的 chat
	if chatID != h.adminChatID() {
		h.sendToChat(chatID, "⛔ 未经授权的用户")
		return
	}

	switch {
	case text == "/start":
		h.cmdStart(chatID)
	case text == "/help" || text == "/emails":
		h.cmdHelp(chatID)
	case strings.HasPrefix(text, "/emails_list"):
		h.cmdList(chatID)
	case strings.HasPrefix(text, "/search "):
		h.cmdSearch(chatID, strings.TrimPrefix(text, "/search "))
	case strings.HasPrefix(text, "/emails_search "):
		h.cmdSearch(chatID, strings.TrimPrefix(text, "/emails_search "))
	case strings.HasPrefix(text, "/emails_search"):
		// 仅命令无关键词
		h.cmdSearch(chatID, "")
	case strings.HasPrefix(text, "/emails_show_") || strings.HasPrefix(text, "/show_"):
		arg := strings.TrimPrefix(text, "/emails_show_")
		if arg == text {
			arg = strings.TrimPrefix(text, "/show_")
		}
		h.cmdShow(chatID, arg)
	case strings.HasPrefix(text, "/reply_"):
		h.cmdReply(chatID, strings.TrimPrefix(text, "/reply_"))
	case strings.HasPrefix(text, "/keywords") || text == "/keywords":
		h.cmdKeywords(chatID)
	default:
		h.sendToChat(chatID, "未知命令。输入 /help 查看可用命令。")
	}
}

func (h *BotHandler) cmdStart(chatID int64) {
	h.sendToChat(chatID,
		"👋 <b>AiFlowHub 管理 Bot</b>\n\n"+
			"可用命令:\n"+
			"/emails_list — 列出最近邮件\n"+
			"/emails_search &lt;关键词&gt; — 搜索邮件\n"+
			"/emails_show_&lt;ID&gt; — 查看详情\n"+
			"/reply_&lt;ID&gt; &lt;正文&gt; — 回复邮件\n"+
			"/keywords — 查看关键词规则",
	)
}

func (h *BotHandler) cmdHelp(chatID int64) {
	h.cmdStart(chatID)
}

func (h *BotHandler) cmdList(chatID int64) {
	rows, err := h.db.Query(
		`SELECT id, "from", subject, created_at FROM emails ORDER BY created_at DESC LIMIT 50`,
	)
	if err != nil {
		h.sendToChat(chatID, "❌ 查询失败: "+err.Error())
		return
	}
	defer rows.Close()

	var lines []string
	lines = append(lines, "📧 <b>最近邮件 (10封)</b>\n")
	hasRows := false
	for rows.Next() {
		var id int64
		var from, subject string
		var ts int64
		if err := rows.Scan(&id, &from, &subject, &ts); err != nil {
			continue
		}
		subj := escapeHTMLBot(truncStr(subject, 40))
		fromName := escapeHTMLBot(truncStr(from, 25))
		lines = append(lines, fmt.Sprintf("/emails_show_%d — <code>#%d</code> %s\n          <i>%s</i>", id, id, subj, fromName))
		hasRows = true
	}

	if !hasRows {
		lines = append(lines, "暂无邮件")
	}

	h.sendToChat(chatID, strings.Join(lines, "\n"))
}

func (h *BotHandler) cmdSearch(chatID int64, query string) {
	query = strings.TrimSpace(query)
	if query == "" {
		h.sendToChat(chatID, "用法: /emails_search &lt;关键词&gt;")
		return
	}

	like := "%" + query + "%"
	rows, err := h.db.Query(
		`SELECT id, "from", subject, created_at FROM emails
		 WHERE subject LIKE ? OR body_text LIKE ? OR "from" LIKE ?
		 ORDER BY created_at DESC LIMIT 50`,
		like, like, like,
	)
	if err != nil {
		h.sendToChat(chatID, "❌ 搜索失败")
		return
	}
	defer rows.Close()

	var lines []string
	lines = append(lines, fmt.Sprintf("🔍 搜索 \"%s\":\n", truncStr(query, 30)))
	hasRows := false
	for rows.Next() {
		var id int64
		var from, subject string
		var ts int64
		if err := rows.Scan(&id, &from, &subject, &ts); err != nil {
			continue
		}
		lines = append(lines, fmt.Sprintf("/emails_show_%d — %s", id, escapeHTMLBot(truncStr(subject, 40))))
		hasRows = true
	}
	if !hasRows {
		lines = append(lines, "无匹配结果")
	}

	h.sendToChat(chatID, strings.Join(lines, "\n"))
}

func (h *BotHandler) cmdShow(chatID int64, idStr string) {
	idStr = strings.TrimSpace(idStr)
	if idStr == "" {
		h.sendToChat(chatID, "用法: /emails_show_&lt;ID&gt;")
		return
	}

	var id int64
	if _, err := fmt.Sscanf(idStr, "%d", &id); err != nil {
		h.sendToChat(chatID, "无效的邮件ID")
		return
	}

	var messageID, from, to, subject, body string
	var attachCount int
	var ts int64
	err := h.db.QueryRow(
		`SELECT message_id, "from", "to", subject, body_text, attach_count, created_at
		 FROM emails WHERE id = ?`, id,
	).Scan(&messageID, &from, &to, &subject, &body, &attachCount, &ts)
	if err == sql.ErrNoRows {
		h.sendToChat(chatID, "邮件不存在")
		return
	}
	if err != nil {
		h.sendToChat(chatID, "查询失败")
		return
	}

	text := fmt.Sprintf(
		"📧 <b>#%d %s</b>\n"+
			"<b>From:</b> %s\n"+
			"<b>To:</b> %s\n"+
			"<b>附件:</b> %d\n\n"+
			"%s\n\n"+
			"<i>回复: /reply_%d 内容</i>",
		id, escapeHTMLBot(subject), escapeHTMLBot(from), escapeHTMLBot(to), attachCount, escapeHTMLBot(truncStr(body, 1000)), id,
	)
	h.sendToChat(chatID, text)
}

func (h *BotHandler) cmdReply(chatID int64, args string) {
	parts := strings.SplitN(args, " ", 2)
	if len(parts) < 2 {
		h.sendToChat(chatID, "用法: /reply_&lt;ID&gt; &lt;回复正文&gt;")
		return
	}

	var emailID int64
	if _, err := fmt.Sscanf(parts[0], "%d", &emailID); err != nil {
		h.sendToChat(chatID, "无效的邮件ID")
		return
	}
	replyBody := strings.TrimSpace(parts[1])
	if replyBody == "" {
		h.sendToChat(chatID, "回复内容不能为空")
		return
	}

	var origFrom, origSubj, origMsgID string
	err := h.db.QueryRow(
		`SELECT "from", subject, message_id FROM emails WHERE id = ?`, emailID,
	).Scan(&origFrom, &origSubj, &origMsgID)
	if err == sql.ErrNoRows {
		h.sendToChat(chatID, "原邮件不存在")
		return
	}
	if err != nil {
		h.sendToChat(chatID, "查询失败")
		return
	}

	if err := h.emailSender.SendReply(origFrom, origSubj, origMsgID, replyBody); err != nil {
		log.Printf("[TG-bot] Mailgun 发送失败: %v", err)
		h.sendToChat(chatID, "❌ 发送失败: "+err.Error())
		return
	}

	h.sendToChat(chatID, fmt.Sprintf("✅ 已回复 #%d → %s", emailID, truncStr(origFrom, 30)))
}

func (h *BotHandler) cmdKeywords(chatID int64) {
	rows, err := h.db.Query(
		`SELECT id, keyword, enabled FROM email_keywords ORDER BY id`,
	)
	if err != nil {
		h.sendToChat(chatID, "查询失败")
		return
	}
	defer rows.Close()

	var lines []string
	lines = append(lines, "🏷 <b>关键词规则:</b>\n")
	hasRows := false
	for rows.Next() {
		var id int64
		var kw string
		var enabled bool
		if err := rows.Scan(&id, &kw, &enabled); err != nil {
			continue
		}
		status := "✅"
		if !enabled {
			status = "⏸"
		}
		lines = append(lines, fmt.Sprintf("%s %s", status, kw))
		hasRows = true
	}
	if !hasRows {
		lines = append(lines, "暂无关键词规则")
	}

	h.sendToChat(chatID, strings.Join(lines, "\n"))
}

func (h *BotHandler) adminChatID() int64 {
	var id int64
	fmt.Sscanf(h.tg.ChatID(), "%d", &id)
	return id
}

// sendToChat 发送消息到指定 chat
func (h *BotHandler) sendToChat(chatID int64, text string) {
	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", h.tg.botToken)
	payload := map[string]interface{}{
		"chat_id":    chatID,
		"text":       text,
		"parse_mode": "HTML",
	}
	body, _ := json.Marshal(payload)
	resp, err := http.Post(url, "application/json", bytes.NewReader(body))
	if err != nil {
		log.Printf("[TG-bot] sendToChat 失败: %v", err)
		return
	}
	defer resp.Body.Close()
	bodyBytes, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		log.Printf("[TG-bot] sendToChat 返回 %d: %s", resp.StatusCode, string(bodyBytes))
	}
}

func stripBotUsername(text string) string {
	i := strings.Index(text, "@")
	if i < 0 {
		return text
	}
	end := strings.Index(text[i:], " ")
	if end < 0 {
		return text[:i]
	}
	return text[:i] + text[i+end:]
}

func truncStr(s string, max int) string {
	if len(s) > max {
		return s[:max] + "…"
	}
	return s
}

func escapeHTMLBot(s string) string {
	s = strings.ReplaceAll(s, "&", "&amp;")
	s = strings.ReplaceAll(s, "<", "&lt;")
	s = strings.ReplaceAll(s, ">", "&gt;")
	return s
}
