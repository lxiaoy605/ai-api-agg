package auth

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/ai-api-agg/backend/internal/middleware"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

// OAuthConfig OAuth 配置
type OAuthConfig struct {
	Google OAuthProvider `json:"google"`
	GitHub OAuthProvider `json:"github"`
}

// OAuthProvider 单个 OAuth 提供方配置
type OAuthProvider struct {
	ClientID     string `json:"client_id"`
	ClientSecret string `json:"client_secret"`
	RedirectURL  string `json:"redirect_url"`
}

// OAuthHandler OAuth 处理器
type OAuthHandler struct {
	db          *sql.DB
	jwtSecret   string
	config      OAuthConfig
	frontendURL string
}

// OAuthState 存储 OAuth state（防 CSRF）
type OAuthState struct {
	State     string
	Provider  string
	ExpiresAt int64
}

// NewOAuthHandler 创建 OAuth 处理器
func NewOAuthHandler(db *sql.DB, jwtSecret string, config OAuthConfig, frontendURL string) *OAuthHandler {
	return &OAuthHandler{db: db, jwtSecret: jwtSecret, config: config, frontendURL: frontendURL}
}

// generateState 生成随机 state token
func generateState() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

// LoginGoogle 发起 Google OAuth GET /auth/oauth/google
func (h *OAuthHandler) LoginGoogle(c *gin.Context) {
	h.oauthLogin(c, "google", "https://accounts.google.com/o/oauth/v2/auth", map[string]string{
		"scope":         "https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile",
		"response_type": "code",
	})
}

// LoginGitHub 发起 GitHub OAuth GET /auth/oauth/github
func (h *OAuthHandler) LoginGitHub(c *gin.Context) {
	h.oauthLogin(c, "github", "https://github.com/login/oauth/authorize", map[string]string{
		"scope": "read:user user:email",
	})
}

func (h *OAuthHandler) oauthLogin(c *gin.Context, provider string, authURL string, extra map[string]string) {
	var cfg OAuthProvider
	switch provider {
	case "google":
		cfg = h.config.Google
	case "github":
		cfg = h.config.GitHub
	default:
		middleware.BadRequest(c, "不支持的 OAuth 提供方")
		return
	}

	if cfg.ClientID == "" {
		middleware.InternalError(c, fmt.Sprintf("%s OAuth 未配置", provider))
		return
	}

	state, err := generateState()
	if err != nil {
		middleware.InternalError(c, "生成 state 失败")
		return
	}

	params := url.Values{
		"client_id":    {cfg.ClientID},
		"redirect_uri": {cfg.RedirectURL},
		"state":        {state},
		"response_type": {"code"},
	}
	for k, v := range extra {
		params.Set(k, v)
	}

	redirectTo := authURL + "?" + params.Encode()
	c.Redirect(http.StatusTemporaryRedirect, redirectTo)
}

// CallbackGoogle Google OAuth 回调 GET /auth/oauth/google/callback
func (h *OAuthHandler) CallbackGoogle(c *gin.Context) {
	code := c.Query("code")
	if code == "" {
		middleware.BadRequest(c, "缺少授权 code")
		return
	}

	// 用 code 换 access token
	tokenResp, err := h.exchangeCode(
		"https://oauth2.googleapis.com/token",
		h.config.Google,
		code,
	)
	if err != nil {
		middleware.InternalError(c, "换取 token 失败: "+err.Error())
		return
	}

	// 获取用户信息
	userInfo, err := h.fetchGoogleUser(tokenResp.AccessToken)
	if err != nil {
		middleware.InternalError(c, "获取用户信息失败: "+err.Error())
		return
	}

	h.handleOAuthUser(c, userInfo.Email, userInfo.Name, "google")
}

// CallbackGitHub GitHub OAuth 回调 GET /auth/oauth/github/callback
func (h *OAuthHandler) CallbackGitHub(c *gin.Context) {
	code := c.Query("code")
	if code == "" {
		middleware.BadRequest(c, "缺少授权 code")
		return
	}

	// 用 code 换 access token
	tokenResp, err := h.exchangeGitHubCode(code)
	if err != nil {
		middleware.InternalError(c, "换取 token 失败: "+err.Error())
		return
	}

	// 获取用户信息
	userInfo, err := h.fetchGitHubUser(tokenResp.AccessToken)
	if err != nil {
		middleware.InternalError(c, "获取用户信息失败: "+err.Error())
		return
	}

	h.handleOAuthUser(c, userInfo.Email, userInfo.Name, "github")
}

// OAuthTokenResponse OAuth token 交换响应
type OAuthTokenResponse struct {
	AccessToken string `json:"access_token"`
}

// OAuthUserInfo OAuth 用户信息
type OAuthUserInfo struct {
	Email string
	Name  string
}

func (h *OAuthHandler) exchangeCode(tokenURL string, cfg OAuthProvider, code string) (*OAuthTokenResponse, error) {
	data := url.Values{
		"client_id":     {cfg.ClientID},
		"client_secret": {cfg.ClientSecret},
		"code":          {code},
		"redirect_uri":  {cfg.RedirectURL},
		"grant_type":    {"authorization_code"},
	}

	resp, err := http.PostForm(tokenURL, data)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("OAuth 服务返回错误: %s", string(body))
	}

	var tokenResp OAuthTokenResponse
	if err := json.Unmarshal(body, &tokenResp); err != nil {
		return nil, err
	}

	return &tokenResp, nil
}

