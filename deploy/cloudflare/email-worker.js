// Cloudflare Email Worker — Catch-all for aiflowhub.ai

const BOT_TOKEN = "8812183039:AAHOB6OkhQVrSQy40ijeE_GHwoqz-FlELK8";
const CHAT_ID = "8798788738";
// 环境变量（在 Cloudflare Dashboard 配置）:
//   BACKEND_URL = https://aiflowhub.ai/api/email/inbound
//   INBOUND_SECRET = 共享密钥（后端 EMAIL_INBOUND_SECRET 一致）

function escapeHTML(str) {
  return String(str || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function truncate(str, max = 200) {
  if (!str) return "(empty)";
  return str.length > max ? str.slice(0, max) + "…" : str;
}

function decodeMIME(str) {
  if (!str) return "";
  return str.replace(
    /=\?([^?]+)\?([BbQq])\?([^?]*)\?=/g,
    (_, charset, encoding, data) => {
      try {
        if (encoding.toLowerCase() === "b") {
          const u8 = Uint8Array.from(atob(data), (c) => c.charCodeAt(0));
          return new TextDecoder(charset).decode(u8);
        }
        if (encoding.toLowerCase() === "q") {
          return decodeURIComponent(
            data.replace(/_/g, " ").replace(/=([0-9A-F]{2})/gi, "%$1"));
        }
      } catch {}
      return data;
    }
  );
}

function decodeTransfer(body, encoding) {
  if (!encoding) return body;
  const enc = encoding.toLowerCase().trim();
  try {
    if (enc === "base64") {
      const clean = body.replace(/\s/g, "");
      const u8 = Uint8Array.from(atob(clean), (c) => c.charCodeAt(0));
      return new TextDecoder("utf-8").decode(u8);
    }
    if (enc === "quoted-printable") {
      return body.replace(/=\r?\n/g, "").replace(
        /=([0-9A-F]{2})/gi, (_, h) => String.fromCharCode(parseInt(h, 16)));
    }
  } catch {}
  return body;
}

function stripHTML(html) {
  return html
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/div>/gi, "\n")
    .replace(/<\/p>/gi, "\n")
    .replace(/<[^>]*>/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&nbsp;/g, " ")
    .replace(/&quot;/g, '"')
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

// 去掉回复引用
function stripQuoted(text) {
  return text
    // 删除 "xxx wrote:" 行及之后的所有引用
    .replace(/\n[^\n]*wrote:\s*\n[>].*/is, "")
    // 删除 "于xxx写道：" 行及之后的引用（中文 Gmail 格式）
    .replace(/\n[^\n]*[于在]\d{4}[^\n]*[写道说]\s*[：:]\s*\n[>].*/is, "")
    // 删除单独的引用行
    .replace(/^>[^\n]*\n?/gm, "")
    // 清理多余空行
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function parseEmailBody(raw) {
  const blankLine = raw.search(/\r?\n\r?\n/);
  if (blankLine === -1) return { text: decodeTransfer(raw, ""), attachCount: 0 };

  const headers = raw.slice(0, blankLine);
  const body = raw.slice(blankLine).trim();

  const bMatch = headers.match(/boundary\s*=\s*"?([^";\s\r\n]+)/i);
  if (!bMatch) return { text: stripQuoted(body), attachCount: 0 };

  const boundary = bMatch[1];
  const result = parseMIMEParts(body, boundary);
  return result;
}

// 递归解析 MIME parts，提取文本和附件数量
function parseMIMEParts(body, boundary) {
  const parts = body.split("--" + boundary);
  let textBody = "";
  let htmlBody = "";
  let attachCount = 0;

  for (const part of parts) {
    const headerEnd = part.search(/\r?\n\r?\n/);
    if (headerEnd === -1) continue;
    const pHeaders = part.slice(0, headerEnd);
    const pBody = part.slice(headerEnd).trim();

    // 检查 Content-Disposition: attachment
    const dispMatch = pHeaders.match(/content-disposition:\s*([^;\r\n]+)/i);
    if (dispMatch && dispMatch[1].toLowerCase().includes("attachment")) {
      attachCount++;
      continue;
    }

    // 嵌套 multipart
    const subBoundary = pHeaders.match(/boundary\s*=\s*"?([^";\s\r\n]+)/i);
    if (subBoundary) {
      const sub = parseMIMEParts(pBody, subBoundary[1]);
      if (sub.text) textBody = sub.text;
      if (!textBody && sub.htmlBody) htmlBody = sub.htmlBody;
      attachCount += sub.attachCount;
      continue;
    }

    const ctMatch = pHeaders.match(/content-type:\s*text\/(plain|html)/i);
    if (!ctMatch) continue;

    const ceMatch = pHeaders.match(/content-transfer-encoding:\s*(\S+)/i);
    const enc = ceMatch ? ceMatch[1].replace(/;$/, "") : "";

    if (ctMatch[1].toLowerCase() === "plain") {
      textBody = decodeTransfer(pBody, enc);
    } else {
      htmlBody = decodeTransfer(pBody, enc);
    }
  }

  return {
    text: textBody ? stripQuoted(textBody).trim()
      : (htmlBody ? stripQuoted(stripHTML(htmlBody)) : stripQuoted(body.slice(0, 500))),
    attachCount: attachCount,
  };
}

