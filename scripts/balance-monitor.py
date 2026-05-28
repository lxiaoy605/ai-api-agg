#!/usr/bin/env python3
"""
多厂商 AI API 余额监控脚本
支持：DeepSeek、Z.ai（智谱国际站）、MiMo（小米）
通过 Telegram Bot 发送两级告警通知

用法：
  python balance-monitor.py                  # 标准模式（日志 + Telegram 通知）
  python balance-monitor.py --json           # 仅输出 JSON 汇总
  python balance-monitor.py --no-telegram    # 跳过 Telegram 通知
  python balance-monitor.py --vendor deepseek # 仅检查指定厂商

环境变量：
  DEEPSEEK_API_KEY    DeepSeek API Key
  ZHIPU_API_KEY       Z.ai（智谱国际站）API Key
  MIMO_API_KEY        小米 MiMo API Key
  TELEGRAM_BOT_TOKEN  Telegram Bot Token
  TELEGRAM_CHAT_ID    Telegram Chat ID（接收告警消息）

---
多账号邮箱配置指南（Cloudflare Email Routing + aiflowhub.ai 域名）
---

本平台使用 aiflowhub.ai（Spaceship 注册）作为主域名。
建议配合 Cloudflare Email Routing（免费）实现多厂商账号隔离：

1. 将 aiflowhub.ai 域名的 DNS 托管到 Cloudflare
2. 在 Cloudflare 控制台 → Email → Email Routing 中：
   a. 添加目标邮箱（你的主邮箱，如 Gmail）
   b. 创建 Catch-All 规则：*@aiflowhub.ai → 主邮箱
3. 按厂商分配子邮箱注册 API 账号：
   - deepseek@aiflowhub.ai → DeepSeek 平台
   - zhipu@aiflowhub.ai   → 智谱 Z.ai 平台
   - mimo@aiflowhub.ai    → 小米 MiMo 平台
4. 各厂商邮件自动转发到主邮箱，无需分别登录管理
5. 年费用：域名 ~$10/年（Spaceship），Email Routing $0

更多详见 MASTER-PLAN.md 第 2.4 节（多邮箱申请方案）。
"""

import os
import sys
import json
import logging
import argparse
from datetime import datetime, timezone
from typing import Optional

import subprocess
import urllib.request
import urllib.error

# ---------- 路径配置 ----------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
LOG_DIR = os.path.join(PROJECT_DIR, "logs")
os.makedirs(LOG_DIR, exist_ok=True)
LOG_FILE = os.path.join(LOG_DIR, "balance-monitor.log")

# ---------- 日志配置 ----------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("balance-monitor")

# ---------- 厂商 API Key（从环境变量读取）----------
API_KEYS = {
    "deepseek": os.environ.get("DEEPSEEK_API_KEY", ""),
    "zhipu": os.environ.get("ZHIPU_API_KEY", ""),
    "mimo": os.environ.get("MIMO_API_KEY", ""),
}

# ---------- 余额阈值（美元）----------
THRESHOLD_WARNING = 5.0   # < $5 → WARNING
THRESHOLD_CRITICAL = 2.0  # < $2 → CRITICAL

# ---------- Telegram 配置 ----------
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")

# ---------- 请求配置 ----------
REQUEST_TIMEOUT = 30  # 秒
CNY_TO_USD = 7.2      # 人民币转美元粗略汇率


# ============================================================
# 工具函数
# ============================================================

def http_get(url: str, headers: dict) -> dict:
    """发送 HTTP GET 请求，返回解析后的 JSON 字典"""
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body)
    except urllib.error.HTTPError as e:
        body = ""
        try:
            if e.fp:
                body = e.read().decode("utf-8")
        except Exception:
            pass
        return {"_error": True, "http_code": e.code, "body": body[:500]}
    except urllib.error.URLError as e:
        return {"_error": True, "reason": str(e.reason)}
    except json.JSONDecodeError:
        return {"_error": True, "reason": "JSON 解析失败"}
    except Exception as e:
        return {"_error": True, "reason": str(e)}


