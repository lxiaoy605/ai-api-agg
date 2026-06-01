/** NOWPayments 充值 — 数据类型与 API 调用 */

// ========== 币种 ==========

export interface CurrencyItem {
  code: string;
  name: string;
  network: string;
  logo_url: string;
  precision: number;
}

// ========== 支付 ==========

export interface PaymentInfo {
  payment_id: number;
  order_id: string;
  status: string;
  pay_address: string;
  pay_amount: number;
  pay_currency: string;
  network: string;
  price_amount: number;
  tokens: number;
  bonus: number;
  expires_at: number;
}

export interface PaymentStatus {
  payment_id: number;
  order_id: string;
  status: string;
  pay_address: string;
  pay_amount: number;
  pay_currency: string;
  network: string;
  price_amount: number;
  price_currency: string;
}

// ========== 预设金额 ==========

export interface AmountOption {
  value: number;
  label: string;
  tokens: string;
}

// 最低金额取决于 NOWPayments 实时汇率，前端选项仅做预设参考
// 实际支付时需调用 getMinAmount() 校验
// $5 不再作为选项出现，因为 NOWPayments 对大多数币种最低限额 > $5
export const amountOptions: AmountOption[] = [
  { value: 20, label: "$20", tokens: "2,200" },
  { value: 50, label: "$50", tokens: "5,750" },
  { value: 100, label: "$100", tokens: "12,000" },
  { value: -1, label: "其他", tokens: "" },
];

// ========== 网络配置 ==========

export interface NetworkConfig {
  id: string;
  label: string;
  fullName: string;
  fee: string;
  confirmTime: string;
  currencyCode: string;
}

export const networkConfigs: NetworkConfig[] = [
  {
    id: "trc20",
    label: "TRC-20",
    fullName: "USDT-TRC20 (TRON 网络)",
    fee: "约 $1",
    confirmTime: "1-3 分钟",
    currencyCode: "usdttrc20",
  },
  {
    id: "erc20",
    label: "ERC-20",
    fullName: "USDT-ERC20 (以太坊网络)",
    fee: "$5-50",
    confirmTime: "3-15 分钟",
    currencyCode: "usdterc20",
  },
  {
    id: "bep20",
    label: "BEP-20",
    fullName: "USDT-BEP20 (BSC 网络)",
    fee: "约 $0.1",
    confirmTime: "1-2 分钟",
    currencyCode: "usdtbep20",
  },
];

// ========== 静态 USDT 地址（API 不可用时降级） ==========

export const fallbackUSDTAddresses: Record<string, string> = {
  trc20: "TFdzo1emymQeSB9s5su3vZg4zNBYpFR7fS",
  erc20: "0xA6e474c3B8755a1FC01921dcC3D758Fa1f5E6120",
};

// ========== API 调用 ==========

function getApiBase(): string {
  if (typeof window === "undefined") return "";
  return window.location.hostname === "localhost"
    ? "http://localhost:8082"
    : window.location.origin;
}

function authHeaders(): Record<string, string> {
  if (typeof window === "undefined") return {};
  const token = localStorage.getItem("ai_api_agg_token") || localStorage.getItem("token");
  return token ? { Authorization: `Bearer ${token}` } : {};
}

/** 获取可用币种 */
export async function fetchCurrencies(): Promise<CurrencyItem[]> {
  const res = await fetch(`${getApiBase()}/api/payment/currencies`);
  const json = await res.json();
  if (json.code !== 0) throw new Error(json.message || "获取币种失败");
  return json.data as CurrencyItem[];
}

/** 创建支付 */
export async function createPayment(
  amountCents: number,
  payCurrency: string
): Promise<PaymentInfo> {
  const res = await fetch(`${getApiBase()}/api/payment/create`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...authHeaders(),
    },
    body: JSON.stringify({ amount_cents: amountCents, pay_currency: payCurrency }),
  });
  const json = await res.json();
  if (json.code !== 0) throw new Error(json.message || "创建支付失败");
  return json.data as PaymentInfo;
}

/** 获取最低支付金额 */
export async function getMinAmount(currencyFrom: string, currencyTo: string): Promise<number> {
  const res = await fetch(`${getApiBase()}/api/payment/min-amount?currency_from=${currencyFrom}&currency_to=${currencyTo}`, {
    headers: authHeaders(),
  });
  if (!res.ok) return 10; // fallback
  const json = await res.json();
  return json.data?.min_amount ?? 10;
}

/** 获取估算金额 */
export async function getEstimatedAmount(amount: number, currencyFrom: string, currencyTo: string): Promise<number> {
  const res = await fetch(`${getApiBase()}/api/payment/estimate?amount=${amount}&currency_from=${currencyFrom}&currency_to=${currencyTo}`, {
    headers: authHeaders(),
  });
  if (!res.ok) return amount;
  const json = await res.json();
  return json.data?.estimated_amount ?? amount;
}

/** 查询支付状态 */
export async function fetchPaymentStatus(paymentId: number): Promise<PaymentStatus> {
  const res = await fetch(`${getApiBase()}/api/payment/status/${paymentId}`, {
    headers: authHeaders(),
  });
  const json = await res.json();
  if (json.code !== 0) throw new Error(json.message || "查询状态失败");
  return json.data as PaymentStatus;
}

/** 计算预估 token（含 bonus） */
export function estimateTokens(usdAmount: number): { base: number; bonus: number; total: number } {
  const base = usdAmount * 100;
  let bonusRate = 0;
  if (usdAmount >= 100) bonusRate = 0.2;
  else if (usdAmount >= 50) bonusRate = 0.15;
  else if (usdAmount >= 20) bonusRate = 0.1;
  else if (usdAmount >= 10) bonusRate = 0.05;
  const bonus = Math.floor(base * bonusRate);
  return { base, bonus, total: base + bonus };
}
