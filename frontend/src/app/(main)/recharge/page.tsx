"use client";

import { useState, useCallback, useEffect, useRef } from "react";
import QRCode from "qrcode";
import { useTranslations } from "next-intl";
import {
  Copy,
  Check,
  Clock,
  AlertTriangle,
  Info,
  Zap,
  Loader2,
  ArrowLeft,
  RefreshCw,
  CreditCard,
  Wallet,
} from "lucide-react";
import {
  amountOptions,
  networkConfigs,
  fallbackUSDTAddresses,
  fetchCurrencies,
  createPayment,
  fetchPaymentStatus,
  getMinAmount,
  estimateTokens,
} from "@/data/recharge";
import type {
  AmountOption,
  NetworkConfig,
  PaymentInfo,
  CurrencyItem,
} from "@/data/recharge";

// ========== 状态枚举 ==========

type PageState =
  | "select"
  | "creating"
  | "pending"
  | "completed"
  | "failed"
  | "fallback";

// ========== 页面组件 ==========

export default function RechargePage() {
  const t = useTranslations("recharge");
  const tc = useTranslations("common");

  // Tab state
  const [activeTab, setActiveTab] = useState<"usdt" | "card">("usdt");

  // 选择状态
  const [selectedAmount, setSelectedAmount] = useState<number>(20);
  const [customAmount, setCustomAmount] = useState("");
  const [networkId, setNetworkId] = useState("trc20");

  // 页面状态
  const [pageState, setPageState] = useState<PageState>("select");
  const [errorMsg, setErrorMsg] = useState("");
  const [amountError, setAmountError] = useState<string | null>(null);

  // 支付信息
  const [paymentInfo, setPaymentInfo] = useState<PaymentInfo | null>(null);
  const [pollCount, setPollCount] = useState(0);

  // QR 码
  const [qrDataUrl, setQrDataUrl] = useState("");

  // 复制
  const [copied, setCopied] = useState(false);

  // 币种
  const [currencies, setCurrencies] = useState<CurrencyItem[]>([]);
  const [currenciesLoaded, setCurrenciesLoaded] = useState(false);

  // 轮询 timer
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);
  // 倒计时
  const [countdown, setCountdown] = useState(3600);

  // 计算显示金额
  const displayAmount =
    selectedAmount === -1 ? parseFloat(customAmount) || 0 : selectedAmount;
  const amountCents = Math.round(displayAmount * 100);
  const tokenEstimate = estimateTokens(displayAmount);

  // 当前网络配置
  const currentNetwork: NetworkConfig = networkConfigs.find(
    (n) => n.id === networkId
  )!;

  // 预加载币种
  useEffect(() => {
    if (currenciesLoaded) return;
    fetchCurrencies()
      .then((list) => {
        setCurrencies(list);
        setCurrenciesLoaded(true);
      })
      .catch(() => setCurrenciesLoaded(true));
  }, [currenciesLoaded]);

  // 生成 QR 码
  useEffect(() => {
    if (!paymentInfo?.pay_address) return;
    const qrContent = paymentInfo.pay_address;
    QRCode.toDataURL(qrContent, {
      width: 200,
      margin: 2,
      color: { dark: "#111111", light: "#ffffff" },
    })
      .then(setQrDataUrl)
      .catch(console.error);
  }, [paymentInfo?.pay_address]);

  // 倒计时
  useEffect(() => {
    if (pageState !== "pending") return;
    const timer = setInterval(() => {
      setCountdown((prev) => {
        if (prev <= 1) {
          clearInterval(timer);
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
    return () => clearInterval(timer);
  }, [pageState]);

  // 格式化倒计时
  const formatCountdown = (seconds: number) => {
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`;
  };

  // ========== 操作 ==========

  function cleanErrorMessage(msg: string): string {
    try {
      const match = msg.match(/"message":"([^"]+)"/);
      if (match) return match[1];
    } catch {}
    return msg;
  }

  const handlePay = useCallback(async () => {
    if (displayAmount < 5) {
      setAmountError(t("minAmountError"));
      return;
    }

    setAmountError(null);
    setErrorMsg("");
    setPageState("creating");

    try {
      // 先获取最低金额校验
      const minAmount = await getMinAmount("usdt", currentNetwork.currencyCode);
      if (displayAmount < minAmount) {
        setAmountError(t("minAmountError"));
        setPageState("select");
        return;
      }

      const info = await createPayment(amountCents, currentNetwork.currencyCode);
      setPaymentInfo(info);
      setCountdown(3600);
      setPageState("pending");
      startPolling(info.payment_id);
    } catch (err: any) {
      console.error("Payment creation failed:", err);
      const cleaned = cleanErrorMessage(err.message || t("subtitleFallback"));
      setErrorMsg(cleaned);
      setPageState("fallback");
    }
  }, [displayAmount, amountCents, currentNetwork.currencyCode, t]);

  const startPolling = useCallback((paymentId: number) => {
    setPollCount(0);
    if (pollRef.current) clearInterval(pollRef.current);

    pollRef.current = setInterval(async () => {
      setPollCount((prev) => prev + 1);
      try {
        const status = await fetchPaymentStatus(paymentId);
        if (status.status === "finished" || status.status === "confirmed") {
          if (pollRef.current) clearInterval(pollRef.current);
          setPageState("completed");
        } else if (
          status.status === "failed" ||
          status.status === "expired" ||
          status.status === "refunded"
        ) {
          if (pollRef.current) clearInterval(pollRef.current);
          setPageState("failed");
        }
      } catch {
        // 轮询失败静默跳过
      }
    }, 5000);

    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, []);

  // 清理轮询
  useEffect(() => {
    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, []);

  const handleCopy = useCallback(async (text: string) => {
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      const ta = document.createElement("textarea");
      ta.value = text;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      document.body.removeChild(ta);
    }
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }, []);

  const handleReset = useCallback(() => {
    if (pollRef.current) clearInterval(pollRef.current);
    setPageState("select");
    setPaymentInfo(null);
    setErrorMsg("");
    setAmountError(null);
    setQrDataUrl("");
    setPollCount(0);
  }, []);

  // 页面标题文本
  const pageSubtitle: Record<PageState, string> = {
    select: t("subtitleSelect"),
    creating: t("subtitleCreating"),
    pending: t("subtitlePending"),
    completed: t("subtitleCompleted"),
    failed: t("subtitleFailed"),
    fallback: t("subtitleFallback"),
  };

  // ========== 渲染 ==========

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[var(--body-text)]">{t("title")}</h1>
        <p className="text-[var(--muted-text)] text-sm mt-1">{pageSubtitle[pageState]}</p>
      </div>

      {errorMsg && pageState === "failed" && (
        <div className="flex items-center gap-2 p-4 rounded-lg bg-red-500/10 border border-red-500/20">
          <AlertTriangle className="h-4 w-4 text-red-400 shrink-0" />
          <p className="text-sm text-red-400">{errorMsg}</p>
        </div>
      )}

      {/* ===== Tab Switcher ===== */}
      {pageState === "select" && (
        <div className="flex items-center gap-1 p-1 bg-[var(--surface-raised)] rounded-xl w-fit border border-[var(--border-color)]">
          <button
            onClick={() => setActiveTab("usdt")}
            className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all ${
              activeTab === "usdt"
                ? "bg-brand-600 text-white shadow-sm"
                : "text-[var(--muted-text)] hover:text-[var(--body-text)]"
            }`}
          >
            <Wallet className="h-4 w-4" />
            {t("usdtTab")}
          </button>
          <button
            onClick={() => setActiveTab("card")}
            className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all ${
              activeTab === "card"
                ? "bg-brand-600 text-white shadow-sm"
                : "text-[var(--muted-text)] hover:text-[var(--body-text)]"
            }`}
          >
            <CreditCard className="h-4 w-4" />
            {t("cardTab")}
          </button>
        </div>
      )}

      {/* ===== 状态: 选择金额 (USDT) ===== */}
      {(pageState === "select" || pageState === "creating") && activeTab === "usdt" && (
        <>
          {amountError && (
            <div className="flex items-center gap-2 p-3 rounded-lg bg-red-500/10 border border-red-500/20">
              <AlertTriangle className="h-4 w-4 text-red-400 shrink-0" />
              <p className="text-sm text-red-400">{amountError}</p>
            </div>
          )}
          {errorMsg && (
            <div className="flex items-center gap-2 p-3 rounded-lg bg-yellow-500/5 border border-yellow-500/10">
              <AlertTriangle className="h-4 w-4 text-yellow-400 shrink-0" />
              <p className="text-sm text-yellow-400">{errorMsg}</p>
            </div>
          )}

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
              <h3 className="text-sm font-semibold text-[var(--body-text)] mb-4">
                {t("selectAmount")}
              </h3>
              <div className="grid grid-cols-3 gap-3">
                {amountOptions.map((opt: AmountOption) => {
                  const isSelected = selectedAmount === opt.value;
                  return (
                    <button
                      key={opt.value}
                      onClick={() => setSelectedAmount(opt.value)}
                      disabled={pageState === "creating"}
                      className={`relative p-3 rounded-xl border text-center transition-all ${
                        isSelected
                          ? "border-brand-500/50 bg-brand-500/10 text-brand-300"
                          : "border-[var(--border-color)] bg-[var(--surface-raised)]/50 text-[var(--body-text)] hover:border-[var(--border-color)] hover:bg-[var(--surface-raised)]"
                      }`}
                    >
                      {isSelected && (
                        <div className="absolute top-1.5 right-1.5 w-2 h-2 rounded-full bg-brand-500" />
                      )}
                      <span className="text-lg font-bold">{opt.label}</span>
                      {opt.tokens && (
                        <p className="text-xs text-[var(--muted-text)] mt-1">
                          ≈ {opt.tokens} tokens
                        </p>
                      )}
                    </button>
                  );
                })}
              </div>

              {selectedAmount === -1 && (
                <div className="mt-4">
                  <label className="text-xs text-[var(--muted-text)] mb-1.5 block">
                    {t("customAmountLabel")}
                  </label>
                  <div className="relative">
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--muted-text)] text-sm">
                      $
                    </span>
                    <input
                      type="number"
                      value={customAmount}
                      onChange={(e) => setCustomAmount(e.target.value)}
                      placeholder={t("customAmountPlaceholder")}
                      min="5"
                      className="w-full bg-[var(--surface-raised)] border border-[var(--border-color)] rounded-lg py-2.5 pl-8 pr-4 text-[var(--body-text)] text-sm focus:outline-none focus:border-brand-500/50 focus:ring-1 focus:ring-brand-500/20 transition-colors"
                    />
                  </div>
                </div>
              )}

              {displayAmount >= 5 && (
                <div className="mt-4 space-y-2">
                  <div className="flex items-center gap-2 px-3 py-2.5 rounded-lg bg-[var(--surface-raised)]/50 border border-[var(--border-color)]/50">
                    <Info className="h-4 w-4 text-[var(--muted-text)] shrink-0" />
                    <p className="text-sm text-[var(--muted-text)]">
                      {t("tokenEstimate", {
                        usdt: displayAmount.toFixed(2),
                        tokens: tokenEstimate.total.toLocaleString(),
                      })}
                      {tokenEstimate.bonus > 0 && (
                        <span className="text-yellow-400 text-xs ml-1">
                          {t("tokenBonus", { bonus: tokenEstimate.bonus.toLocaleString() })}
                        </span>
                      )}
                    </p>
                  </div>
                </div>
              )}
            </div>

            <div className="space-y-6">
              <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
                <h3 className="text-sm font-semibold text-[var(--body-text)] mb-4">
                  {t("selectNetwork")}
                </h3>

                <div className="space-y-2">
                  {networkConfigs.map((n) => (
                    <button
                      key={n.id}
                      onClick={() => setNetworkId(n.id)}
                      className={`w-full p-3 rounded-lg border text-left transition-all ${
                        networkId === n.id
                          ? "border-brand-500/50 bg-brand-500/10"
                          : "border-[var(--border-color)] bg-[var(--surface-raised)]/50 hover:border-[var(--border-color)]"
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <span
                          className={`text-sm font-semibold ${
                            networkId === n.id ? "text-brand-300" : "text-[var(--body-text)]"
                          }`}
                        >
                          {n.label}
                        </span>
                        {n.id === "trc20" && (
                          <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-brand-500/20 text-brand-300 font-medium">
                            {tc("recommended")}
                          </span>
                        )}
                      </div>
                      <p className="text-xs text-[var(--muted-text)] mt-1">
                        {t(n.id)} · {t("feeLabel")} {n.fee} · {t("confirmTimeLabel", { time: n.confirmTime })}
                      </p>
                    </button>
                  ))}
                </div>

                <div className="mt-4 p-3 rounded-lg bg-brand-500/5 border border-brand-500/10">
                  <div className="flex items-start gap-2">
                    <Zap className="h-4 w-4 text-brand-600 mt-0.5 shrink-0" />
                    <div>
                      <p className="text-sm text-brand-300 font-medium">
                        {t("trc20Recommend")}
                      </p>
                      <p className="text-xs text-[var(--muted-text)] mt-0.5">
                        {t("trc20Detail")}
                      </p>
                    </div>
                  </div>
                </div>
              </div>

              <button
                onClick={handlePay}
                disabled={pageState === "creating" || displayAmount < 5}
                className="w-full py-3.5 rounded-xl bg-brand-600 hover:bg-brand-700 disabled:bg-neutral-600 disabled:text-neutral-400 text-white font-semibold text-base transition-all flex items-center justify-center gap-2"
              >
                {pageState === "creating" ? (
                  <>
                    <Loader2 className="h-5 w-5 animate-spin" />
                    {t("creating")}
                  </>
                ) : (
                  <>{t("payNow", { amount: displayAmount >= 5 ? displayAmount.toFixed(2) : "—" })}</>
                )}
              </button>
            </div>
          </div>
        </>
      )}

      {/* ===== 状态: 等待付款 ===== */}
      {pageState === "pending" && paymentInfo && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-semibold text-[var(--body-text)]">
                {t("scanToPay", { currency: paymentInfo.pay_currency.toUpperCase() })}
              </h3>
              <span className="text-xs px-2 py-0.5 rounded-full bg-yellow-500/10 text-yellow-400 border border-yellow-500/20">
                {t("pendingStatus")}
              </span>
            </div>

            <div className="flex justify-center mb-4 p-3 bg-white rounded-xl">
              {qrDataUrl ? (
                <img
                  src={qrDataUrl}
                  alt="QR Code"
                  className="w-48 h-48"
                />
              ) : (
                <div className="w-48 h-48 bg-[var(--surface-raised)] animate-pulse rounded" />
              )}
            </div>

            <p className="text-xs text-[var(--muted-text)] text-center mb-4">
              {t("scanInstructions")}
            </p>

            <div className="flex items-center gap-2">
              <code className="flex-1 text-xs text-[var(--body-text)] bg-[var(--surface-raised)] rounded-lg px-3 py-2.5 break-all font-mono border border-[var(--border-color)]">
                {paymentInfo.pay_address}
              </code>
              <button
                onClick={() => handleCopy(paymentInfo.pay_address)}
                className={`shrink-0 p-2.5 rounded-lg border transition-all ${
                  copied
                    ? "border-brand-500/50 bg-brand-500/10 text-brand-300"
                    : "border-[var(--border-color)] bg-[var(--surface-raised)] text-[var(--muted-text)] hover:text-[var(--body-text)] hover:border-[var(--border-color)]"
                }`}
              >
                {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
              </button>
            </div>

            {copied && (
              <p className="mt-2 text-xs text-brand-300 flex items-center gap-1">
                <Check className="h-3 w-3" /> {t("addressCopied")}
              </p>
            )}
          </div>

          <div className="space-y-6">
            <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
              <h3 className="text-sm font-semibold text-[var(--body-text)] mb-4">{t("orderDetails")}</h3>

              <div className="space-y-3">
                <DetailRow label={t("orderId")} value={paymentInfo.order_id} />
                <DetailRow
                  label={t("payAmount")}
                  value={`${paymentInfo.pay_amount} ${paymentInfo.pay_currency.toUpperCase()}`}
                />
                <DetailRow label={t("fiatAmount")} value={`$${paymentInfo.price_amount}`} />
                <DetailRow
                  label={t("network")}
                  value={paymentInfo.network?.toUpperCase() || currentNetwork.label}
                />
                <DetailRow
                  label={t("tokensReceived")}
                  value={`${paymentInfo.tokens.toLocaleString()}${paymentInfo.bonus > 0 ? ` (${t("tokenBonus", { bonus: paymentInfo.bonus.toLocaleString() })})` : ""}`}
                />
                <DetailRow
                  label={t("remainingTime")}
                  value={
                    <span className={countdown < 300 ? "text-red-400" : "text-yellow-400"}>
                      <Clock className="h-3 w-3 inline mr-1" />
                      {formatCountdown(countdown)}
                    </span>
                  }
                />
              </div>
            </div>

            <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
              <h3 className="text-sm font-semibold text-[var(--body-text)] mb-3">{t("paymentSteps")}</h3>
              <ol className="space-y-2">
                <StepItem num="1" text={t("step1")} />
                <StepItem num="2" text={t("step2", { network: paymentInfo.network?.toUpperCase() || currentNetwork.label })} />
                <StepItem num="3" text={t("step3", { amount: paymentInfo.pay_amount, currency: paymentInfo.pay_currency.toUpperCase() })} />
                <StepItem num="4" text={t("step4")} />
              </ol>

              <div className="mt-4 flex items-center gap-2 px-3 py-2 rounded-lg bg-[var(--surface-raised)]/50">
                <Loader2 className="h-3 w-3 text-brand-300 animate-spin" />
                <p className="text-xs text-[var(--muted-text)]">
                  {t("pollingHint", { count: pollCount })}
                </p>
              </div>
            </div>

            <button
              onClick={handleReset}
              className="w-full py-2.5 rounded-lg border border-[var(--border-color)] text-[var(--muted-text)] hover:text-[var(--body-text)] hover:border-[var(--border-color)] text-sm transition-colors flex items-center justify-center gap-2"
            >
              <ArrowLeft className="h-4 w-4" />
              {t("backToSelect")}
            </button>
          </div>
        </div>
      )}

      {/* ===== 状态: 支付完成 ===== */}
      {pageState === "completed" && paymentInfo && (
        <div className="max-w-md mx-auto">
          <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-8 text-center">
            <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-brand-500/10 border border-brand-500/20 flex items-center justify-center">
              <Check className="h-8 w-8 text-brand-300" />
            </div>
            <h3 className="text-xl font-bold text-[var(--body-text)] mb-2">{t("paySuccess")}</h3>
            <p className="text-[var(--muted-text)] text-sm mb-6">
              {t("paySuccessDesc", { tokens: paymentInfo.tokens.toLocaleString() })}
            </p>

            <div className="space-y-2 mb-6 text-left bg-[var(--surface-raised)]/50 rounded-lg p-4">
              <DetailRow label={t("orderId")} value={paymentInfo.order_id} />
              <DetailRow label={t("amount")} value={`$${paymentInfo.price_amount}`} />
              <DetailRow
                label={t("credited")}
                value={`${paymentInfo.tokens.toLocaleString()} tokens${
                  paymentInfo.bonus > 0
                    ? ` (${t("tokenBonus", { bonus: paymentInfo.bonus.toLocaleString() })})`
                    : ""
                }`}
              />
            </div>

            <button
              onClick={handleReset}
              className="w-full py-3 rounded-xl bg-brand-600 hover:bg-brand-700 text-white font-semibold transition-colors"
            >
              {t("continueRecharge")}
            </button>
          </div>
        </div>
      )}

      {/* ===== 状态: 支付失败 ===== */}
      {pageState === "failed" && (
        <div className="max-w-md mx-auto">
          <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-8 text-center">
            <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-red-500/10 border border-red-500/20 flex items-center justify-center">
              <AlertTriangle className="h-8 w-8 text-red-400" />
            </div>
            <h3 className="text-xl font-bold text-[var(--body-text)] mb-2">{t("payFailed")}</h3>
            <p className="text-[var(--muted-text)] text-sm mb-6">{t("payFailedMsg")}</p>

            <button
              onClick={handleReset}
              className="w-full py-3 rounded-xl bg-[var(--surface-raised)] hover:bg-[var(--border-color)] text-[var(--body-text)] font-semibold transition-colors flex items-center justify-center gap-2"
            >
              <RefreshCw className="h-4 w-4" />
              {t("retryRecharge")}
            </button>
          </div>
        </div>
      )}

      {/* ===== 状态: 降级（API 不可用） ===== */}
      {pageState === "fallback" && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
            <div className="flex items-center gap-2 mb-4">
              <AlertTriangle className="h-4 w-4 text-yellow-400" />
              <h3 className="text-sm font-semibold text-yellow-400">
                {t("fallbackTitle")}
              </h3>
            </div>

            {errorMsg && (
              <div className="mb-4 p-3 rounded-lg bg-red-500/10 border border-red-500/20">
                <p className="text-sm text-red-400">{errorMsg}</p>
              </div>
            )}

            <div className="flex justify-center mb-4 p-3 bg-white rounded-xl">
              {qrDataUrl ? (
                <img src={qrDataUrl} alt="QR" className="w-44 h-44" />
              ) : (
                <div className="w-44 h-44 bg-[var(--surface-raised)] animate-pulse rounded" />
              )}
            </div>

            <div className="flex items-center gap-2">
              <code className="flex-1 text-xs text-[var(--body-text)] bg-[var(--surface-raised)] rounded-lg px-3 py-2.5 break-all font-mono border border-[var(--border-color)]">
                {fallbackUSDTAddresses[networkId] || fallbackUSDTAddresses.trc20}
              </code>
              <button
                onClick={() =>
                  handleCopy(fallbackUSDTAddresses[networkId] || fallbackUSDTAddresses.trc20)
                }
                className={`shrink-0 p-2.5 rounded-lg border transition-all ${
                  copied
                    ? "border-brand-500/50 bg-brand-500/10 text-brand-300"
                    : "border-[var(--border-color)] bg-[var(--surface-raised)] text-[var(--muted-text)] hover:text-[var(--body-text)] hover:border-[var(--border-color)]"
                }`}
              >
                {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
              </button>
            </div>
          </div>

          <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
            <h3 className="text-sm font-semibold text-[var(--body-text)] mb-4">{t("paymentSteps")}</h3>
            <ol className="space-y-3">
              <StepItem num="1" text={t("fallbackStep1", { network: currentNetwork.label })} />
              <StepItem num="2" text={t("fallbackStep2")} />
              <StepItem num="3" text={t("fallbackStep3", { time: currentNetwork.confirmTime })} />
            </ol>

            <button
              onClick={handleReset}
              className="mt-6 w-full py-2.5 rounded-lg border border-[var(--border-color)] text-[var(--muted-text)] hover:text-[var(--body-text)] hover:border-[var(--border-color)] text-sm transition-colors flex items-center justify-center gap-2"
            >
              <ArrowLeft className="h-4 w-4" />
              {t("retry")}
            </button>
          </div>
        </div>
      )}

      {/* ===== Credit Card Placeholder ===== */}
      {pageState === "select" && activeTab === "card" && (
        <div className="flex items-center justify-center py-16">
          <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-12 text-center max-w-md">
            <div className="w-16 h-16 mx-auto mb-6 rounded-full bg-[var(--surface-raised)] flex items-center justify-center">
              <CreditCard className="h-8 w-8 text-[var(--muted-text)]" />
            </div>
            <h3 className="text-lg font-semibold text-[var(--body-text)] mb-2">{t("cardComingSoon")}</h3>
            <p className="text-sm text-[var(--muted-text)] leading-relaxed">
              {t("cardComingSoonDesc")}
            </p>
          </div>
        </div>
      )}

      {/* ===== 支付说明 ===== */}
      {(pageState === "select" || pageState === "creating") && activeTab === "usdt" && (
        <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6">
          <h3 className="text-sm font-semibold text-[var(--body-text)] mb-4">{t("infoTitle")}</h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <InfoCard title={t("infoAutoCard.title")} desc={t("infoAutoCard.desc")} />
            <InfoCard title={t("infoMultiCard.title")} desc={t("infoMultiCard.desc")} />
            <InfoCard title={t("infoSecureCard.title")} desc={t("infoSecureCard.desc")} />
          </div>
        </div>
      )}
    </div>
  );
}

// ========== 子组件 ==========

function DetailRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="text-[var(--muted-text)]">{label}</span>
      <span className="text-[var(--body-text)] font-mono text-xs">{value}</span>
    </div>
  );
}

function StepItem({ num, text }: { num: string; text: string }) {
  return (
    <li className="flex items-start gap-3">
      <span className="shrink-0 w-5 h-5 rounded-full bg-[var(--surface-raised)] border border-[var(--border-color)] flex items-center justify-center text-[10px] text-[var(--muted-text)] font-medium">
        {num}
      </span>
      <span className="text-sm text-[var(--muted-text)]">{text}</span>
    </li>
  );
}

function InfoCard({ title, desc }: { title: string; desc: string }) {
  return (
    <div className="p-4 rounded-lg bg-[var(--surface-raised)]/30 border border-[var(--border-color)]/50">
      <h4 className="text-sm font-medium text-[var(--body-text)] mb-1">{title}</h4>
      <p className="text-xs text-[var(--muted-text)] leading-relaxed">{desc}</p>
    </div>
  );
}
