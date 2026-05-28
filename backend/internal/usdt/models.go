package usdt

// PaymentLog 支付记录
type PaymentLog struct {
	ID          int64  `json:"id"`
	UserID      int64  `json:"user_id"`
	Username    string `json:"username,omitempty"`
	PaymentID   string `json:"payment_id"` // Stripe Session ID / USDT TxHash
	Provider    string `json:"provider"`   // "stripe" / "usdt_trc20" / "usdt_erc20"
	AmountCents int64  `json:"amount_cents"`
	Currency    string `json:"currency"`
	Tokens      int64  `json:"tokens"`
	Bonus       int64  `json:"bonus"`
	Status      string `json:"status"` // pending/completed/refunded/disputed/failed
	Memo        string `json:"memo,omitempty"`
	TxHash      string `json:"tx_hash,omitempty"`
	Notes       string `json:"notes,omitempty"`
	CreatedAt   int64  `json:"created_at"`
	UpdatedAt   int64  `json:"updated_at,omitempty"`
	CompletedAt int64  `json:"completed_at,omitempty"`
}

// 状态常量
const (
	StatusPending   = "pending"
	StatusCompleted = "completed"
	StatusRefunded  = "refunded"
	StatusDisputed  = "disputed"
	StatusFailed    = "failed"
)

// 提供商常量
const (
	ProviderStripe   = "stripe"
	ProviderUSDTTron = "usdt_trc20"
	ProviderUSDTEth  = "usdt_erc20"
)

// USDT 精度常量 (TRC-20/ERC-20 均为 6 位小数)
const USDTDecimals = 1_000_000

// DDL 建表语句
const CreatePaymentLogTable = `
CREATE TABLE IF NOT EXISTS payment_log (
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
);

CREATE INDEX IF NOT EXISTS idx_payment_user ON payment_log(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_status ON payment_log(status);
CREATE INDEX IF NOT EXISTS idx_payment_tx_hash ON payment_log(tx_hash);
CREATE INDEX IF NOT EXISTS idx_payment_created ON payment_log(created_at);
`
