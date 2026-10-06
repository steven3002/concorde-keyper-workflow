import { posix } from "node:path";

export type GatewayConfig = {
  readonly databaseUrl: string;
  readonly telegramBotToken: string;
  readonly telegramChatId: string;
  readonly telegramApiBaseUrl: string;
  readonly agentInstanceHost: string;
  readonly agentInstancePort: number;
  readonly agentSessionsDir: string;
  readonly agentServerHost: string;
  readonly agentServerPort: number;
  readonly publicHost: string;
  readonly publicPort: number;
};

function readRequired(env: NodeJS.ProcessEnv, key: string): string {
  const value = env[key];
  if (value === undefined || value.trim() === "") {
    throw new Error(`missing required environment variable: ${key}`);
  }
  return value;
}

function parsePort(env: NodeJS.ProcessEnv, key: string, fallback: number): number {
  const raw = env[key];
  if (raw === undefined || raw.trim() === "") {
    return fallback;
  }
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed <= 0 || parsed > 65535) {
    throw new Error(`invalid port number for ${key}: ${raw}`);
  }
  return parsed;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): GatewayConfig {
  const databaseUrl = readRequired(env, "DATABASE_URL");
  const telegramBotToken = readRequired(env, "TELEGRAM_BOT_TOKEN");
  const telegramChatId = readRequired(env, "TELEGRAM_CHAT_ID");
  const telegramApiBaseUrl = env.TELEGRAM_API_BASE?.trim() || "https://api.telegram.org";

  const agentInstanceHost = env.AGENT_INSTANCE_HOST?.trim() || "agent";
  const agentInstancePort = parsePort(env, "AGENT_INSTANCE_PORT", 4000);
  const agentSessionsDir = env.AGENT_SESSIONS_DIR?.trim() || "/sessions";

  if (!posix.isAbsolute(agentSessionsDir)) {
    throw new Error(`AGENT_SESSIONS_DIR must be an absolute path: ${agentSessionsDir}`);
  }

  const agentServerHost = env.AGENT_SERVER_HOST?.trim() || "0.0.0.0";
  const agentServerPort = parsePort(env, "AGENT_SERVER_PORT", 7411);

  const publicHost = env.PUBLIC_HOST?.trim() || "127.0.0.1";
  const publicPort = parsePort(env, "PUBLIC_PORT", 8081);

  return {
    databaseUrl,
    telegramBotToken,
    telegramChatId,
    telegramApiBaseUrl,
    agentInstanceHost,
    agentInstancePort,
    agentSessionsDir,
    agentServerHost,
    agentServerPort,
    publicHost,
    publicPort,
  };
}
