package database

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"
)

// Init 初始化 SQLite 数据库并运行迁移
func Init(dbPath string) (*sql.DB, error) {
	// 确保数据目录存在
	dir := filepath.Dir(dbPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("创建数据目录失败: %w", err)
	}

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("打开数据库失败: %w", err)
	}

	// 启用 WAL 模式
	if _, err := db.Exec("PRAGMA journal_mode=WAL"); err != nil {
		return nil, fmt.Errorf("启用 WAL 模式失败: %w", err)
	}
	if _, err := db.Exec("PRAGMA foreign_keys=ON"); err != nil {
		return nil, fmt.Errorf("启用外键约束失败: %w", err)
	}

	if err := migrate(db); err != nil {
		return nil, fmt.Errorf("数据库迁移失败: %w", err)
	}

	return db, nil
}

func migrate(db *sql.DB) error {
	migrations := []string{
		`CREATE TABLE IF NOT EXISTS users (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			email TEXT UNIQUE NOT NULL,
			password_hash TEXT NOT NULL,
			role TEXT NOT NULL DEFAULT 'user',
			quota INTEGER NOT NULL DEFAULT 0,
			created_at INTEGER NOT NULL,
			updated_at INTEGER NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS api_keys (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id INTEGER NOT NULL,
			name TEXT NOT NULL DEFAULT '',
			key_prefix TEXT NOT NULL,
			encrypted_key TEXT NOT NULL,
			status TEXT NOT NULL DEFAULT 'active',
			created_at INTEGER NOT NULL,
			last_used_at INTEGER,
			FOREIGN KEY (user_id) REFERENCES users(id)
		)`,
		`CREATE TABLE IF NOT EXISTS usage_logs (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			api_key_id INTEGER NOT NULL,
			request_count INTEGER NOT NULL DEFAULT 0,
			token_count INTEGER NOT NULL DEFAULT 0,
			recorded_at INTEGER NOT NULL,
			FOREIGN KEY (api_key_id) REFERENCES api_keys(id)
		)`,
		`CREATE TABLE IF NOT EXISTS audit_log (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			timestamp INTEGER NOT NULL,
			action TEXT NOT NULL,
			actor TEXT NOT NULL,
			target TEXT NOT NULL DEFAULT '',
			details TEXT NOT NULL DEFAULT '',
			ip TEXT NOT NULL DEFAULT ''
		)`,
		`CREATE TABLE IF NOT EXISTS workgroups (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id INTEGER NOT NULL,
			name TEXT NOT NULL,
			description TEXT NOT NULL DEFAULT '',
			created_at INTEGER NOT NULL,
			FOREIGN KEY (user_id) REFERENCES users(id)
		)`,
		`CREATE TABLE IF NOT EXISTS payment_log (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id       INTEGER NOT NULL,
			username      TEXT DEFAULT '',
			payment_id    TEXT NOT NULL UNIQUE,
			provider      TEXT NOT NULL,
			amount_cents  INTEGER NOT NULL,
			currency      TEXT DEFAULT 'USD',
			tokens        INTEGER NOT NULL,
			bonus         INTEGER DEFAULT 0,
			status        TEXT NOT NULL DEFAULT 'pending',
			memo          TEXT DEFAULT '',
			tx_hash       TEXT DEFAULT '',
			notes         TEXT DEFAULT '',
			created_at    INTEGER NOT NULL,
			updated_at    INTEGER DEFAULT 0,
			completed_at  INTEGER DEFAULT 0,
			FOREIGN KEY (user_id) REFERENCES users(id)
		)`,
		`CREATE TABLE IF NOT EXISTS provider_balances (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT NOT NULL UNIQUE,
			balance REAL NOT NULL DEFAULT 0,
			alert_threshold REAL NOT NULL DEFAULT 50,
			notes TEXT DEFAULT '',
			updated_at INTEGER NOT NULL,
			created_at INTEGER NOT NULL
		)`,
	}

	// 兼容旧表：尝试添加可能缺失的列
	alterStatements := []string{
		`ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'user'`,
		`ALTER TABLE users ADD COLUMN quota INTEGER NOT NULL DEFAULT 0`,
		`ALTER TABLE api_keys ADD COLUMN workgroup_id INTEGER DEFAULT NULL`,
		`ALTER TABLE usage_logs ADD COLUMN model TEXT DEFAULT ''`,
	}

	for _, m := range migrations {
		if _, err := db.Exec(m); err != nil {
			return fmt.Errorf("执行迁移失败: %w\nSQL: %s", err, m)
		}
	}

	for _, a := range alterStatements {
		db.Exec(a) // 忽略错误（列已存在时 SQLite 会报错）
	}

	// 创建 payment_log 索引（迁移完成后执行）
	for _, idx := range []string{
		`CREATE INDEX IF NOT EXISTS idx_payment_user ON payment_log(user_id)`,
		`CREATE INDEX IF NOT EXISTS idx_payment_status ON payment_log(status)`,
		`CREATE INDEX IF NOT EXISTS idx_payment_tx_hash ON payment_log(tx_hash)`,
		`CREATE INDEX IF NOT EXISTS idx_payment_created ON payment_log(created_at)`,
		`CREATE INDEX IF NOT EXISTS idx_usage_api_key ON usage_logs(api_key_id)`,
		`CREATE INDEX IF NOT EXISTS idx_usage_recorded ON usage_logs(recorded_at)`,
		`CREATE INDEX IF NOT EXISTS idx_emails_created ON emails(created_at)`,
		`CREATE INDEX IF NOT EXISTS idx_emails_message_id ON emails(message_id)`,
	} {
		db.Exec(idx)
	}

	// 邮件模块表
	for _, m := range []string{
		`CREATE TABLE IF NOT EXISTS emails (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			message_id TEXT NOT NULL,
			"from" TEXT NOT NULL DEFAULT '',
			"to" TEXT NOT NULL DEFAULT '',
			subject TEXT NOT NULL DEFAULT '',
			body_text TEXT NOT NULL DEFAULT '',
			body_html TEXT DEFAULT '',
			eml_path TEXT DEFAULT '',
			attach_count INTEGER DEFAULT 0,
			created_at INTEGER NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS email_keywords (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			keyword TEXT NOT NULL,
			action TEXT NOT NULL DEFAULT 'alert',
			enabled INTEGER NOT NULL DEFAULT 1,
			created_at INTEGER NOT NULL
		)`,
	} {
		if _, err := db.Exec(m); err != nil {
			return fmt.Errorf("执行邮件表迁移失败: %w", err)
		}
	}

	// 迁移：为现有用户创建默认工作组
	migrateWorkgroups(db)

	return nil
}

