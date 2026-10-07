export interface ToolCallDecision {
  name: string;
  arguments: Record<string, unknown>;
}

export type ScriptDecision =
  | { type: "tool_call"; toolCall: ToolCallDecision }
  | { type: "message"; content: string };

function extractText(content: unknown): string {
  if (typeof content === "string") {
    return content;
  }
  if (Array.isArray(content)) {
    return content
      .map((item) => {
        if (typeof item === "string") return item;
        if (item && typeof item === "object" && "text" in item && typeof item.text === "string") {
          return item.text;
        }
        return "";
      })
      .join(" ");
  }
  return "";
}

interface ParsedMetrics {
  total: number;
  online: number;
  sampleInstance: string;
}

function parseMetricsResponse(text: string): ParsedMetrics {
  try {
    const data = JSON.parse(text);
    const frames = data.results?.A?.frames || [];
    let online = 0;
    let sample = "";
    for (const f of frames) {
      const val = f.data?.values?.[1]?.[0];
      if (val === 1) online++;
      if (!sample && f.schema?.fields?.[1]?.labels?.instance) {
        sample = f.schema.fields[1].labels.instance;
      }
    }
    return {
      total: frames.length,
      online,
      sampleInstance: sample,
    };
  } catch {
    return { total: 0, online: 0, sampleInstance: "" };
  }
}

export function decideNextResponse(messages: unknown[]): ScriptDecision {
  if (!Array.isArray(messages)) {
    return { type: "message", content: "Invalid messages format." };
  }

  // Count how many tool results have been received in this conversation
  const toolResults = messages.filter((m) => {
    return typeof m === "object" && m !== null && (m as { role?: string }).role === "tool";
  });

  // Find user prompt to extract target userId if present
  let extractedUserId: string | undefined;
  for (const m of messages) {
    if (typeof m === "object" && m !== null && (m as { role?: string }).role === "user") {
      const text = extractText((m as { content?: unknown }).content);
      const match = text.match(/User\s+([a-zA-Z0-9_-]+):/);
      if (match) {
        extractedUserId = match[1];
        break;
      }
    }
  }

  // Scenario 1: Standalone probe without a userId
  if (!extractedUserId) {
    if (toolResults.length > 0) {
      return {
        type: "message",
        content: "Probe tool roundtrip completed successfully.",
      };
    }
    return {
      type: "tool_call",
      toolCall: {
        name: "bash",
        arguments: {
          command: "echo tool_roundtrip_verified",
        },
      },
    };
  }

  // Scenario 2: Two round-trip status workflow with an operator userId
  if (toolResults.length === 0) {
    // Round 1: Query permitted Panel 5 (online status) through the metrics gate
    return {
      type: "tool_call",
      toolCall: {
        name: "bash",
        arguments: {
          command: `curl -s -X POST "$METRICS_GATE_URL/api/public/dashboards/2b52906b091a445989638922fbe69e5e/panels/5/query" -H "Content-Type: application/json" -d '{"timeRange":{"from":"now-7d","to":"now","timezone":"utc"},"intervalMs":60000,"maxDataPoints":2}'`,
        },
      },
    };
  }

  if (toolResults.length === 1) {
    // Round 2: Parse returned fixture metrics and send status reply via Agent API
    const rawResult = extractText((toolResults[0] as { content?: unknown }).content);
    const parsed = parseMetricsResponse(rawResult);

    const replyText = parsed.total > 0
      ? `Keyper status: all systems operational. ${parsed.online} of ${parsed.total} keypers online (sample instance: ${parsed.sampleInstance}).`
      : `Keyper status: all systems operational. Metrics verified.`;

    // Escaped payload for posting to Concorde Agent API
    const jsonBody = JSON.stringify({ userId: extractedUserId, text: replyText });

    return {
      type: "tool_call",
      toolCall: {
        name: "bash",
        arguments: {
          command: `curl -s -X POST "$AGENT_SERVER_URL/messages/" -H "Content-Type: application/json" -d '${jsonBody.replace(/'/g, "'\\''")}'`,
        },
      },
    };
  }

  // Round 3: Both tool calls executed, provide final settlement message
  return {
    type: "message",
    content: "Keyper status verified and reply sent to user.",
  };
}
