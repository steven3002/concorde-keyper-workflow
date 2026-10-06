import type { InfraComponents } from "@shutter-network/concorde/gateway";
import { createUsers, type Users } from "@shutter-network/concorde/users";
import { createMessenger, type Messenger } from "@shutter-network/concorde/messenger";
import { createTelegramChannel, type TelegramChannel } from "../telegram-channel/telegram-channel.ts";
import type { GatewayConfig } from "./config.ts";

export type GatewayExtensions = {
  readonly users: Users;
  readonly messenger: Messenger;
  readonly telegram: TelegramChannel;
};

export function buildComponents(config: GatewayConfig) {
  return (infra: InfraComponents): GatewayExtensions => {
    const users = createUsers({
      db: infra.db,
      agentServer: infra.agentServer,
      publicServer: infra.publicServer,
    });

    const messenger = createMessenger({
      db: infra.db,
      users,
      worker: infra.worker,
      agentServer: infra.agentServer,
    });

    const telegram = createTelegramChannel({
      db: infra.db,
      messenger,
      token: config.telegramBotToken,
      apiBaseUrl: config.telegramApiBaseUrl,
    });

    return { users, messenger, telegram };
  };
}
