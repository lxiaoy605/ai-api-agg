package usdt

import (
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/ai-api-agg/backend/internal/audit"
	"github.com/ai-api-agg/backend/internal/notify"
)

// Monitor USDT 自动监听引擎
type Monitor struct {
	db             *sql.DB
	tg             *notify.Telegram
	notif          *notify.Center
	walletAddr     string // TRC-20 收款地址
	tronGridKey    string // TronGrid Pro API Key（可选）
	minConfirm     int    // 最少确认数
	minUSDT        float64
	centsPerToken  float64

	// 轮询控制
	mu         sync.Mutex
	running    bool
	stopCh     chan struct{}

	// 最近轮询的最后交易时间戳（毫秒），防重复
	lastTimestamp int64
}

// NewMonitor 创建 USDT 监听器
func NewMonitor(db *sql.DB, tg *notify.Telegram, notifCenter *notify.Center) *Monitor {
	return &Monitor{
		db:            db,
		tg:            tg,
		notif:         notifCenter,
		walletAddr:    os.Getenv("USDT_TRC20_WALLET"),
		tronGridKey:   os.Getenv("TRON_PRO_API_KEY"),
		minConfirm:    getEnvInt("USDT_MIN_CONFIRM", 12),
		minUSDT:       5.0,
		centsPerToken: getEnvFloat("USDT_CENTS_PER_TOKEN", 0.01),
		stopCh:        make(chan struct{}),
	}
}

// Start 启动轮询引擎
func (m *Monitor) Start(pollInterval time.Duration) {
	m.mu.Lock()
	if m.running {
		m.mu.Unlock()
		log.Println("[USDT] 监听器已在运行中，跳过启动")
		return
	}
	m.running = true
	m.mu.Unlock()

	if m.walletAddr == "" {
		log.Println("[USDT] 未配置 USDT_TRC20_WALLET 环境变量，监听器不启动")
		return
	}

	log.Printf("[USDT] 监听器启动: 钱包=%s 确认数=%d 最小金额=$%.2f 间隔=%v",
		m.walletAddr, m.minConfirm, m.minUSDT, pollInterval)

	ticker := time.NewTicker(pollInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			m.pollTransactions()
		case <-m.stopCh:
			log.Println("[USDT] 监听器收到停止信号，正在退出...")
			return
		}
	}
}

// Stop 停止监听器
func (m *Monitor) Stop() {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.running {
		close(m.stopCh)
		m.running = false
	}
}

// pollTransactions 拉取并处理交易
func (m *Monitor) pollTransactions() {
	// 查询最近一段时间（从上次检查点起，最多 10 分钟窗口）
	since := m.lastTimestamp
	if since == 0 {
		since = time.Now().Add(-10 * time.Minute).UnixMilli()
	}

	url := fmt.Sprintf(
		"https://api.trongrid.io/v1/accounts/%s/transactions/trc20?limit=50&only_confirmed=true&min_timestamp=%d",
		m.walletAddr, since,
	)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		log.Printf("[USDT] 创建请求失败: %v", err)
		return
	}
	req.Header.Set("Accept", "application/json")
	if m.tronGridKey != "" {
		req.Header.Set("TRON-PRO-API-KEY", m.tronGridKey)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		log.Printf("[USDT] TronGrid API 请求失败: %v", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		log.Printf("[USDT] TronGrid API 返回 %d", resp.StatusCode)
		return
	}

	var result tronGridResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		log.Printf("[USDT] 解析 TronGrid 响应失败: %v", err)
		return
	}

	if len(result.Data) == 0 {
		return
	}

	log.Printf("[USDT] 拉取到 %d 条 TRC-20 交易", len(result.Data))

	for _, tx := range result.Data {
		m.processTransaction(tx)
	}

	// 更新检查点
	if len(result.Data) > 0 {
		m.lastTimestamp = result.Data[0].BlockTimestamp + 1
	}
}

