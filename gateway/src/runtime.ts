import { createPiRuntime } from "@shutter-network/concorde/pi";
import type { Runtime } from "@shutter-network/concorde/signals";
import type { GatewayConfig } from "./config.ts";

export function buildRuntime(config: GatewayConfig): Runtime {
  return createPiRuntime({
    host: config.agentInstanceHost,
    port: config.agentInstancePort,
    sessionsDir: config.agentSessionsDir,
  });
}