// migrateWorkgroups 为没有工作组的用户创建默认工作组，并将现有 keys 分配到默认组
func migrateWorkgroups(db *sql.DB) {
	now := time.Now().Unix()

	// 1. 为没有工作组的用户创建默认工作组（避免重名）
	rows, err := db.Query(
		`SELECT u.id FROM users u
		 WHERE NOT EXISTS (SELECT 1 FROM workgroups w WHERE w.user_id = u.id)
		 LIMIT 1000`,
	)
	if err != nil {
		return
	}
	defer rows.Close()

	for rows.Next() {
		var userID int64
		if err := rows.Scan(&userID); err != nil {
			continue
		}
		db.Exec(
			"INSERT INTO workgroups (user_id, name, description, created_at) VALUES (?, ?, ?, ?)",
			userID, "Default", "System default workgroup", now,
		)
	}

	// 2. 将 workgroup_id 为 NULL 的 key 分配到默认工作组
	db.Exec(`
		UPDATE api_keys
		SET workgroup_id = (
			SELECT w.id FROM workgroups w
			WHERE w.user_id = api_keys.user_id
			ORDER BY w.id LIMIT 1
		)
		WHERE workgroup_id IS NULL
	`)

	// 3. 重命名旧中文工作组名为 Default
	db.Exec(`UPDATE workgroups SET name = 'Default' WHERE name = '默认工作组'`)
}
