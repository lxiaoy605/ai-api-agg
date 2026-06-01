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

// ========== 自定义类型 ==========

// FlexibleID NOWPayments payment_id 有时是字符串有时是数字，统一处理
type FlexibleID string

func (f *FlexibleID) UnmarshalJSON(data []byte) error {
	var s string
	if err := json.Unmarshal(data, &s); err == nil {
		*f = FlexibleID(s)
		return nil
	}
	var n float64
	if err := json.Unmarshal(data, &n); err == nil {
		*f = FlexibleID(fmt.Sprintf("%.0f", n))
		return nil
	}
	return fmt.Errorf("FlexibleID: cannot unmarshal %s", string(data))
}

func (f FlexibleID) String() string { return string(f) }

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
	PaymentID        FlexibleID `json:"payment_id"`
	PaymentStatus    string     `json:"payment_status"`
	PayAddress       string     `json:"pay_address"`
	PayAmount        float64    `json:"pay_amount"`
	PriceAmount      float64    `json:"price_amount"`
	PriceCurrency    string     `json:"price_currency"`
	PayCurrency      string     `json:"pay_currency"`
	OrderID          string     `json:"order_id"`
	OrderDescription string     `json:"order_description"`
	Network          string     `json:"network"`
	CreatedAt        string     `json:"created_at"`
	UpdatedAt        string     `json:"updated_at"`
}

// Currency 可用币种
type Currency struct {
	Code       string `json:"code"`
	Name       string `json:"name"`
	Enable     bool   `json:"enable"`
	Network    string `json:"network"`
	LogoURL    string `json:"logo_url"`
	Precision  int    `json:"precision"`
	DepositFee string `json:"deposit_fee"`
}

// EstimateResponse 预估响应
type EstimateResponse struct {
	CurrencyFrom    string  `json:"currency_from"`
	CurrencyTo      string  `json:"currency_to"`
	EstimatedAmount float64 `json:"estimated_amount"`
}

// MinAmountResponse 最低金额响应
type MinAmountResponse struct {
	CurrencyFrom string  `json:"currency_from"`
	CurrencyTo   string  `json:"currency_to"`
	MinAmount    float64 `json:"min_amount"`
}

// ErrorResponse NOWPayments 错误响应
type ErrorResponse struct {
	StatusCode int    `json:"statusCode"`
	Code       string `json:"code"`
	Message    string `json:"message"`
}

// ========== Client ==========

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
		apiKey:     apiKey,
		ipnSecret:  ipnSecret,
		baseURL:    strings.TrimRight(baseURL, "/"),
		httpClient:  &http.Client{Timeout: 20 * time.Second},
	}
}

func (c *Client) doRequest(method, path string, body interface{}, result interface{}) error {
	url := c.baseURL + path

	var reqBody io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("failed to marshal request: %w", err)
		}
		reqBody = bytes.NewReader(data)
	}

	req, err := http.NewRequest(method, url, reqBody)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("x-api-key", c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	respData, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode >= 400 {
		var errResp ErrorResponse
		if json.Unmarshal(respData, &errResp) == nil && errResp.Message != "" {
			return fmt.Errorf("%s", errResp.Message)
		}
		return fmt.Errorf("API error %d: %s", resp.StatusCode, string(respData))
	}

	if result != nil {
		if err := json.Unmarshal(respData, result); err != nil {
			return fmt.Errorf("failed to parse response: %w, body: %s", err, string(respData))
		}
	}
	return nil
}

// ========== 支付接口 ==========

// CreatePayment 创建支付订单
func (c *Client) CreatePayment(req *PaymentRequest) (*PaymentResponse, error) {
	var resp PaymentResponse
	if err := c.doRequest("POST", "/payment", req, &resp); err != nil {
		return nil, err
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

// GetMinAmount 获取最低支付金额
func (c *Client) GetMinAmount(currencyFrom, currencyTo string) (*MinAmountResponse, error) {
	path := fmt.Sprintf("/min-amount/%s/%s", currencyFrom, currencyTo)
	var resp MinAmountResponse
	if err := c.doRequest("GET", path, nil, &resp); err != nil {
		return nil, err
	}
	return &resp, nil
}

// GetEstimate 获取估价
func (c *Client) GetEstimate(amount float64, currencyFrom, currencyTo string) (*EstimateResponse, error) {
	path := fmt.Sprintf("/estimate?amount=%.2f&currency_from=%s&currency_to=%s", amount, currencyFrom, currencyTo)
	var resp EstimateResponse
	if err := c.doRequest("GET", path, nil, &resp); err != nil {
		return nil, err
	}
	return &resp, nil
}

// VerifyIPN 验证 IPN 回调签名
func (c *Client) VerifyIPN(payload []byte, receivedHMAC string) bool {
	if c.ipnSecret == "" {
		return false
	}
	computedHMAC := computeHMAC(c.ipnSecret, payload)
	return computedHMAC == receivedHMAC
}

func computeHMAC(secret string, payload []byte) string {
	mac := hmac.New(sha512.New, []byte(secret))
	mac.Write(payload)
	return hex.EncodeToString(mac.Sum(nil))
}

// SortIPNPayload 排序 IPN 回调的 JSON 字段
func SortIPNPayload(raw []byte) ([]byte, error) {
	var data map[string]interface{}
	if err := json.Unmarshal(raw, &data); err != nil {
		return nil, err
	}

	keys := make([]string, 0, len(data))
	for k := range data {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	var buf bytes.Buffer
	buf.WriteString("{")
	for i, k := range keys {
		if i > 0 {
			buf.WriteString(",")
		}
		kb, _ := json.Marshal(k)
		vb, _ := json.Marshal(data[k])
		buf.Write(kb)
		buf.WriteString(":")
		buf.Write(vb)
	}
	buf.WriteString("}")
	return buf.Bytes(), nil
}
