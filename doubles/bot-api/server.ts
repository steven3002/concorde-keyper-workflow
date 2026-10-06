import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { UpdateQueue, type TelegramUpdate } from "./updates.ts";
import { SentStore } from "./sent.ts";

const updates = new UpdateQueue();
const sent = new SentStore();

async function readJson(req: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) {
    chunks.push(typeof chunk === "string" ? Buffer.from(chunk) : chunk);
  }
  const body = Buffer.concat(chunks).toString("utf8").trim();
  if (body === "") return {};
  try {
    return JSON.parse(body) as Record<string, unknown>;
  } catch {
    return {};
  }
}

function sendJson(res: ServerResponse, status: number, data: unknown): void {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(data));
}

// Bot API public server: receives calls from gateway's Telegram channel
const botApiServer = createServer(async (req, res) => {
  const match = req.url?.match(/^\/bot([^/]+)\/([a-zA-Z0-9]+)$/);
  if (!match) {
    return sendJson(res, 404, { ok: false, error_code: 404, description: "Not Found" });
  }

  const [, token, method] = match;
  if (!token) {
    return sendJson(res, 401, { ok: false, error_code: 401, description: "Unauthorized" });
  }

  if (req.method !== "POST") {
    return sendJson(res, 405, { ok: false, error_code: 405, description: "Method Not Allowed" });
  }

  const body = await readJson(req);

  if (method === "getUpdates") {
    const offset = typeof body.offset === "number" ? body.offset : undefined;
    const timeout = typeof body.timeout === "number" ? body.timeout : 0;
    const controller = new AbortController();
    req.on("close", () => controller.abort());

    const result = await updates.poll(offset, timeout, controller.signal);
    return sendJson(res, 200, { ok: true, result });
  }

  if (method === "sendMessage") {
    const chatId = String(body.chat_id ?? "");
    const text = String(body.text ?? "");
    if (!chatId || !text) {
      return sendJson(res, 400, {
        ok: false,
        error_code: 400,
        description: "Bad Request: chat_id and text required",
      });
    }

    const recorded = sent.record(chatId, text);
    return sendJson(res, 200, {
      ok: true,
      result: {
        message_id: recorded.messageId,
        chat: { id: Number(chatId) || 0, type: "private" },
        text: recorded.text,
        date: Math.floor(Date.now() / 1000),
      },
    });
  }

  return sendJson(res, 404, {
    ok: false,
    error_code: 404,
    description: `Not Found: method ${method}`,
  });
});

// Control server: loopback only, used by cli.ts via docker compose exec
const controlServer = createServer(async (req, res) => {
  if (req.url === "/control/inject" && req.method === "POST") {
    const body = await readJson(req);
    const update = body.update as TelegramUpdate | undefined;
    if (!update || typeof update.update_id !== "number") {
      return sendJson(res, 400, { error: "valid update object with update_id required" });
    }
    updates.push(update);
    return sendJson(res, 200, { ok: true, update_id: update.update_id });
  }

  if (req.url === "/control/sent" && req.method === "GET") {
    return sendJson(res, 200, { ok: true, sent: sent.list() });
  }

  if (req.url === "/control/clear" && req.method === "POST") {
    sent.clear();
    return sendJson(res, 200, { ok: true });
  }

  return sendJson(res, 404, { error: "Not Found" });
});

const BOT_API_PORT = 8080;
const CONTROL_PORT = 8081;

botApiServer.listen(BOT_API_PORT, "0.0.0.0", () => {
  console.log(`Bot API double listening on 0.0.0.0:${BOT_API_PORT}`);
});

controlServer.listen(CONTROL_PORT, "127.0.0.1", () => {
  console.log(`Bot API control server listening on 127.0.0.1:${CONTROL_PORT}`);
});
