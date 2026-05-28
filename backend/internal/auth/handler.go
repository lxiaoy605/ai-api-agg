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
		middleware.BadRequest(c, "请提供有效的邮箱和密码（密码至少6位）")
		return
	}

	// 校验邮箱格式
	if _, err := mail.ParseAddress(req.Email); err != nil {
		middleware.BadRequest(c, "邮箱格式无效")
		return
	}

	// 检查邮箱唯一性
	var existingID int64
	err := h.db.QueryRow("SELECT id FROM users WHERE email = ?", req.Email).Scan(&existingID)
	if err == nil {
		middleware.BadRequest(c, "该邮箱已被注册")
		return
	}

	// bcrypt 哈希密码
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		middleware.InternalError(c, "密码加密失败")
		return
	}

	// 插入用户
	now := time.Now().Unix()
	result, err := h.db.Exec(
		"INSERT INTO users (email, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?)",
		req.Email, string(hashedPassword), now, now,
	)
	if err != nil {
		middleware.InternalError(c, "创建用户失败")
		return
	}

	userID, _ := result.LastInsertId()

	// 生成 JWT token
	token, err := h.generateToken(userID, "user")
	if err != nil {
		middleware.InternalError(c, "生成令牌失败")
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
		middleware.BadRequest(c, "请提供邮箱和密码")
		return
	}

	// 查找用户
	var id int64
	var email, passwordHash, role string
	err := h.db.QueryRow("SELECT id, email, password_hash, role FROM users WHERE email = ?", req.Email).
		Scan(&id, &email, &passwordHash, &role)
	if err == sql.ErrNoRows {
		middleware.Unauthorized(c, "邮箱或密码错误")
		return
	}
	if err != nil {
		middleware.InternalError(c, "查询用户失败")
		return
	}

	// 验证密码
	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)); err != nil {
		middleware.Unauthorized(c, "邮箱或密码错误")
		return
	}

	// 生成 JWT token
	token, err := h.generateToken(id, role)
	if err != nil {
		middleware.InternalError(c, "生成令牌失败")
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
		middleware.NotFound(c, "用户不存在")
		return
	}
	if err != nil {
		middleware.InternalError(c, "查询用户失败")
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