// processTransaction 处理单笔交易
func (m *Monitor) processTransaction(tx tronGridTransaction) {
	// 只处理 USDT 转入
	if tx.TokenInfo.Symbol != "USDT" {
		return
	}
	if !strings.EqualFold(tx.To, m.walletAddr) {
		return
	}
	if tx.Type != "Transfer" {
		return
	}

	txHash := tx.TransactionID

	// 幂等性检查
	var count int
	if err := m.db.QueryRow("SELECT COUNT(*) FROM payment_log WHERE tx_hash = ?", txHash).Scan(&count); err != nil {
		log.Printf("[USDT] 幂等性检查失败: tx=%s err=%v", txHash[:16], err)
		return
	}
	if count > 0 {
		return
	}

	// 解析金额
	rawValue, err := strconv.ParseFloat(tx.Value, 64)
	if err != nil {
		log.Printf("[USDT] 金额解析失败: tx=%s value=%s", txHash[:16], tx.Value)
		return
	}
	usdtAmount := rawValue / USDTDecimals
	if usdtAmount < m.minUSDT {
		log.Printf("[USDT] 金额 $%.2f < 最小 $%.2f，跳过 tx=%s", usdtAmount, m.minUSDT, txHash[:16])
		return
	}

	// 检查确认数
	confirmations := m.getConfirmations(txHash)
	if confirmations < m.minConfirm {
		log.Printf("[USDT] 确认数 %d/%d，等待 tx=%s", confirmations, m.minConfirm, txHash[:16])
		return
	}

	// 提取 Memo 获取用户 ID
	userID := m.extractUserFromMemo(txHash)
	if userID == 0 {
		log.Printf("[USDT] 无有效 Memo，待人工处理 tx=%s", txHash[:16])
		_, _ = m.db.Exec(
			`INSERT OR IGNORE INTO payment_log (user_id, payment_id, provider, amount_cents, tokens, status, memo, tx_hash, notes, created_at)
			 VALUES (0, ?, ?, ?, 0, ?, ?, ?, ?, ?)`,
			txHash, ProviderUSDTTron, int(usdtAmount*100), StatusPending, "", txHash,
			"无有效Memo，待人工核对", time.Now().Unix(),
		)
		m.tg.NotifyUSDTManualReview(txHash, usdtAmount, "无法解析 Memo，无有效 USER_ID")
		m.notif.Notify(notify.EventPaymentFailed, notify.SeverityWarning,
			fmt.Sprintf("USDT 交易待人工审核"),
			fmt.Sprintf("交易 %s\n金额: $%.2f USDT\n原因: 无法解析 Memo，无有效 USER_ID",
				txHash[:16], usdtAmount),
			map[string]interface{}{"tx_hash": txHash, "amount": usdtAmount})
		return
	}

	// 验证用户是否存在
	var userEmail string
	if err := m.db.QueryRow("SELECT email FROM users WHERE id = ?", userID).Scan(&userEmail); err == sql.ErrNoRows {
		log.Printf("[USDT] 用户 %d 不存在，待人工处理 tx=%s", userID, txHash[:16])
		_, _ = m.db.Exec(
			`INSERT OR IGNORE INTO payment_log (user_id, payment_id, provider, amount_cents, tokens, status, memo, tx_hash, notes, created_at)
			 VALUES (?, ?, ?, ?, 0, ?, ?, ?, ?, ?)`,
			userID, txHash, ProviderUSDTTron, int(usdtAmount*100), StatusPending, "", txHash,
			fmt.Sprintf("用户ID %d 不存在，待核对", userID), time.Now().Unix(),
		)
		m.tg.NotifyUSDTManualReview(txHash, usdtAmount, fmt.Sprintf("用户 ID %d 不存在", userID))
		m.notif.Notify(notify.EventPaymentFailed, notify.SeverityWarning,
			fmt.Sprintf("USDT 交易待人工审核"),
			fmt.Sprintf("交易 %s\n金额: $%.2f USDT\n原因: 用户 ID %d 不存在",
				txHash[:16], usdtAmount, userID),
			map[string]interface{}{"tx_hash": txHash, "amount": usdtAmount})
		return
	} else if err != nil {
		log.Printf("[USDT] 查询用户失败: %v", err)
		return
	}

	// 计算 Token
	amountCents := int(usdtAmount * 100)
	tokens := int(float64(amountCents) / m.centsPerToken)
	bonus := m.calculateUSDTBonus(usdtAmount)
	totalTokens := tokens + bonus
	now := time.Now().Unix()

	// 事务写入
	dbTx, err := m.db.Begin()
	if err != nil {
		log.Printf("[USDT] 开启事务失败: %v", err)
		return
	}

	_, err = dbTx.Exec(`
		INSERT INTO payment_log (user_id, payment_id, provider, amount_cents, tokens, bonus, status, memo, tx_hash, created_at, completed_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		userID, txHash, ProviderUSDTTron, amountCents, totalTokens, bonus, StatusCompleted,
		"", txHash, now, now)
	if err != nil {
		log.Printf("[USDT] 写入 payment_log 失败: %v", err)
		_ = dbTx.Rollback()
		return
	}

	_, err = dbTx.Exec("UPDATE users SET quota = quota + ?, updated_at = ? WHERE id = ?",
		totalTokens, now, userID)
	if err != nil {
		log.Printf("[USDT] 更新用户额度失败: %v", err)
		_ = dbTx.Rollback()
		return
	}

	if err := dbTx.Commit(); err != nil {
		log.Printf("[USDT] 提交事务失败: %v", err)
		return
	}

	// 审计日志
	audit.Log(m.db, "usdt_auto_credit", "system", fmt.Sprintf("user:%d", userID),
		fmt.Sprintf("金额:$%.2f Token:%d 哈希:%s", usdtAmount, totalTokens, txHash), "")

	log.Printf("[USDT] 自动到账: user=%d amount=$%.2f tokens=%d(+%d) tx=%s",
		userID, usdtAmount, totalTokens, bonus, txHash[:16])

	// 通知（旧通道 + 新通知中心）
	go m.tg.NotifyUSDTReceived(int64(userID), usdtAmount, int64(totalTokens), txHash)
	m.notif.Notify(notify.EventPaymentConfirmed, notify.SeverityInfo,
		fmt.Sprintf("USDT 自动到账"),
		fmt.Sprintf("用户 %d 收到 $%.2f USDT → %d Token (+%d 赠送)\n交易: %s",
			userID, usdtAmount, totalTokens, bonus, txHash[:16]),
		map[string]interface{}{
			"user_id":    userID,
			"email":      userEmail,
			"tx_hash":    txHash,
			"amount_usd": usdtAmount,
			"tokens":     totalTokens,
			"bonus":      bonus,
			"amount":     usdtAmount,
		})
}

// getConfirmations 获取交易确认数
func (m *Monitor) getConfirmations(txID string) int {
	latestBlock := m.getLatestBlock()
	if latestBlock == 0 {
		return 0
	}

	url := fmt.Sprintf("https://api.trongrid.io/v1/transactions/%s", txID)
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Accept", "application/json")
	if m.tronGridKey != "" {
		req.Header.Set("TRON-PRO-API-KEY", m.tronGridKey)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		log.Printf("[USDT] 查询交易详情失败: tx=%s err=%v", txID[:16], err)
		return 0
	}
	defer resp.Body.Close()

	var result struct {
		BlockNumber int64 `json:"blockNumber"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		log.Printf("[USDT] 解析交易详情失败: tx=%s err=%v", txID[:16], err)
		return 0
	}

	if result.BlockNumber == 0 {
		return 0
	}

	return int(latestBlock - result.BlockNumber + 1)
}

