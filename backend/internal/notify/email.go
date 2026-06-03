package notify

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// EmailConfig 邮件发送配置
type EmailConfig struct {
	APIKey string // Mailgun API Key
	Domain string // 发送域名 (aiflowhub.ai)
	From   string // 发件人地址
}

// EmailSender Mailgun 邮件发送器
type EmailSender struct {
	cfg    EmailConfig
	client *http.Client
}

// NewEmailSender 创建邮件发送器
func NewEmailSender(apiKey, domain, from string) *EmailSender {
	if apiKey == "" {
		log.Println("[email] MAILGUN_API_KEY 未配置，邮件通知不可用")
	}
	if from == "" {
		from = fmt.Sprintf("AiFlowHub <noreply@%s>", domain)
	}
	return &EmailSender{
		cfg: EmailConfig{APIKey: apiKey, Domain: domain, From: from},
		client: &http.Client{Timeout: 15 * time.Second},
	}
}

// Enabled 邮件发送是否可用
func (e *EmailSender) Enabled() bool {
	return e.cfg.APIKey != "" && e.cfg.Domain != ""
}

// Send 发送邮件
func (e *EmailSender) Send(to, subject, htmlBody string) error {
	if !e.Enabled() {
		return fmt.Errorf("邮件发送未配置")
	}

	form := url.Values{}
	form.Set("from", e.cfg.From)
	form.Set("to", to)
	form.Set("subject", subject)
	form.Set("html", htmlBody)

	apiURL := fmt.Sprintf("https://api.eu.mailgun.net/v3/%s/messages", e.cfg.Domain)
	req, err := http.NewRequest("POST", apiURL, strings.NewReader(form.Encode()))
	if err != nil {
		return fmt.Errorf("构建请求失败: %w", err)
	}
	req.SetBasicAuth("api", e.cfg.APIKey)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := e.client.Do(req)
	if err != nil {
		return fmt.Errorf("请求失败: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return fmt.Errorf("Mailgun 返回 %d: %s", resp.StatusCode, string(body))
	}

	log.Printf("[email] 发送成功 → %s | %s", to, subject)
	return nil
}

// ============================================================
// 邮件模板
// ============================================================

const emailWrapper = `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f5f5f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif">
<table width="100%%" cellpadding="0" cellspacing="0" style="background:#f5f5f5;padding:40px 0">
<tr><td align="center">
<table width="600" cellpadding="0" cellspacing="0" style="background:#fff;border-radius:8px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08)">
  <tr><td style="background:#1a1a2e;padding:24px 32px;text-align:center">
    <span style="color:#fff;font-size:20px;font-weight:700">🚀 AiFlowHub</span>
  </td></tr>
  <tr><td style="padding:32px">
    %s
  </td></tr>
  <tr><td style="background:#fafafa;padding:16px 32px;text-align:center">
    <span style="color:#999;font-size:12px">AiFlowHub — High-Performance AI API Aggregator</span><br>
    <span style="color:#bbb;font-size:11px">This is an automated message. Please do not reply.</span>
  </td></tr>
</table>
</td></tr></table>
</body></html>`

// BuildWelcomeEmail 注册欢迎邮件
func BuildWelcomeEmail(email string) (subject, html string) {
	body := fmt.Sprintf(`
    <h2 style="color:#1a1a2e;margin:0 0 16px">👋 Welcome to AiFlowHub!</h2>
    <p style="color:#444;font-size:15px;line-height:1.6;margin:0 0 16px">
      Your account <strong>%s</strong> has been successfully registered.
    </p>
    <p style="color:#444;font-size:15px;line-height:1.6;margin:0 0 24px">
      We've added <strong>$1 trial credit</strong> (≈ 500,000 tokens) to get you started right away.
    </p>
    <div style="background:#f0f7ff;border-left:4px solid #3b82f6;padding:12px 16px;margin:0 0 24px;border-radius:0 4px 4px 0">
      <p style="color:#1e40af;font-size:14px;margin:0">
        📍 API Endpoint: <code style="background:#fff;padding:2px 6px;border-radius:3px">https://api.aiflowhub.ai/v1/chat/completions</code>
      </p>
    </div>
    <a href="https://aiflowhub.ai/dashboard" style="display:inline-block;background:#1a1a2e;color:#fff;text-decoration:none;padding:12px 32px;border-radius:6px;font-weight:600;font-size:15px">
      Go to Dashboard →
    </a>
  `, email)
	return "Welcome to AiFlowHub 🚀", fmt.Sprintf(emailWrapper, body)
}

// BuildPasswordResetEmail 密码重置邮件
func BuildPasswordResetEmail(email, resetLink string) (subject, html string) {
	body := fmt.Sprintf(`
    <h2 style="color:#1a1a2e;margin:0 0 16px">🔑 Password Reset</h2>
    <p style="color:#444;font-size:15px;line-height:1.6;margin:0 0 16px">
      We received a password reset request for <strong>%s</strong>.
    </p>
    <p style="color:#444;font-size:15px;line-height:1.6;margin:0 0 24px">
      Click the button below to reset your password (valid for 30 minutes):
    </p>
    <a href="%s" style="display:inline-block;background:#3b82f6;color:#fff;text-decoration:none;padding:12px 32px;border-radius:6px;font-weight:600;font-size:15px">
      Reset Password →
    </a>
    <p style="color:#999;font-size:13px;margin:24px 0 0">
      If you did not request this, please ignore this email.
    </p>
  `, email, resetLink)
	return "AiFlowHub Password Reset", fmt.Sprintf(emailWrapper, body)
}

// BuildTopupConfirmEmail 充值成功邮件
func BuildTopupConfirmEmail(email string, amountUSD float64, tokens int64, bonus int64) (subject, html string) {
	totalTokens := tokens + bonus
	body := fmt.Sprintf(`
    <h2 style="color:#1a1a2e;margin:0 0 16px">💰 Top-Up Confirmed</h2>
    <p style="color:#444;font-size:15px;line-height:1.6;margin:0 0 16px">
      Your top-up for <strong>%s</strong> has been credited.
    </p>
    <table cellpadding="0" cellspacing="0" style="width:100%%;border-collapse:collapse;margin:0 0 24px">
      <tr><td style="padding:8px 12px;border-bottom:1px solid #eee;color:#666;width:140px">Amount</td>
          <td style="padding:8px 12px;border-bottom:1px solid #eee;font-weight:600">$%.2f USD</td></tr>
      <tr><td style="padding:8px 12px;border-bottom:1px solid #eee;color:#666">Tokens Credited</td>
          <td style="padding:8px 12px;border-bottom:1px solid #eee;font-weight:600">%s</td></tr>
      <tr><td style="padding:8px 12px;border-bottom:1px solid #eee;color:#666">Bonus</td>
          <td style="padding:8px 12px;border-bottom:1px solid #eee;font-weight:600;color:#10b981">+%s</td></tr>
      <tr><td style="padding:8px 12px;color:#666">Total</td>
          <td style="padding:8px 12px;font-weight:700;font-size:16px;color:#1a1a2e">%s Tokens</td></tr>
    </table>
    <a href="https://aiflowhub.ai/dashboard" style="display:inline-block;background:#1a1a2e;color:#fff;text-decoration:none;padding:12px 32px;border-radius:6px;font-weight:600;font-size:15px">
      View Balance →
    </a>
  `, email, amountUSD, fmtNum(tokens), fmtNum(bonus), fmtNum(totalTokens))
	return "AiFlowHub Top-Up Confirmed ✅", fmt.Sprintf(emailWrapper, body)
}

// BuildBalanceWarningEmail 余额预警邮件
func BuildBalanceWarningEmail(email string, remainingTokens int64, estimatedDaysLeft int) (subject, html string) {
	body := fmt.Sprintf(`
    <h2 style="color:#1a1a2e;margin:0 0 16px">⚠️ Low Balance Alert</h2>
    <p style="color:#444;font-size:15px;line-height:1.6;margin:0 0 16px">
      Your account <strong>%s</strong> is running low on tokens.
    </p>
    <table cellpadding="0" cellspacing="0" style="width:100%%;border-collapse:collapse;margin:0 0 24px">
      <tr><td style="padding:8px 12px;border-bottom:1px solid #eee;color:#666;width:160px">Remaining Tokens</td>
          <td style="padding:8px 12px;border-bottom:1px solid #eee;font-weight:600">%s</td></tr>
      <tr><td style="padding:8px 12px;color:#666">Est. Days Left</td>
          <td style="padding:8px 12px;font-weight:600;color:#ef4444">≈ %d days</td></tr>
    </table>
    <p style="color:#666;font-size:14px;margin:0 0 20px">
      Once your balance reaches zero, API requests will return 402 Payment Required. Top up now to avoid service interruption.
    </p>
    <a href="https://aiflowhub.ai/dashboard/topup" style="display:inline-block;background:#ef4444;color:#fff;text-decoration:none;padding:12px 32px;border-radius:6px;font-weight:600;font-size:15px">
      Top Up Now →
    </a>
  `, email, fmtNum(remainingTokens), estimatedDaysLeft)
	return "AiFlowHub Low Balance Alert ⚠️", fmt.Sprintf(emailWrapper, body)
}

// fmtNum 格式化数字（加千分位逗号）
func fmtNum(n int64) string {
	s := fmt.Sprintf("%d", n)
	if len(s) <= 3 {
		return s
	}
	var result []byte
	for i, c := range s {
		if i > 0 && (len(s)-i)%3 == 0 {
			result = append(result, ',')
		}
		result = append(result, byte(c))
	}
	return string(result)
}

// ============================================================
// EmailChannel 适配通知中心
// ============================================================

// EmailChannel 将 EmailSender 包装为通知中心渠道
type EmailChannel struct {
	sender *EmailSender
}

// NewEmailChannel 创建邮件渠道
func NewEmailChannel(sender *EmailSender) *EmailChannel {
	return &EmailChannel{sender: sender}
}

func (ec *EmailChannel) Name() string  { return "email" }
func (ec *EmailChannel) Enabled() bool { return ec.sender.Enabled() }

func (ec *EmailChannel) Send(n Notification) bool {
	if !ec.sender.Enabled() {
		return false
	}

	// 从 Meta 中提取收件人
	to, ok := n.Meta["email"].(string)
	if !ok || to == "" {
		log.Printf("[notify|email] 缺少收件人地址，跳过事件: %s", n.Event)
		return false
	}

	var subject, html string
	switch n.Event {
	case EventPaymentConfirmed:
		amount, _ := n.Meta["amount_usd"].(float64)
		tokens, _ := n.Meta["tokens"].(int64)
		bonus, _ := n.Meta["bonus"].(int64)
		subject, html = BuildTopupConfirmEmail(to, amount, tokens-bonus, bonus)
	case EventUserRegistered:
		subject, html = BuildWelcomeEmail(to)
	default:
		subject = n.Title
		html = fmt.Sprintf(emailWrapper,
			fmt.Sprintf("<p style='color:#444;font-size:15px;line-height:1.6'>%s</p>", n.Body))
	}

	if err := ec.sender.Send(to, subject, html); err != nil {
		log.Printf("[notify|email] 发送失败: %v", err)
		return false
	}
	return true
}

// ============================================================
// 兼容旧 mailgunSend (bot.go 引用)
// ============================================================

// SendReply 发送邮件回复（兼容 bot.go 中的 mailgunSend）
func (e *EmailSender) SendReply(to, origSubj, origMsgID, body string) error {
	if !strings.HasPrefix(strings.ToLower(origSubj), "re:") {
		origSubj = "Re: " + origSubj
	}

	form := url.Values{}
	form.Set("from", e.cfg.From)
	form.Set("to", to)
	form.Set("subject", origSubj)
	form.Set("text", body)
	form.Set("h:In-Reply-To", origMsgID)
	form.Set("h:References", origMsgID)

	apiURL := fmt.Sprintf("https://api.eu.mailgun.net/v3/%s/messages", e.cfg.Domain)
	req, _ := http.NewRequest("POST", apiURL, strings.NewReader(form.Encode()))
	req.SetBasicAuth("api", e.cfg.APIKey)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := e.client.Do(req)
	if err != nil {
		return fmt.Errorf("请求失败: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		errBody, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return fmt.Errorf("Mailgun 返回 %d: %s", resp.StatusCode, string(errBody))
	}
	return nil
}
