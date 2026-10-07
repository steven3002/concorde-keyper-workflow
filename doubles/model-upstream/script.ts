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

export function decideNextResponse(messages: unknown[]): ScriptDecision {
  if (!Array.isArray(messages)) {
    return { type: "message", content: "Invalid messages format." };
  }

  // Check whether a tool result has already been returned in the conversation
  const hasToolResult = messages.some((m) => {
    return typeof m === "object" && m !== null && (m as { role?: string }).role === "tool";
  });

  if (hasToolResult) {
    return {
      type: "message",
      content: "Keyper status verified and reply sent to user.",
    };
  }

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

  if (extractedUserId) {
    return {
      type: "tool_call",
      toolCall: {
        name: "bash",
        arguments: {
          command: `curl -s -X POST "$AGENT_SERVER_URL/messages/" -H "Content-Type: application/json" -d '{"userId":"${extractedUserId}","text":"Keyper status: all systems operational."}'`,
        },
      },
    };
  }

  // Standalone or direct probe without a formatted user id
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
