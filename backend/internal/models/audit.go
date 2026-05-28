package models

// AuditEntry 审计日志条目
type AuditEntry struct {
	ID        int64  `json:"id"`
	Timestamp int64  `json:"timestamp"`
	Action    string `json:"action"`
	Actor     string `json:"actor"`
	Target    string `json:"target"`
	Details   string `json:"details"`
	IP        string `json:"ip"`
}