// getLatestBlock 获取 TRON 最新区块高度
func (m *Monitor) getLatestBlock() int64 {
	resp, err := http.Get("https://api.trongrid.io/wallet/getnowblock")
	if err != nil {
		log.Printf("[USDT] 获取最新区块失败: %v", err)
		return 0
	}
	defer resp.Body.Close()

	var result struct {
		BlockHeader struct {
			RawData struct {
				Number int64 `json:"number"`
			} `json:"raw_data"`
		} `json:"block_header"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		log.Printf("[USDT] 解析区块数据失败: %v", err)
		return 0
	}

	return result.BlockHeader.RawData.Number
}

// extractUserFromMemo 从原始交易 hex data 中提取用户 ID
// 解析 TriggerSmartContract 调用的 data 字段，提取 Memo
func (m *Monitor) extractUserFromMemo(txID string) int {
	url := fmt.Sprintf("https://api.trongrid.io/v1/transactions/%s", txID)
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Accept", "application/json")
	if m.tronGridKey != "" {
		req.Header.Set("TRON-PRO-API-KEY", m.tronGridKey)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		log.Printf("[USDT] 查询原始交易失败: tx=%s err=%v", txID[:16], err)
		return 0
	}
	defer resp.Body.Close()

	var result struct {
		RawData struct {
			Contract []struct {
				Parameter struct {
					Value struct {
						Data string `json:"data"`
					} `json:"value"`
				} `json:"parameter"`
			} `json:"contract"`
		} `json:"raw_data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		log.Printf("[USDT] 解析原始交易失败: tx=%s err=%v", txID[:16], err)
		return 0
	}

	// 遍历合约调用寻找 USDT transfer 的 data 字段
	for _, contract := range result.RawData.Contract {
		data := contract.Parameter.Value.Data
		if data == "" || len(data) < 64 {
			continue
		}

		// TRC-20 transfer(address,uint256) 函数签名: a9059cbb
		// data 前 4 字节 = 函数选择器, 后 32 字节 = to, 32 字节 = amount
		// 剩余部分 (如果有) = memo hex
		if !strings.HasPrefix(data, "a9059cbb") {
			continue
		}

		// 前面 68 字节 (4+32+32 hex = 68 字符) 是 transfer 必需参数
		// 剩余的 hex 就是 memo
		if len(data) > 68 {
			memoHex := data[68:]
			memoBytes, err := hex.DecodeString(memoHex)
			if err != nil {
				log.Printf("[USDT] hex 解码 Memo 失败: tx=%s hex=%s err=%v", txID[:16], memoHex, err)
				continue
			}
			memo := strings.TrimSpace(string(memoBytes))
			if memo == "" {
				continue
			}

			// 解析 "USER_12345" 格式 或 纯数字
			var userID int
			if strings.HasPrefix(memo, "USER_") {
				if _, scanErr := fmt.Sscanf(memo, "USER_%d", &userID); scanErr != nil {
					log.Printf("[USDT] Memo 格式无效: %s", memo)
					continue
				}
			} else {
				if _, scanErr := fmt.Sscanf(memo, "%d", &userID); scanErr != nil {
					log.Printf("[USDT] Memo 不是有效数字: %s", memo)
					continue
				}
			}
			return userID
		}
	}

	return 0
}