// 转发邮件到后端 API 持久化存储
async function saveToBackend(env, emailData) {
  const backendUrl = env.BACKEND_URL;
  const inboundSecret = env.INBOUND_SECRET;
  if (!backendUrl || !inboundSecret) {
    console.log("[email-worker] BACKEND_URL 或 INBOUND_SECRET 未配置，跳过持久化");
    return;
  }
  try {
    const resp = await fetch(backendUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${inboundSecret}`,
      },
      body: JSON.stringify(emailData),
    });
    if (!resp.ok) {
      console.log(`[email-worker] 后端返回 ${resp.status}: ${await resp.text()}`);
    }
  } catch (err) {
    console.log(`[email-worker] 后端存储失败: ${err.message}`);
  }
}

async function sendTelegram(text) {
  await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      chat_id: CHAT_ID, text, parse_mode: "HTML",
      disable_web_page_preview: true,
    }),
  });
}

export default {
  async email(message, env, ctx) {
    const from = escapeHTML(
      decodeMIME(message.from || message.headers.get("from") || "unknown"));
    const to = escapeHTML(message.to || message.headers.get("to") || "unknown");
    const subject = escapeHTML(
      decodeMIME(message.headers.get("subject") || "(no subject)"));
    const date = escapeHTML(message.headers.get("date") || "");

    let raw = "";
    try {
      if (message.raw) raw = await new Response(message.raw).text();
    } catch (e) {
      raw = "read error: " + e.message;
    }

    const { text: parsedBody, attachCount } = parseEmailBody(raw);
    const body = escapeHTML(parsedBody);

    // 1. 转发到 Telegram + 存储到后端（保持现有行为）
    const lines = [];
    lines.push(`📧 <b>${truncate(subject, 100)}</b>`);
    lines.push(`<b>From:</b> ${truncate(from, 80)}`);
    lines.push(`<b>To:</b> ${truncate(to, 80)}`);
    if (date) lines.push(`<b>Date:</b> ${truncate(date, 30)}`);
    if (attachCount > 0) lines.push(`<b>附件:</b> ${attachCount} 个`);
    lines.push("");
    lines.push(truncate(body, 1500));

    await sendTelegram(lines.join("\n"));

    // 2. 转发到 Gmail 以便阅读完整内容和附件（需在 Cloudflare Email Routing 添加验证过的目标地址）
    if (env.FORWARD_EMAIL) {
      try {
        await message.forward(env.FORWARD_EMAIL);
      } catch (e) {
        console.log(`[email-worker] 转发失败: ${e.message}`);
      }
    }

    // 3. 持久化到后端（异步，不阻塞 Telegram 通知）
    ctx.waitUntil(saveToBackend(env, {
      message_id: message.headers.get("message-id") || "",
      from: decodeMIME(message.from || message.headers.get("from") || ""),
      to: decodeMIME(message.to || message.headers.get("to") || ""),
      subject: decodeMIME(message.headers.get("subject") || ""),
      body_text: parsedBody,
      attach_count: attachCount,
      raw_eml: raw,
    }));
  },
};
