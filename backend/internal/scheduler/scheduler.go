// Package scheduler 内置任务调度器
// 服务启动时注册所有定时任务，使用 time.Ticker goroutine，零外部依赖。
// 替代之前通过 OpenClaw cron 调用 localhost 的方案。
package scheduler

import (
	"log"
	"time"

	"github.com/ai-api-agg/backend/internal/cron"
)

// Start 启动所有定时任务（阻塞 goroutine）
func Start(h *cron.Handler) {
	log.Println("[scheduler] Starting built-in task scheduler...")

	// 用户余额预警：每分钟
	go func() {
		ticker := time.NewTicker(1 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			h.RunUserBalanceWarning()
		}
	}()

	// Provider 余额预警：每 30 分钟
	go func() {
		ticker := time.NewTicker(30 * time.Minute)
		defer ticker.Stop()
		// 首次延迟 10 秒，等服务完全启动
		time.Sleep(10 * time.Second)
		for range ticker.C {
			h.RunProviderCheck()
		}
	}()

	// 管理端余额预警：每 6 小时
	go func() {
		ticker := time.NewTicker(6 * time.Hour)
		defer ticker.Stop()
		time.Sleep(30 * time.Second)
		for range ticker.C {
			h.RunBalanceCheck()
		}
	}()

	log.Println("[scheduler] All tasks registered: user-warning(1m) | provider-check(30m) | balance-check(6h)")
}