// calculateUSDTBonus 根据充值金额计算赠送 Token
func (m *Monitor) calculateUSDTBonus(usdAmount float64) int {
	baseTokens := int(usdAmount * 100 / m.centsPerToken)
	switch {
	case usdAmount >= 100:
		return baseTokens * 20 / 100 // 加赠 20%
	case usdAmount >= 50:
		return baseTokens * 15 / 100 // 加赠 15%
	case usdAmount >= 25:
		return baseTokens * 10 / 100 // 加赠 10%
	case usdAmount >= 10:
		return baseTokens * 5 / 100 // 加赠 5%
	default:
		return 0
	}
}

// ========== JSON 解析结构体 ==========

type tronGridResponse struct {
	Data []tronGridTransaction `json:"data"`
	Meta struct {
		Fingerprint string `json:"fingerprint"`
		Links       struct {
			Next string `json:"next"`
		} `json:"links"`
	} `json:"meta"`
	Success bool `json:"success"`
}

type tronGridTransaction struct {
	TransactionID string `json:"transaction_id"`
	TokenInfo     struct {
		Symbol   string `json:"symbol"`
		Address  string `json:"address"`
		Decimals int    `json:"decimals"`
		Name     string `json:"name"`
	} `json:"token_info"`
	BlockTimestamp int64  `json:"block_timestamp"`
	From           string `json:"from"`
	To             string `json:"to"`
	Type           string `json:"type"`
	Value          string `json:"value"`
}

// ========== 环境变量辅助函数 ==========

func getEnvInt(key string, defaultVal int) int {
	if val := os.Getenv(key); val != "" {
		if n, err := strconv.Atoi(val); err == nil {
			return n
		}
	}
	return defaultVal
}

func getEnvFloat(key string, defaultVal float64) float64 {
	if val := os.Getenv(key); val != "" {
		if f, err := strconv.ParseFloat(val, 64); err == nil && !math.IsNaN(f) {
			return f
		}
	}
	return defaultVal
}
