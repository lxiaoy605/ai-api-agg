package audit

import (
	"database/sql"
	"time"
)

// Log 写入审计日志（只追加，不修改，不删除）
func Log(db *sql.DB, action, actor, target, details, ip string) {
	db.Exec(
		"INSERT INTO audit_log (timestamp, action, actor, target, details, ip) VALUES (?, ?, ?, ?, ?, ?)",
		time.Now().Unix(), action, actor, target, details, ip,
	)
}