func (h *OAuthHandler) exchangeGitHubCode(code string) (*OAuthTokenResponse, error) {
	cfg := h.config.GitHub
	data := url.Values{
		"client_id":     {cfg.ClientID},
		"client_secret": {cfg.ClientSecret},
		"code":          {code},
		"redirect_uri":  {cfg.RedirectURL},
	}

	req, _ := http.NewRequest("POST", "https://github.com/login/oauth/access_token", nil)
	req.Header.Set("Accept", "application/json")
	req.URL.RawQuery = data.Encode()

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var tokenResp OAuthTokenResponse
	if err := json.Unmarshal(body, &tokenResp); err != nil {
		// GitHub 返回 form-encoded
		values, _ := url.ParseQuery(string(body))
		if at := values.Get("access_token"); at != "" {
			return &OAuthTokenResponse{AccessToken: at}, nil
		}
		return nil, fmt.Errorf("GitHub 返回格式错误: %s", string(body))
	}

	return &tokenResp, nil
}

func (h *OAuthHandler) fetchGoogleUser(accessToken string) (*OAuthUserInfo, error) {
	req, _ := http.NewRequest("GET", "https://www.googleapis.com/oauth2/v3/userinfo", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	var info struct {
		Email string `json:"email"`
		Name  string `json:"name"`
	}
	if err := json.Unmarshal(body, &info); err != nil {
		return nil, err
	}

	return &OAuthUserInfo{Email: info.Email, Name: info.Name}, nil
}

func (h *OAuthHandler) fetchGitHubUser(accessToken string) (*OAuthUserInfo, error) {
	req, _ := http.NewRequest("GET", "https://api.github.com/user", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Accept", "application/vnd.github.v3+json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	var user struct {
		Login string `json:"login"`
		Name  string `json:"name"`
		Email string `json:"email"`
	}
	if err := json.Unmarshal(body, &user); err != nil {
		return nil, err
	}

	// GitHub email 可能为空，需要再请求 /user/emails
	email := user.Email
	if email == "" {
		emails, _ := h.fetchGitHubEmails(accessToken)
		if len(emails) > 0 {
			email = emails[0]
		}
	}

	name := user.Name
	if name == "" {
		name = user.Login
	}

	return &OAuthUserInfo{Email: email, Name: name}, nil
}

func (h *OAuthHandler) fetchGitHubEmails(accessToken string) ([]string, error) {
	req, _ := http.NewRequest("GET", "https://api.github.com/user/emails", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Accept", "application/vnd.github.v3+json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	var emails []struct {
		Email    string `json:"email"`
		Primary  bool   `json:"primary"`
		Verified bool   `json:"verified"`
	}
	if err := json.Unmarshal(body, &emails); err != nil {
		return nil, err
	}

	var result []string
	for _, e := range emails {
		if e.Verified {
			result = append(result, e.Email)
		}
	}
	return result, nil
}

// handleOAuthUser 统一处理 OAuth 用户：查找或创建 → 返回 JWT
func (h *OAuthHandler) handleOAuthUser(c *gin.Context, email, name, provider string) {
	if email == "" {
		middleware.BadRequest(c, fmt.Sprintf("无法从 %s 获取邮箱地址", provider))
		return
	}

	var userID int64
	var role string
	var quota int64

	err := h.db.QueryRow("SELECT id, role, quota FROM users WHERE email = ?", email).
		Scan(&userID, &role, &quota)

	if err == sql.ErrNoRows {
		// 新用户：自动注册
		defaultQuota := int64(500000)
		now := time.Now().Unix()
		result, err := h.db.Exec(
			"INSERT INTO users (email, password_hash, role, quota, created_at, updated_at) VALUES (?, ?, 'user', ?, ?, ?)",
			email, "oauth:"+provider, defaultQuota, now, now,
		)
		if err != nil {
			middleware.InternalError(c, "创建 OAuth 用户失败")
			return
		}
		userID, _ = result.LastInsertId()
		role = "user"
		quota = defaultQuota
	} else if err != nil {
		middleware.InternalError(c, "查询用户失败")
		return
	}

	// 生成 JWT
	token, err := h.generateOAuthToken(userID, role)
	if err != nil {
		middleware.InternalError(c, "生成令牌失败")
		return
	}

	// 重定向到前端 OAuth 回调页
	redirectURL := fmt.Sprintf("%s/login?oauth_token=%s", h.frontendURL, token)
	c.Redirect(http.StatusTemporaryRedirect, redirectURL)
}

func (h *OAuthHandler) generateOAuthToken(userID int64, role string) (string, error) {
	now := time.Now()
	claims := map[string]interface{}{
		"user_id": userID,
		"role":    role,
		"exp":     now.Add(24 * time.Hour).Unix(),
		"iat":     now.Unix(),
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims(claims)).
		SignedString([]byte(h.jwtSecret))
}
