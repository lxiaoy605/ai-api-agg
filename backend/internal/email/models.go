package email

// Email 邮件模型 — SQLite 元数据
type Email struct {
	ID          int64  `json:"id"`
	MessageID   string `json:"message_id"`
	From        string `json:"from"`
	To          string `json:"to"`
	Subject     string `json:"subject"`
	BodyText    string `json:"body_text"`
	BodyHTML    string `json:"body_html,omitempty"`
	EmlPath     string `json:"eml_path"`
	AttachCount int    `json:"attach_count"`
	CreatedAt   int64  `json:"created_at"`
}

// InboundRequest Worker 发来的邮件接收请求
type InboundRequest struct {
	MessageID string `json:"message_id"`
	From      string `json:"from"`
	To        string `json:"to"`
	Subject   string `json:"subject"`
	BodyText  string `json:"body_text"`
	BodyHTML  string `json:"body_html,omitempty"`
	RawEML    string `json:"raw_eml,omitempty"`
}

// ReplyRequest 回复邮件请求
type ReplyRequest struct {
	EmailID int64  `json:"email_id"`
	Body    string `json:"body"`
}
