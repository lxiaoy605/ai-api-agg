/** 模型目录 mock 数据 */

export interface ModelInfo {
  id: string;
  name: string;
  provider: string;
  providerLogo: string;
  description: string;
  inputPrice: string; // 每百万 token
  outputPrice: string;
  contextWindow: string;
  maxTokens: string;
  status: "available" | "coming-soon" | "maintenance";
  category: "chat" | "code" | "reasoning" | "multimodal";
  features: string[];
  codeExample: {
    curl: string;
    python: string;
    nodejs: string;
  };
}

export const models: ModelInfo[] = [
  {
    id: "deepseek-v4-flash",
    name: "DeepSeek V4 Flash",
    provider: "DeepSeek",
    providerLogo: "DS",
    description: "轻量快速模型，适合高并发场景，响应速度极快",
    inputPrice: "$0.14",
    outputPrice: "$0.28",
    contextWindow: "128K",
    maxTokens: "8K",
    status: "available",
    category: "chat",
    features: ["函数调用", "JSON 模式", "流式输出", "高并发"],
    codeExample: {
      curl: `curl https://api.example.com/v1/chat/completions \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer $API_KEY" \\
  -d '{
    "model": "deepseek-v4-flash",
    "messages": [{"role": "user", "content": "你好"}]
  }'`,
      python: `import openai

client = openai.OpenAI(
    base_url="https://api.example.com/v1",
    api_key="your-api-key"
)

response = client.chat.completions.create(
    model="deepseek-v4-flash",
    messages=[{"role": "user", "content": "你好"}]
)
print(response.choices[0].message.content)`,
      nodejs: `import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "https://api.example.com/v1",
  apiKey: "your-api-key",
});

const response = await client.chat.completions.create({
  model: "deepseek-v4-flash",
  messages: [{ role: "user", content: "你好" }],
});
console.log(response.choices[0].message.content);`,
    },
  },
  {
    id: "deepseek-v4-pro",
    name: "DeepSeek V4 Pro",
    provider: "DeepSeek",
    providerLogo: "DS",
    description: "旗舰推理模型，深度思考模式，适合复杂逻辑和代码生成",
    inputPrice: "$0.55",
    outputPrice: "$2.19",
    contextWindow: "128K",
    maxTokens: "32K",
    status: "available",
    category: "reasoning",
    features: ["深度思考", "代码生成", "逻辑推理", "长文本理解", "流式输出"],
    codeExample: {
      curl: `curl https://api.example.com/v1/chat/completions \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer $API_KEY" \\
  -d '{
    "model": "deepseek-v4-pro",
    "messages": [{"role": "user", "content": "解释量子计算的基本原理"}]
  }'`,
      python: `import openai

client = openai.OpenAI(
    base_url="https://api.example.com/v1",
    api_key="your-api-key"
)

response = client.chat.completions.create(
    model="deepseek-v4-pro",
    messages=[{"role": "user", "content": "解释量子计算的基本原理"}]
)
print(response.choices[0].message.content)`,
      nodejs: `import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "https://api.example.com/v1",
  apiKey: "your-api-key",
});

const response = await client.chat.completions.create({
  model: "deepseek-v4-pro",
  messages: [{ role: "user", content: "解释量子计算的基本原理" }],
});
console.log(response.choices[0].message.content);`,
    },
  },
  {
    id: "glm-5.1",
    name: "GLM-5.1",
    provider: "智谱 Z.ai",
    providerLogo: "ZP",
    description: "智谱最新旗舰模型，综合能力强，中英文表现优秀",
    inputPrice: "$1.40",
    outputPrice: "$4.40",
    contextWindow: "128K",
    maxTokens: "16K",
    status: "available",
    category: "chat",
    features: ["多语言", "函数调用", "工具使用", "长文档理解", "流式输出"],
    codeExample: {
      curl: `curl https://api.example.com/v1/chat/completions \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer $API_KEY" \\
  -d '{
    "model": "glm-5.1",
    "messages": [{"role": "user", "content": "写一篇关于AI发展的短文"}]
  }'`,
      python: `import openai

client = openai.OpenAI(
    base_url="https://api.example.com/v1",
    api_key="your-api-key"
)

response = client.chat.completions.create(
    model="glm-5.1",
    messages=[{"role": "user", "content": "写一篇关于AI发展的短文"}]
)
print(response.choices[0].message.content)`,
      nodejs: `import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "https://api.example.com/v1",
  apiKey: "your-api-key",
});

const response = await client.chat.completions.create({
  model: "glm-5.1",
  messages: [{ role: "user", content: "写一篇关于AI发展的短文" }],
});
console.log(response.choices[0].message.content);`,
    },
  },
  {
    id: "mimo-v2.5-pro",
    name: "MiMo-V2.5-Pro",
    provider: "小米 MiMo",
    providerLogo: "MI",
    description: "小米多模态旗舰模型，支持文本/图像/音频理解和生成",
    inputPrice: "$0.80",
    outputPrice: "$3.20",
    contextWindow: "32K",
    maxTokens: "8K",
    status: "available",
    category: "multimodal",
    features: ["多模态", "图像理解", "文本生成", "音频处理", "TTS"],
    codeExample: {
      curl: `curl https://api.example.com/v1/chat/completions \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer $API_KEY" \\
  -d '{
    "model": "mimo-v2.5-pro",
    "messages": [{"role": "user", "content": "描述这张图片"}]
  }'`,
      python: `import openai

client = openai.OpenAI(
    base_url="https://api.example.com/v1",
    api_key="your-api-key"
)

response = client.chat.completions.create(
    model="mimo-v2.5-pro",
    messages=[{"role": "user", "content": "描述这张图片"}]
)
print(response.choices[0].message.content)`,
      nodejs: `import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "https://api.example.com/v1",
  apiKey: "your-api-key",
});

const response = await client.chat.completions.create({
  model: "mimo-v2.5-pro",
  messages: [{ role: "user", content: "描述这张图片" }],
});
console.log(response.choices[0].message.content);`,
    },
  },
  {
    id: "gpt-4o",
    name: "GPT-4o",
    provider: "OpenAI",
    providerLogo: "OA",
    description: "OpenAI 旗舰多模态模型，全能型选手",
    inputPrice: "$2.50",
    outputPrice: "$10.00",
    contextWindow: "128K",
    maxTokens: "16K",
    status: "available",
    category: "multimodal",
    features: ["多模态", "函数调用", "JSON 模式", "流式输出", "高精度"],
    codeExample: {
      curl: `curl https://api.example.com/v1/chat/completions \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer $API_KEY" \\
  -d '{
    "model": "gpt-4o",
    "messages": [{"role": "user", "content": "你好，世界"}]
  }'`,
      python: `import openai

client = openai.OpenAI(
    base_url="https://api.example.com/v1",
    api_key="your-api-key"
)

response = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "你好，世界"}]
)
print(response.choices[0].message.content)`,
      nodejs: `import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "https://api.example.com/v1",
  apiKey: "your-api-key",
});

const response = await client.chat.completions.create({
  model: "gpt-4o",
  messages: [{ role: "user", content: "你好，世界" }],
});
console.log(response.choices[0].message.content);`,
    },
  },
  {
    id: "gpt-4o-mini",
    name: "GPT-4o Mini",
    provider: "OpenAI",
    providerLogo: "OA",
    description: "轻量级模型，成本极低，适合简单任务和高吞吐场景",
    inputPrice: "$0.15",
    outputPrice: "$0.60",
    contextWindow: "128K",
    maxTokens: "16K",
    status: "available",
    category: "chat",
    features: ["函数调用", "JSON 模式", "流式输出", "低成本"],
    codeExample: {
      curl: `curl https://api.example.com/v1/chat/completions \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer $API_KEY" \\
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "你好"}]
  }'`,
      python: `import openai

client = openai.OpenAI(
    base_url="https://api.example.com/v1",
    api_key="your-api-key"
)

response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "你好"}]
)
print(response.choices[0].message.content)`,
      nodejs: `import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "https://api.example.com/v1",
  apiKey: "your-api-key",
});

const response = await client.chat.completions.create({
  model: "gpt-4o-mini",
  messages: [{ role: "user", content: "你好" }],
});
console.log(response.choices[0].message.content);`,
    },
  },
  {
    id: "claude-3.5-sonnet",
    name: "Claude 3.5 Sonnet",
    provider: "Anthropic",
    providerLogo: "AN",
    description: "Anthropic 旗舰模型，代码和推理能力出色",
    inputPrice: "$3.00",
    outputPrice: "$15.00",
    contextWindow: "200K",
    maxTokens: "8K",
    status: "available",
    category: "code",
    features: ["代码生成", "长文档", "安全护栏", "函数调用", "流式输出"],
    codeExample: {
      curl: `curl https://api.example.com/v1/chat/completions \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer $API_KEY" \\
  -d '{
    "model": "claude-3.5-sonnet",
    "messages": [{"role": "user", "content": "写一个快速排序算法"}]
  }'`,
      python: `import openai

client = openai.OpenAI(
    base_url="https://api.example.com/v1",
    api_key="your-api-key"
)

response = client.chat.completions.create(
    model="claude-3.5-sonnet",
    messages=[{"role": "user", "content": "写一个快速排序算法"}]
)
print(response.choices[0].message.content)`,
      nodejs: `import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "https://api.example.com/v1",
  apiKey: "your-api-key",
});

const response = await client.chat.completions.create({
  model: "claude-3.5-sonnet",
  messages: [{ role: "user", content: "写一个快速排序算法" }],
});
console.log(response.choices[0].message.content);`,
    },
  },
  {
    id: "glm-4.7-flash",
    name: "GLM-4.7 Flash",
    provider: "智谱 Z.ai",
    providerLogo: "ZP",
    description: "智谱免费轻量模型，适合原型开发和测试",
    inputPrice: "免费",
    outputPrice: "免费",
    contextWindow: "32K",
    maxTokens: "4K",
    status: "available",
    category: "chat",
    features: ["免费使用", "快速响应", "流式输出"],
    codeExample: {
      curl: `curl https://api.example.com/v1/chat/completions \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer $API_KEY" \\
  -d '{
    "model": "glm-4.7-flash",
    "messages": [{"role": "user", "content": "今天天气如何"}]
  }'`,
      python: `import openai

client = openai.OpenAI(
    base_url="https://api.example.com/v1",
    api_key="your-api-key"
)

response = client.chat.completions.create(
    model="glm-4.7-flash",
    messages=[{"role": "user", "content": "今天天气如何"}]
)
print(response.choices[0].message.content)`,
      nodejs: `import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "https://api.example.com/v1",
  apiKey: "your-api-key",
});

const response = await client.chat.completions.create({
  model: "glm-4.7-flash",
  messages: [{ role: "user", content: "今天天气如何" }],
});
console.log(response.choices[0].message.content);`,
    },
  },
];

/** API 文档错误码 */
export const errorCodes = [
  { code: 200, message: "成功", description: "请求已成功处理" },
  { code: 400, message: "请求参数错误", description: "请求体格式不正确或缺少必填参数" },
  { code: 401, message: "认证失败", description: "API Key 无效或已过期" },
  { code: 402, message: "额度不足", description: "账户余额不足以完成本次请求" },
  { code: 429, message: "请求过于频繁", description: "超出速率限制，请稍后重试" },
  { code: 500, message: "服务器内部错误", description: "服务器内部错误，请稍后重试" },
  { code: 503, message: "服务暂不可用", description: "模型服务暂时不可用或正在维护" },
];