def to_usd(raw_balance: float, currency: str) -> float:
    """将原始余额转为美元"""
    if currency.upper() == "CNY":
        return round(raw_balance / CNY_TO_USD, 2)
    return round(raw_balance, 2)


def check_level(balance_usd: float) -> str:
    """根据余额返回告警级别"""
    if balance_usd < THRESHOLD_CRITICAL:
        return "CRITICAL"
    elif balance_usd < THRESHOLD_WARNING:
        return "WARNING"
    return "OK"


def send_ops_notify(level: str, title: str, message: str, channel: str = "default") -> bool:
    """通过统一通知脚本 ops-notify.sh 发送运维通知"""
    notify_script = os.path.join(SCRIPT_DIR, "ops-notify.sh")
    if not os.path.isfile(notify_script) or not os.access(notify_script, os.X_OK):
        log.warning("ops-notify.sh 不存在或不可执行，跳过通知")
        return False

    try:
        result = subprocess.run(
            [notify_script,
             "--level", level,
             "--title", title,
             "--message", message,
             "--channel", channel,
             "--silent"],
            capture_output=True, text=True, timeout=15
        )
        if result.returncode == 0:
            log.info(f"运维通知发送成功: [{level}] {title}")
            return True
        else:
            log.warning(f"运维通知发送失败: {result.stderr.strip()}")
            return False
    except subprocess.TimeoutExpired:
        log.error("运维通知脚本执行超时")
        return False
    except Exception as e:
        log.error(f"运维通知异常: {e}")
        return False


# ============================================================
# 各厂商余额查询（独立错误处理，一个挂了不影响其他）
# ============================================================

def check_deepseek(api_key: str) -> dict:
    """
    查询 DeepSeek 余额
    API: GET https://api.deepseek.com/user/balance
    返回示例: {"is_available": true, "balance_infos": [{"currency": "CNY", "total_balance": "100.00", ...}]}
    """
    if not api_key:
        return {"vendor": "DeepSeek", "status": "error", "error": "未配置 API Key (DEEPSEEK_API_KEY)"}

    url = "https://api.deepseek.com/user/balance"
    headers = {"Authorization": f"Bearer {api_key}", "Accept": "application/json"}
    result = http_get(url, headers)

    if result.get("_error"):
        return {"vendor": "DeepSeek", "status": "error", "error": result.get("reason") or f"HTTP {result.get('http_code')}"}

    try:
        balance_infos = result.get("balance_infos", [])
        if not balance_infos:
            # 备用：检查 is_available 字段
            if not result.get("is_available", True):
                return {"vendor": "DeepSeek", "status": "error", "error": "余额不可用 (is_available=false)", "raw": result}
            return {"vendor": "DeepSeek", "status": "error", "error": "余额数据为空", "raw": result}

        info = balance_infos[0]
        currency = info.get("currency", "CNY")
        total_balance = float(info.get("total_balance", "0"))
        balance_usd = to_usd(total_balance, currency)
        level = check_level(balance_usd)

        return {
            "vendor": "DeepSeek",
            "status": "ok",
            "balance": balance_usd,
            "currency": "USD",
            "raw_balance": total_balance,
            "raw_currency": currency,
            "level": level,
        }
    except (KeyError, ValueError, TypeError) as e:
        return {"vendor": "DeepSeek", "status": "error", "error": f"解析余额失败: {e}", "raw": result}


