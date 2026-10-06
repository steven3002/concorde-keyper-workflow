import type { InfraComponents } from "@shutter-network/concorde/gateway";
import { messageReceivedKind, type MessageRecord } from "@shutter-network/concorde/messenger";
import {
  templateHandler,
  type PostOutcome,
  type Signal,
  type SignalHandlers,
} from "@shutter-network/concorde/signals";
import type { GatewayExtensions } from "./components.ts";

export const RUN_FAILURE_MESSAGE =
  "I am unable to process your request at this time. Please try again later.";

export function buildHandlers() {
  return (components: InfraComponents & GatewayExtensions): SignalHandlers => {
    const handler = templateHandler<MessageRecord>({
      template: "User {{userId}}: {{text}}",
      session: (signal: Signal<MessageRecord>) => `user_${signal.payload.userId}`,
      data: (signal: Signal<MessageRecord>) => ({
        userId: signal.payload.userId,
        text: signal.payload.text,
      }),
    });

    return {
      [messageReceivedKind]: {
        ...handler,
        async post(signal: Signal<MessageRecord>, outcome: PostOutcome) {
          if (outcome.failed) {
            await components.db.tx(async (tx) => {
              await components.messenger.send(tx, signal.payload.userId, RUN_FAILURE_MESSAGE);
            });
          }
        },
      },
    };
  };
}
