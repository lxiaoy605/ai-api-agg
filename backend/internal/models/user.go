package models

// User 用户模型
type User struct {
	ID           int64  `json:"id"`
	Email        string `json:"email"`
	PasswordHash string `json:"-"` // 永远不序列化
	Role         string `json:"role"`
	Quota        int64  `json:"quota"`
	CreatedAt    int64  `json:"created_at"`
	UpdatedAt    int64  `json:"updated_at"`
}