def check_zhipu(api_key: str) -> dict:
    """
    查询智谱 Z.ai 余额
    注意：智谱 API v4 目前未开放余额查询端点（/user/balance 和 /profile 均返回 404）
    尝试所有已知 endpoint，全部失败则返回 unsupported
    """
    if not api_key:
        return {"vendor": "Z.ai(智谱)", "status": "error", "error": "未配置 API Key (ZHIPU_API_KEY)"}

    headers = {"Authorization": f"Bearer {api_key}", "Accept": "application/json"}

    # 尝试所有可能的余额查询 endpoint
    endpoints = [
        "https://api.z.ai/api/paas/v4/user/balance",
        "https://open.bigmodel.cn/api/paas/v4/user/balance",
        "https://api.z.ai/api/paas/v4/profile",
        "https://open.bigmodel.cn/api/paas/v4/profile",
        "https://api.z.ai/api/paas/v4/account",
        "https://open.bigmodel.cn/api/paas/v4/account",
    ]

    for url in endpoints:
        result = http_get(url, headers)
        if result.get("_error"):
            continue

        # 尝试解析余额
        try:
            data = result.get("data", result)
            if isinstance(data, dict):
                for field in ("balance", "total_balance", "remaining", "quota"):
                    if field in data:
                        raw_balance = float(data[field])
                        currency = str(data.get("currency", "CNY"))
                        balance_usd = to_usd(raw_balance, currency)
                        level = check_level(balance_usd)
                        return {
                            "vendor": "Z.ai(智谱)",
                            "status": "ok",
                            "balance": balance_usd,
                            "currency": "USD",
                            "raw_balance": raw_balance,
                            "raw_currency": currency,
                            "level": level,
                        }
            for field in ("balance", "total_balance", "remaining"):
                if field in result:
                    raw_balance = float(result[field])
                    currency = str(result.get("currency", "CNY"))
                    balance_usd = to_usd(raw_balance, currency)
                    level = check_level(balance_usd)
                    return {
                        "vendor": "Z.ai(智谱)",
                        "status": "ok",
                        "balance": balance_usd,
                        "currency": "USD",
                        "level": level,
                    }
        except (KeyError, ValueError, TypeError):
            continue

    # 所有 endpoint 都不可用
    return {
        "vendor": "Z.ai(智谱)",
        "status": "unsupported",
        "error": "智谱 API v4 未开放余额查询端点。请手动查看: https://z.ai → Dashboard → Billing",
    }


def check_mimo(api_key: str) -> dict:
    """
    查询小米 MiMo 余额
    注意：MiMo 未公开余额查询 API，尝试已知 endpoints
    失败时返回 "unsupported" 状态，不影响其他厂商
    """
    if not api_key:
        return {"vendor": "MiMo", "status": "error", "error": "未配置 API Key (MIMO_API_KEY)"}

    headers = {"Authorization": f"Bearer {api_key}", "Accept": "application/json"}

    # 尝试多个可能的余额 endpoint
    endpoints = [
        "https://api.xiaomimimo.com/v1/balance",
        "https://api.xiaomimimo.com/v1/user/balance",
        "https://api.xiaomimimo.com/v1/account/balance",
        "https://api.xiaomimimo.com/v1/billing/balance",
    ]

    for url in endpoints:
        result = http_get(url, headers)
        if result.get("_error"):
            continue

        # 尝试解析余额
        try:
            data = result.get("data", result)
            if isinstance(data, dict):
                for field in ("balance", "total_balance", "remaining", "quota", "credits"):
                    if field in data:
                        raw_balance = float(data[field])
                        currency = str(data.get("currency", "USD"))
                        balance_usd = to_usd(raw_balance, currency)
                        level = check_level(balance_usd)
                        return {
                            "vendor": "MiMo",
                            "status": "ok",
                            "balance": balance_usd,
                            "currency": "USD",
                            "raw_balance": raw_balance,
                            "raw_currency": currency,
                            "level": level,
                        }
            # 根级别字段
            for field in ("balance", "total_balance", "credits"):
                if field in result:
                    raw_balance = float(result[field])
                    currency = str(result.get("currency", "USD"))
                    balance_usd = to_usd(raw_balance, currency)
                    level = check_level(balance_usd)
                    return {
                        "vendor": "MiMo",
                        "status": "ok",
                        "balance": balance_usd,
                        "currency": "USD",
                        "level": level,
                    }
        except (KeyError, ValueError, TypeError):
            continue

    # 所有 endpoint 都失败
    return {
        "vendor": "MiMo",
        "status": "unsupported",
        "error": "MiMo 未公开余额查询 API，无法自动获取。请手动查看: https://platform.xiaomimimo.com",
    }


