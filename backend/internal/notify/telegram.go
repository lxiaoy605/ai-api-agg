package notify

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

// Telegram 通知器（项目全局共享）
type Telegram struct {
	botToken string
	chatID   string
	client   *http.Client
}

// NewTelegram 创建 Telegram 通知器
func NewTelegram() *Telegram {
	return &Telegram{
		botToken: os.Getenv("TELEGRAM_BOT_TOKEN"),
		chatID:   os.Getenv("TELEGRAM_CHAT_ID"),
		client:   &http.Client{Timeout: 10 * time.Second},
	}
}

// Enabled 检查通知是否可用
func (t *Telegram) Enabled() bool {
	return t.botToken != "" && t.chatID != ""
}

// Send 发送消息到 Telegram
func (t *Telegram) Send(text string) {
	if !t.Enabled() {
		return
	}

	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", t.botToken)
	payload := map[string]interface{}{
		"chat_id":    t.chatID,
		"text":       text,
		"parse_mode": "HTML",
	}
	body, _ := json.Marshal(payload)
	resp, err := t.client.Post(url, "application/json", bytes.NewReader(body))
	if err != nil {
		log.Printf("[TG] 发送通知失败: %v", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		log.Printf("[TG] Telegram API 返回非 200: %d", resp.StatusCode)
	}
}

// Sendf 格式化发送消息
func (t *Telegram) Sendf(format string, args ...interface{}) {
	t.Send(fmt.Sprintf(format, args...))
}

// NotifyUSDTReceived USDT 到账通知
func (t *Telegram) NotifyUSDTReceived(userID int64, amount float64, tokens int64, txHash string) {
	t.Sendf(
		"💰 <b>USDT 自动到账</b>\n"+
			"用户 ID: %d\n"+
			"金额: $%.2f USDT\n"+
			"获得 Token: %d\n"+
			"交易哈希: <code>%s</code>",
		userID, amount, tokens, txHash,
	)
}

// NotifyUSDTError USDT 监听异常通知
func (t *Telegram) NotifyUSDTError(errType string, err error, detail string) {
	t.Sendf(
		"⚠️ <b>USDT 监听异常</b>\n"+
			"类型: %s\n"+
			"错误: %v\n"+
			"详情: %s",
		errType, err, detail,
	)
}

// NotifyUSDTManualReview USDT 交易需人工审核
func (t *Telegram) NotifyUSDTManualReview(txHash string, amount float64, reason string) {
	t.Sendf(
		"🔍 <b>USDT 交易待人工审核</b>\n"+
			"哈希: <code>%s</code>\n"+
			"金额: $%.2f USDT\n"+
			"原因: %s",
		txHash, amount, reason,
	)
}
