export interface DeltaToolCall {
  index: number;
  id?: string;
  type?: "function";
  function?: {
    name?: string;
    arguments?: string;
  };
}

export interface DeltaPayload {
  role?: string;
  content?: string;
  tool_calls?: DeltaToolCall[];
}

export interface StreamChunk {
  id: string;
  object: "chat.completion.chunk";
  created: number;
  model: string;
  choices: Array<{
    index: number;
    delta: DeltaPayload;
    finish_reason: string | null;
  }>;
  usage?: {
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  };
}

export function formatSSE(chunk: StreamChunk): string {
  return `data: ${JSON.stringify(chunk)}\n\n`;
}

export function formatDone(): string {
  return "data: [DONE]\n\n";
}