# ============================================================
# 主流程
# ============================================================

VENDOR_FUNCTIONS = {
    "deepseek": check_deepseek,
    "zhipu": check_zhipu,
    "mimo": check_mimo,
}


def run_checks(vendors: Optional[list] = None) -> list:
    """运行指定厂商（或全部）的余额检查"""
    if vendors is None:
        vendors = list(VENDOR_FUNCTIONS.keys())

    results = []
    for vendor in vendors:
        func = VENDOR_FUNCTIONS.get(vendor)
        if not func:
            log.warning(f"未知厂商: {vendor}，跳过")
            continue

        key = API_KEYS.get(vendor, "")
        log.info(f"检查 {vendor} 余额...")
        try:
            result = func(key)
        except Exception as e:
            result = {"vendor": vendor, "status": "error", "error": f"未预期的异常: {e}"}

        results.append(result)
        status = result.get("status", "?")
        detail = result.get("balance", result.get("error", "N/A"))
        log.info(f"  {vendor}: status={status}, detail={detail}")

    return results


def send_alerts(results: list) -> int:
    """根据结果发送运维通知，返回告警数量"""
    alerts = []
    for r in results:
        if r.get("status") != "ok":
            continue
        level = r.get("level", "OK")
        if level in ("WARNING", "CRITICAL"):
            alerts.append(r)

    if not alerts:
        log.info("无需告警，所有渠道余额正常")
        return 0

    # 为每个告警单独发送通知
    for r in alerts:
        level_lower = r["level"].lower()
        title = f"余额{r['level']}: {r['vendor']}"
        detail = f"当前余额: ${r['balance']:.2f}\n原始余额: {r.get('raw_balance', 'N/A')} {r.get('raw_currency', '')}\n阈值: CRITICAL<$2 WARNING<$5"
        send_ops_notify(level_lower, title, detail)

    return len(alerts)


def output_summary(results: list) -> dict:
    """输出 JSON 汇总并返回"""
    summary = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "thresholds": {"warning_usd": THRESHOLD_WARNING, "critical_usd": THRESHOLD_CRITICAL},
        "results": results,
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return summary


def main():
    parser = argparse.ArgumentParser(description="多厂商 AI API 余额监控")
    parser.add_argument("--json", action="store_true", help="静默模式，仅输出 JSON 汇总到 stdout")
    parser.add_argument("--no-telegram", action="store_true", help="跳过 Telegram 通知")
    parser.add_argument("--vendor", action="append", dest="vendors",
                        choices=list(VENDOR_FUNCTIONS.keys()),
                        help="仅检查指定厂商（可多次指定）")
    args = parser.parse_args()

    if args.json:
        logging.getLogger().setLevel(logging.ERROR)

    log.info("========== 余额监控开始 ==========")

    results = run_checks(args.vendors)

    if not args.no_telegram:
        alert_count = send_alerts(results)
        log.info(f"发送了 {alert_count} 条告警")
    else:
        log.info("已跳过 Telegram 通知 (--no-telegram)")

    summary = output_summary(results)

    # 汇总统计
    ok_count = sum(1 for r in results if r.get("level") == "OK")
    warn_count = sum(1 for r in results if r.get("level") == "WARNING")
    crit_count = sum(1 for r in results if r.get("level") == "CRITICAL")
    err_count = sum(1 for r in results if r.get("status") not in ("ok", "unsupported"))

    log.info(f"汇总: OK={ok_count} WARNING={warn_count} CRITICAL={crit_count} ERROR={err_count}")
    log.info("========== 余额监控结束 ==========")

    # 退出码：有 CRITICAL 或 ERROR 返回 1
    if crit_count > 0 or err_count > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
