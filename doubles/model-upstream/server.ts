import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { RequestStore, type RecordedRequest } from "./requests.ts";
import { decideNextResponse } from "./script.ts";
import { formatDone, formatSSE, type StreamChunk } from "./stream.ts";

const store = new RequestStore();

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

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Model upstream public server: receives calls from relay
const modelServer = createServer(async (req, res) => {
  if (req.url !== "/v1/chat/completions") {
    return sendJson(res, 404, { error: { message: "Not Found", type: "invalid_request_error" } });
  }

  if (req.method !== "POST") {
    return sendJson(res, 405, { error: { message: "Method Not Allowed", type: "invalid_request_error" } });
  }

  const body = await readJson(req);

  const record: RecordedRequest = {
    timestamp: new Date().toISOString(),
    method: req.method,
    url: req.url,
    headers: req.headers,
    body,
  };
  store.record(record);

  const modelId = typeof body.model === "string" ? body.model : "keyper-status-model";
  const messages = Array.isArray(body.messages) ? body.messages : [];
  const decision = decideNextResponse(messages);

  res.writeHead(200, {
    "content-type": "text/event-stream",
    "cache-control": "no-cache",
    connection: "keep-alive",
  });

  const responseId = `chatcmpl-${Math.random().toString(36).slice(2, 10)}`;
  const created = Math.floor(Date.now() / 1000);

  if (decision.type === "tool_call") {
    const callId = `call_${Math.random().toString(36).slice(2, 10)}`;
    const chunk1: StreamChunk = {
      id: responseId,
      object: "chat.completion.chunk",
      created,
      model: modelId,
      choices: [
        {
          index: 0,
          delta: {
            role: "assistant",
            tool_calls: [
              {
                index: 0,
                id: callId,
                type: "function",
                function: {
                  name: decision.toolCall.name,
                  arguments: JSON.stringify(decision.toolCall.arguments),
                },
              },
            ],
          },
          finish_reason: null,
        },
      ],
    };
    res.write(formatSSE(chunk1));

    // Pause between chunks to provide unbuffered streaming timing evidence
    await delay(500);

    const chunk2: StreamChunk = {
      id: responseId,
      object: "chat.completion.chunk",
      created,
      model: modelId,
      choices: [
        {
          index: 0,
          delta: {},
          finish_reason: "tool_calls",
        },
      ],
      usage: {
        prompt_tokens: 30,
        completion_tokens: 15,
        total_tokens: 45,
      },
    };
    res.write(formatSSE(chunk2));
    res.write(formatDone());
    res.end();
    return;
  }

  // Final message turn
  const chunk1: StreamChunk = {
    id: responseId,
    object: "chat.completion.chunk",
    created,
    model: modelId,
    choices: [
      {
        index: 0,
        delta: {
          role: "assistant",
          content: decision.content,
        },
        finish_reason: null,
      },
    ],
  };
  res.write(formatSSE(chunk1));

  // Pause between chunks to provide unbuffered streaming timing evidence
  await delay(500);

  const chunk2: StreamChunk = {
    id: responseId,
    object: "chat.completion.chunk",
    created,
    model: modelId,
    choices: [
      {
        index: 0,
        delta: {},
        finish_reason: "stop",
      },
    ],
    usage: {
      prompt_tokens: 50,
      completion_tokens: 20,
      total_tokens: 70,
    },
  };
  res.write(formatSSE(chunk2));
  res.write(formatDone());
  res.end();
});

// Control server: loopback only, used by cli.ts via docker compose exec
const controlServer = createServer(async (req, res) => {
  if (req.url === "/control/requests" && req.method === "GET") {
    return sendJson(res, 200, { ok: true, requests: store.list() });
  }

  if (req.url === "/control/clear" && req.method === "POST") {
    store.clear();
    return sendJson(res, 200, { ok: true });
  }

  return sendJson(res, 404, { error: "Not Found" });
});

const MODEL_SERVER_PORT = 8080;
const CONTROL_PORT = 8081;

modelServer.listen(MODEL_SERVER_PORT, "0.0.0.0", () => {
  console.log(`Model upstream double listening on 0.0.0.0:${MODEL_SERVER_PORT}`);
});

controlServer.listen(CONTROL_PORT, "127.0.0.1", () => {
  console.log(`Model upstream control server listening on 127.0.0.1:${CONTROL_PORT}`);
});
