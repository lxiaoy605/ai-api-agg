package notify

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Channel 通知渠道接口
type Channel interface {
	// Send 发送通知，返回是否发送成功
	Send(n Notification) bool
	// Name 渠道名称
	Name() string
	// Enabled 渠道是否可用
	Enabled() bool
}

// Center 统一通知中心
type Center struct {
	mu       sync.RWMutex
	channels []Channel
}

// NewCenter 创建通知中心
func NewCenter() *Center {
	return &Center{}
}

// Register 注册通知渠道
func (c *Center) Register(ch Channel) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.channels = append(c.channels, ch)
	if ch.Enabled() {
		log.Printf("[notify] 渠道已注册: %s ✅", ch.Name())
	} else {
		log.Printf("[notify] 渠道已注册: %s ⚠️ (未启用)", ch.Name())
	}
}

// Send 向所有启用的渠道发送通知
func (c *Center) Send(n Notification) {
	c.mu.RLock()
	channels := make([]Channel, len(c.channels))
	copy(channels, c.channels)
	c.mu.RUnlock()

	for _, ch := range channels {
		if !ch.Enabled() {
			continue
		}
		go func(ch Channel) {
			if ch.Send(n) {
				log.Printf("[notify] %s → %s ✅", n.Event, ch.Name())
			} else {
				log.Printf("[notify] %s → %s ❌ 发送失败", n.Event, ch.Name())
			}
		}(ch)
	}
}

// Notify 快速构建并发送通知
func (c *Center) Notify(event EventType, severity Severity, title, body string, meta map[string]interface{}) {
	c.Send(Notification{
		Event:    event,
		Severity: severity,
		Title:    title,
		Body:     body,
		Meta:     meta,
	})
}

// ============================================================
// Telegram 渠道（适配 Center 接口）
// ============================================================

// TelegramChannel 将现有 Telegram 通知器包装为 Channel
type TelegramChannel struct {
	tg *Telegram
}

// NewTelegramChannel 创建 Telegram 渠道
func NewTelegramChannel(tg *Telegram) *TelegramChannel {
	return &TelegramChannel{tg: tg}
}

func (tc *TelegramChannel) Name() string  { return "telegram" }
func (tc *TelegramChannel) Enabled() bool { return tc.tg.Enabled() }

func (tc *TelegramChannel) Send(n Notification) bool {
	if !tc.tg.Enabled() {
		return false
	}

	// 根据事件级别选择图标
	icon := severityIcon(n.Severity)
	text := fmt.Sprintf("%s <b>%s</b>\n%s", icon, n.Title, n.Body)

	// 如果有元数据，追加
	if len(n.Meta) > 0 {
		var parts []string
		for k, v := range n.Meta {
			// 跳过敏感/过长字段
			if k == "token" || k == "password" {
				continue
			}
			str := fmt.Sprintf("%v", v)
			if len(str) > 200 {
				str = str[:200] + "..."
			}
			parts = append(parts, fmt.Sprintf("<b>%s:</b> %s", k, escapeHTML(str)))
		}
		if len(parts) > 0 {
			text += "\n\n" + strings.Join(parts, "\n")
		}
	}

	tc.tg.Send(text)
	return true
}

func severityIcon(s Severity) string {
	switch s {
	case SeverityCritical:
		return "🔴"
	case SeverityWarning:
		return "🟡"
	default:
		return "ℹ️"
	}
}

func escapeHTML(s string) string {
	s = strings.ReplaceAll(s, "&", "&amp;")
	s = strings.ReplaceAll(s, "<", "&lt;")
	s = strings.ReplaceAll(s, ">", "&gt;")
	return s
}

// ============================================================
// 日志渠道（开发调试用）
// ============================================================

// LogChannel 将通知输出到日志
type LogChannel struct{}

func (lc *LogChannel) Name() string    { return "log" }
func (lc *LogChannel) Enabled() bool   { return true }
func (lc *LogChannel) Send(n Notification) bool {
	log.Printf("[notify|log] [%s] %s: %s", n.Severity, n.Title, n.Body)
	return true
}

// ============================================================
// Webhook 渠道（ai-api-agg → OpenClaw 桥）
// ============================================================

// WebhookChannel 向 OpenClaw webhook 推送事件
type WebhookChannel struct {
	url    string
	token  string
	client *http.Client
}

// NewWebhookChannel 创建 webhook 渠道
func NewWebhookChannel(url, token string) *WebhookChannel {
	return &WebhookChannel{
		url:    url,
		token:  token,
		client: &http.Client{Timeout: 10 * time.Second},
	}
}

func (wc *WebhookChannel) Name() string  { return "webhook" }
func (wc *WebhookChannel) Enabled() bool { return wc.url != "" && wc.token != "" }

func (wc *WebhookChannel) Send(n Notification) bool {
	if !wc.Enabled() {
		return false
	}

	// 只推送 critical 和 warning 级别事件到 OpenClaw
	if n.Severity != SeverityCritical && n.Severity != SeverityWarning {
		return false
	}

	// 构建 webhook payload
	text := fmt.Sprintf("[%s] %s\n%s", n.Event, n.Title, n.Body)
	if len(n.Meta) > 0 {
		for k, v := range n.Meta {
			text += fmt.Sprintf("\n%s: %v", k, v)
		}
	}

	payload := map[string]interface{}{
		"text": text,
		"mode": "now",
	}
	body, _ := json.Marshal(payload)

	req, err := http.NewRequest("POST", wc.url+"/wake", bytes.NewReader(body))
	if err != nil {
		log.Printf("[notify|webhook] 构建请求失败: %v", err)
		return false
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+wc.token)

	resp, err := wc.client.Do(req)
	if err != nil {
		log.Printf("[notify|webhook] POST 失败: %v", err)
		return false
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		log.Printf("[notify|webhook] 返回 %d", resp.StatusCode)
		return false
	}

	return true
}
