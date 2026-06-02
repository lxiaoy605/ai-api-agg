// Cloudflare Email Worker — Catch-all for aiflowhub.ai
// 极简模式：不做任何解析，只转发原始 EML 到后端。
// 所有 MIME 解析、正文提取、附件处理都在 Go 后端完成。
//
// 环境变量（Cloudflare Dashboard）:
//   BACKEND_URL = https://aiflowhub.ai/api/email/raw
//   INBOUND_SECRET = 共享密钥
//   FORWARD_EMAIL = (可选) 转发到的邮箱地址

export default {
  async email(message, env, ctx) {
    // 1. 转发到 Gmail（可选，需在 Cloudflare Email Routing 添加验证过的目标地址）
    if (env.FORWARD_EMAIL) {
      try {
        await message.forward(env.FORWARD_EMAIL);
      } catch (e) {
        console.log(`[email-worker] forward failed: ${e.message}`);
      }
    }

    // 2. 读取原始 EML
    let raw;
    try {
      raw = await new Response(message.raw).text();
    } catch (e) {
      console.log(`[email-worker] read raw failed: ${e.message}`);
      return;
    }

    // 3. 飞送到后端（后端完成全部解析、存储、通知）
    const backendUrl = env.BACKEND_URL || "https://aiflowhub.ai/api/email/raw";
    const secret = env.INBOUND_SECRET || "";
    try {
      const res = await fetch(backendUrl, {
        method: "POST",
        headers: {
          "Content-Type": "text/plain",
          "X-Inbound-Secret": secret,
        },
        body: raw,
      });
      if (!res.ok) {
        console.log(`[email-worker] backend error: ${res.status} ${await res.text()}`);
      }
    } catch (e) {
      console.log(`[email-worker] fetch failed: ${e.message}`);
    }
  },
};
