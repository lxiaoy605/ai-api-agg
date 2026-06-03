package notify

// EventType 通知事件类型
type EventType string

const (
	// 支付事件
	EventPaymentCreated     EventType = "payment.created"
	EventPaymentConfirming  EventType = "payment.confirming"
	EventPaymentConfirmed   EventType = "payment.confirmed"
	EventPaymentExpired     EventType = "payment.expired"
	EventPaymentFailed      EventType = "payment.failed"

	// 用户事件
	EventUserRegistered     EventType = "user.registered"
	EventUserLogin          EventType = "user.login"
	EventUserBalanceLow     EventType = "user.balance_low"
	EventUserBalanceZero    EventType = "user.balance_zero"

	// API Key 事件
	EventAPIKeyCreated      EventType = "apikey.created"
	EventAPIKeyDeleted      EventType = "apikey.deleted"
	EventAPIKeyUsageHigh    EventType = "apikey.usage_high"

	// 系统事件
	EventServiceStarted     EventType = "system.service_started"
	EventServiceStopping    EventType = "system.service_stopping"
	EventErrorRateSpike     EventType = "system.error_rate_spike"
	EventDatabaseBackup     EventType = "system.database_backup"
	EventUSDTMonitorError   EventType = "system.usdt_monitor_error"

	// 邮件事件
	EventEmailReceived      EventType = "email.received"
	EventEmailKeywordMatch  EventType = "email.keyword_match"
)

// Severity 事件严重级别
type Severity string

const (
	SeverityInfo     Severity = "info"
	SeverityWarning  Severity = "warning"
	SeverityCritical Severity = "critical"
)

// Notification 通知消息
type Notification struct {
	Event    EventType              `json:"event"`
	Severity Severity               `json:"severity"`
	Title    string                 `json:"title"`
	Body     string                 `json:"body"`
	Meta     map[string]interface{} `json:"meta,omitempty"`
}
