import { createGateway } from "@shutter-network/concorde/gateway";
import { loadConfig } from "./config.ts";
import { buildRuntime } from "./runtime.ts";
import { buildComponents } from "./components.ts";
import { buildHandlers } from "./handlers.ts";
import { seedIfEmpty } from "./seed.ts";

async function main(): Promise<void> {
  const config = loadConfig();
  const runtime = buildRuntime(config);

  const gateway = createGateway({
    databaseUrl: config.databaseUrl,
    runtime,
    agentListen: { host: config.agentServerHost, port: config.agentServerPort },
    publicListen: { host: config.publicHost, port: config.publicPort },
    extend: buildComponents(config),
    handlers: buildHandlers(),
  });

  await gateway.start();

  await seedIfEmpty(
    gateway.components.db,
    gateway.components.users,
    gateway.components.telegram,
    config.telegramChatId,
  );

  let stopping = false;
  const stop = async () => {
    if (stopping) return;
    stopping = true;
    try {
      await gateway.stop();
      process.exit(0);
    } catch (error) {
      console.error("Error stopping gateway:", error);
      process.exit(1);
    }
  };

  process.once("SIGINT", () => void stop());
  process.once("SIGTERM", () => void stop());
}

main().catch((error) => {
  console.error("Fatal gateway startup error:", error);
  process.exit(1);
});
