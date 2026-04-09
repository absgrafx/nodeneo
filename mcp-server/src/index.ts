import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const GATEWAY_URL = process.env.NODENEO_GATEWAY_URL ?? "http://127.0.0.1:8069";
const API_KEY = process.env.NODENEO_API_KEY ?? "";

// ---------------------------------------------------------------------------
// HTTP helpers — talk to the NodeNeo gateway on localhost
// ---------------------------------------------------------------------------

async function gatewayFetch(path: string, init?: RequestInit): Promise<Response> {
  const url = `${GATEWAY_URL}${path}`;
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(API_KEY ? { Authorization: `Bearer ${API_KEY}` } : {}),
    ...(init?.headers as Record<string, string> | undefined),
  };
  return fetch(url, { ...init, headers });
}

interface ModelEntry {
  id: string;
  object: string;
  created: number;
  owned_by: string;
  blockchainID?: string;
  tags?: string[];
  modelType?: string;
}

interface ModelsResponse {
  object: string;
  data: ModelEntry[];
}

interface ChatMessage {
  role: string;
  content: string;
}

interface ChatChoice {
  index: number;
  message: ChatMessage;
  finish_reason: string;
}

interface ChatResponse {
  id: string;
  object: string;
  created: number;
  model: string;
  choices: ChatChoice[];
}

// ---------------------------------------------------------------------------
// MCP Server
// ---------------------------------------------------------------------------

const server = new McpServer({
  name: "nodeneo-morpheus",
  version: "0.1.0",
});

// -- Tool: morpheus_models ------------------------------------------------

server.registerTool(
  "morpheus_models",
  {
    description:
      "List available AI models on the Morpheus decentralized network. " +
      "Returns model names, types, and tags. Use this to discover which " +
      "models are available before calling morpheus_chat.",
    inputSchema: {},
  },
  async () => {
    const resp = await gatewayFetch("/v1/models");
    if (!resp.ok) {
      const body = await resp.text();
      return {
        isError: true,
        content: [{ type: "text" as const, text: `Gateway error ${resp.status}: ${body}` }],
      };
    }

    const data: ModelsResponse = await resp.json();
    const lines = data.data.map(
      (m) =>
        `• ${m.id}  [${m.modelType ?? "unknown"}]${m.tags?.length ? "  tags: " + m.tags.join(", ") : ""}`
    );

    return {
      content: [
        {
          type: "text" as const,
          text: `Available Morpheus models (${data.data.length}):\n\n${lines.join("\n")}`,
        },
      ],
    };
  }
);

// -- Tool: morpheus_chat --------------------------------------------------

server.registerTool(
  "morpheus_chat",
  {
    description:
      "Send a chat prompt to a Morpheus decentralized AI model. " +
      "The model runs on the Morpheus network — all traffic stays local " +
      "between this machine and the provider. Use morpheus_models first " +
      "to see available models. Supports multi-turn via the messages array.",
    inputSchema: {
      model: z
        .string()
        .describe('Model name, e.g. "glm-5.1", "llama3.1-8b"'),
      messages: z
        .array(
          z.object({
            role: z.enum(["system", "user", "assistant"]),
            content: z.string(),
          })
        )
        .describe("Chat messages in OpenAI format"),
    },
  },
  async ({ model, messages }) => {
    const resp = await gatewayFetch("/v1/chat/completions", {
      method: "POST",
      body: JSON.stringify({ model, messages, stream: false }),
    });

    if (!resp.ok) {
      const body = await resp.text();
      return {
        isError: true,
        content: [{ type: "text" as const, text: `Gateway error ${resp.status}: ${body}` }],
      };
    }

    const data: ChatResponse = await resp.json();
    const reply = data.choices?.[0]?.message?.content ?? "(empty response)";

    return {
      content: [{ type: "text" as const, text: reply }],
    };
  }
);

// ---------------------------------------------------------------------------
// Start — stdio transport keeps everything local
// ---------------------------------------------------------------------------

const transport = new StdioServerTransport();
await server.connect(transport);
