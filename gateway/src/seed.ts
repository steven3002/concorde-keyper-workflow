import type { Db } from "@shutter-network/concorde/db";
import type { Users } from "@shutter-network/concorde/users";
import type { TelegramChannel } from "../telegram-channel/telegram-channel.ts";

export async function seedIfEmpty(
  db: Db,
  users: Users,
  telegram: TelegramChannel,
  chatId: string,
): Promise<string | undefined> {
  const existing = await users.list({ limit: 1 });
  if (existing.length > 0) {
    return existing[0].id;
  }

  return await db.tx(async (tx) => {
    const user = await users.create(tx);
    await telegram.recordChat(tx, user.id, chatId);
    return user.id;
  });
}
