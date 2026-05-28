package payment

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha512"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"time"
)

// ========== 数据结构 ==========

// PaymentRequest 创建支付请求
type PaymentRequest struct {
	PriceAmount      float64 `json:"price_amount"`
	PriceCurrency    string  `json:"price_currency"`
	PayCurrency      string  `json:"pay_currency"`
	IPNCallbackURL   string  `json:"ipn_callback_url,omitempty"`
	OrderID          string  `json:"order_id"`
	OrderDescription string  `json:"order_description"`
	SuccessURL       string  `json:"success_url,omitempty"`
	CancelURL        string  `json:"cancel_url,omitempty"`
}

// PaymentResponse NOWPayments 支付响应
type PaymentResponse struct {
	PaymentID        int64   `json:"payment_id"`
	PaymentStatus    string  `json:"payment_status"`
	PayAddress       string  `json:"pay_address"`
	PayAmount        float64 `json:"pay_amount"`
	PriceAmount      float64 `json:"price_amount"`
	PriceCurrency    string  `json:"price_currency"`
	PayCurrency      string  `json:"pay_currency"`
	OrderID          string  `json:"order_id"`
	OrderDescription string  `json:"order_description"`
	Network          string  `json:"network"`
	CreatedAt        string  `json:"created_at"`
	UpdatedAt        string  `json:"updated_at"`
}

// Currency 可用币种
type Currency struct {
	Code       string `json:"code"`
	Name       string `json:"name"`
	Enable     bool   `json:"enable"`
	Network    string `json:"network"`
	LogoURL    string `json:"logo_url"`
	Precision  int    `json:"precision"`
}

// ========== 客户端 ==========

// Client NOWPayments API 客户端
type Client struct {
	apiKey     string
	ipnSecret  string
	baseURL    string
	httpClient *http.Client
}

// NewClient 创建 NOWPayments 客户端
func NewClient(apiKey, ipnSecret, baseURL string) *Client {
	if baseURL == "" {
		baseURL = "https://api.nowpayments.io/v1"
	}
	return &Client{
		apiKey:    apiKey,
		ipnSecret: ipnSecret,
		baseURL:   strings.TrimRight(baseURL, "/"),
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// ========== API 方法 ==========

// CreatePayment 创建支付订单
func (c *Client) CreatePayment(priceAmount float64, payCurrency, orderID, description, ipnURL, successURL, cancelURL string) (*PaymentResponse, error) {
	req := PaymentRequest{
		PriceAmount:      priceAmount,
		PriceCurrency:    "usd",
		PayCurrency:      payCurrency,
		IPNCallbackURL:   ipnURL,
		OrderID:          orderID,
		OrderDescription: description,
		SuccessURL:       successURL,
		CancelURL:        cancelURL,
	}

	var resp PaymentResponse
	if err := c.doRequest("POST", "/payment", req, &resp); err != nil {
		return nil, fmt.Errorf("创建支付失败: %w", err)
	}
	return &resp, nil
}

// GetPaymentStatus 查询支付状态
func (c *Client) GetPaymentStatus(paymentID string) (*PaymentResponse, error) {
	var resp PaymentResponse
	if err := c.doRequest("GET", "/payment/"+paymentID, nil, &resp); err != nil {
		return nil, fmt.Errorf("查询支付状态失败: %w", err)
	}
	return &resp, nil
}

// GetCurrencies 获取可用币种列表
func (c *Client) GetCurrencies() ([]Currency, error) {
	var resp []Currency
	if err := c.doRequest("GET", "/currencies", nil, &resp); err != nil {
		return nil, fmt.Errorf("获取币种列表失败: %w", err)
	}

	// 仅返回启用的币种
	var enabled []Currency
	for _, cur := range resp {
		if cur.Enable {
			enabled = append(enabled, cur)
		}
	}
	return enabled, nil
}

// VerifyIPNSignature 验证 IPN 回调签名
// 签名算法: HMAC-SHA512(ipnSecret, JSON.stringify(sortedKeys(body)))
func (c *Client) VerifyIPNSignature(body []byte, sigHeader string) bool {
	if c.ipnSecret == "" {
		// 未配置 IPN secret 时跳过验证
		return true
	}

	// 将 body JSON 解析并按 key 排序后重新序列化
	var data map[string]interface{}
	if err := json.Unmarshal(body, &data); err != nil {
		return false
	}

	sortedJSON, err := json.Marshal(sortedMap(data))
	if err != nil {
		return false
	}

	mac := hmac.New(sha512.New, []byte(c.ipnSecret))
	mac.Write(sortedJSON)
	expected := hex.EncodeToString(mac.Sum(nil))

	return hmac.Equal([]byte(expected), []byte(sigHeader))
}

// ========== 内部方法 ==========

// doRequest 发送 HTTP 请求
func (c *Client) doRequest(method, path string, body interface{}, result interface{}) error {
	url := c.baseURL + path

	var reqBody io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("序列化请求体失败: %w", err)
		}
		reqBody = bytes.NewReader(data)
	}

	req, err := http.NewRequest(method, url, reqBody)
	if err != nil {
		return fmt.Errorf("创建 HTTP 请求失败: %w", err)
	}

	req.Header.Set("x-api-key", c.apiKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("HTTP 请求失败: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("读取响应体失败: %w", err)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("API 返回错误 %d: %s", resp.StatusCode, string(respBody))
	}

	if result != nil {
		if err := json.Unmarshal(respBody, result); err != nil {
			return fmt.Errorf("解析响应失败: %w, body: %s", err, string(respBody))
		}
	}

	return nil
}

// sortedMap 递归排序 map 的 key（用于 IPN 签名验证）
func sortedMap(data map[string]interface{}) map[string]interface{} {
	result := make(map[string]interface{})
	keys := make([]string, 0, len(data))
	for k := range data {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	for _, k := range keys {
		v := data[k]
		if nested, ok := v.(map[string]interface{}); ok {
			result[k] = sortedMap(nested)
		} else {
			result[k] = v
		}
	}
	return result
}
