package database

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"

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
	}

	// 兼容旧表：尝试添加可能缺失的列
	alterStatements := []string{
		`ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'user'`,
		`ALTER TABLE users ADD COLUMN quota INTEGER NOT NULL DEFAULT 0`,
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
	} {
		db.Exec(idx)
	}

	return nil
}
