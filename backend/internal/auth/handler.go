package auth

import (
	"database/sql"
	"net/mail"
	"time"

	"github.com/ai-api-agg/backend/internal/middleware"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

// Handler 认证处理器
type Handler struct {
	db        *sql.DB
	jwtSecret string
}

// NewHandler 创建认证处理器
func NewHandler(db *sql.DB, jwtSecret string) *Handler {
	return &Handler{db: db, jwtSecret: jwtSecret}
}

// RegisterRequest 注册请求
type RegisterRequest struct {
	Email    string `json:"email" binding:"required"`
	Password string `json:"password" binding:"required,min=6"`
}

// LoginRequest 登录请求
type LoginRequest struct {
	Email    string `json:"email" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// Register 用户注册 POST /auth/register
func (h *Handler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		middleware.BadRequest(c, "Please provide email and password (min 6 characters)")
		return
	}

	// 校验邮箱格式
	if _, err := mail.ParseAddress(req.Email); err != nil {
		middleware.BadRequest(c, "Invalid email format")
		return
	}

	// 检查邮箱唯一性
	var existingID int64
	err := h.db.QueryRow("SELECT id FROM users WHERE email = ?", req.Email).Scan(&existingID)
	if err == nil {
		middleware.BadRequest(c, "Email already registered")
		return
	}

	// bcrypt 哈希密码
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		middleware.InternalError(c, "Failed to hash password")
		return
	}

	// 插入用户（默认赠送 $1 试用配额，500000 token/$）
	now := time.Now().Unix()
	defaultQuota := 500000 // $1 * 500k tokens/$ 试用额度
	result, err := h.db.Exec(
		"INSERT INTO users (email, password_hash, role, quota, created_at, updated_at) VALUES (?, ?, 'user', ?, ?, ?)",
		req.Email, string(hashedPassword), defaultQuota, now, now,
	)
	if err != nil {
		middleware.InternalError(c, "Failed to create user")
		return
	}

	userID, _ := result.LastInsertId()

	// 创建用户默认工作组
	h.db.Exec(
		"INSERT INTO workgroups (user_id, name, description, created_at) VALUES (?, ?, ?, ?)",
		userID, "Default", "System default workgroup", now,
	)

	// 生成 JWT token
	token, err := h.generateToken(userID, "user")
	if err != nil {
		middleware.InternalError(c, "Failed to generate token")
		return
	}

	middleware.Success(c, gin.H{
		"user_id": userID,
		"email":   req.Email,
		"token":   token,
	})
}

// Login 用户登录 POST /auth/login
func (h *Handler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		middleware.BadRequest(c, "Please provide email and password")
		return
	}

	// 查找用户
	var id int64
	var email, passwordHash, role string
	err := h.db.QueryRow("SELECT id, email, password_hash, role FROM users WHERE email = ?", req.Email).
		Scan(&id, &email, &passwordHash, &role)
	if err == sql.ErrNoRows {
		middleware.Unauthorized(c, "Invalid email or password")
		return
	}
	if err != nil {
		middleware.InternalError(c, "Failed to query user")
		return
	}

	// 验证密码
	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)); err != nil {
		middleware.Unauthorized(c, "Invalid email or password")
		return
	}

	// 生成 JWT token
	token, err := h.generateToken(id, role)
	if err != nil {
		middleware.InternalError(c, "Failed to generate token")
		return
	}

	middleware.Success(c, gin.H{
		"user_id": id,
		"email":   email,
		"token":   token,
	})
}

// Me 获取当前用户信息 GET /auth/me
func (h *Handler) Me(c *gin.Context) {
	userID := c.GetInt64("user_id")

	var id int64
	var email, role string
	var quota int64
	var createdAt, updatedAt int64
	err := h.db.QueryRow("SELECT id, email, role, quota, created_at, updated_at FROM users WHERE id = ?", userID).
		Scan(&id, &email, &role, &quota, &createdAt, &updatedAt)
	if err == sql.ErrNoRows {
		middleware.NotFound(c, "User not found")
		return
	}
	if err != nil {
		middleware.InternalError(c, "Failed to query user")
		return
	}

	middleware.Success(c, gin.H{
		"id":         id,
		"email":      email,
		"role":       role,
		"quota":      quota,
		"created_at": createdAt,
		"updated_at": updatedAt,
	})
}

// generateToken 生成 JWT token（含 user_id, role, exp）
func (h *Handler) generateToken(userID int64, role string) (string, error) {
	claims := jwt.MapClaims{
		"user_id": userID,
		"role":    role,
		"exp":     time.Now().Add(24 * time.Hour).Unix(),
		"iat":     time.Now().Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(h.jwtSecret))
}

// ForgotPasswordRequest 忘记密码请求
type ForgotPasswordRequest struct {
	Email string `json:"email" binding:"required"`
}

// ResetPasswordRequest 重置密码请求
type ResetPasswordRequest struct {
	Token       string `json:"token" binding:"required"`
	NewPassword string `json:"new_password" binding:"required,min=6"`
}

// ForgotPassword 发送重置密码令牌 POST /auth/forgot-password
func (h *Handler) ForgotPassword(c *gin.Context) {
	var req ForgotPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		middleware.BadRequest(c, "Please provide email")
		return
	}

	// 检查用户是否存在（不透露是否存在，统一返回 ok）
	var userID int64
	var role string
	err := h.db.QueryRow("SELECT id, role FROM users WHERE email = ?", req.Email).Scan(&userID, &role)
	if err == sql.ErrNoRows {
		// 不透露用户是否存在，统一返回成功
		middleware.Success(c, gin.H{"message": "If the email is registered, a reset link will be sent"})
		return
	}
	if err != nil {
		middleware.InternalError(c, "Failed to query user")
		return
	}

	// 生成重置令牌（15 分钟有效）
	claims := jwt.MapClaims{
		"user_id": userID,
		"email":   req.Email,
		"purpose": "reset_password",
		"exp":     time.Now().Add(15 * time.Minute).Unix(),
		"iat":     time.Now().Unix(),
	}
	resetToken, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(h.jwtSecret))
	if err != nil {
		middleware.InternalError(c, "Failed to generate reset token")
		return
	}

	// TODO: 发送邮件（当前开发环境直接返回 token）
	middleware.Success(c, gin.H{
		"message":     "If the email is registered, a reset link will be sent",
		"reset_token": resetToken, // 开发阶段直接返回，后续改为邮件发送
	})
}

// ResetPassword 使用令牌重置密码 POST /auth/reset-password
func (h *Handler) ResetPassword(c *gin.Context) {
	var req ResetPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		middleware.BadRequest(c, "Please provide token and new password (min 6 chars)")
		return
	}

	// 验证重置令牌
	token, err := jwt.Parse(req.Token, func(t *jwt.Token) (interface{}, error) {
		return []byte(h.jwtSecret), nil
	})
	if err != nil || !token.Valid {
		middleware.BadRequest(c, "Reset token is invalid or expired")
		return
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		middleware.BadRequest(c, "Invalid reset token format")
		return
	}

	// 验证用途
	purpose, _ := claims["purpose"].(string)
	if purpose != "reset_password" {
		middleware.BadRequest(c, "Invalid token purpose")
		return
	}

	userIDFloat, ok := claims["user_id"].(float64)
	if !ok {
		middleware.BadRequest(c, "Token missing user info")
		return
	}
	userID := int64(userIDFloat)

	// 加密新密码
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		middleware.InternalError(c, "Failed to hash password")
		return
	}

	// 更新密码
	now := time.Now().Unix()
	_, err = h.db.Exec("UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?",
		string(hashedPassword), now, userID)
	if err != nil {
		middleware.InternalError(c, "Failed to update password")
		return
	}

	middleware.Success(c, gin.H{"message": "Password reset successfully"})
}
