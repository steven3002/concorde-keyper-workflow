const CONTROL_URL = "http://127.0.0.1:8081";

async function main(): Promise<void> {
  const [command, ...args] = process.argv.slice(2);

  if (command === "inject") {
    const chatId = args[0];
    const text = args[1];
    if (!chatId || text === undefined) {
      console.error("Usage: cli.ts inject <chatId> <text> [updateId]");
      process.exit(1);
    }
    const updateId = args[2] ? Number(args[2]) : Date.now();
    const update = {
      update_id: updateId,
      message: {
        message_id: Math.floor(Math.random() * 100000) + 1,
        text,
        chat: { id: Number(chatId) || 12345, type: "private" },
        from: { id: Number(chatId) || 12345, username: "testuser" },
      },
    };

    const res = await fetch(`${CONTROL_URL}/control/inject`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ update }),
    });
    if (!res.ok) {
      console.error("Failed to inject update:", await res.text());
      process.exit(1);
    }
    const json = await res.json();
    console.log(JSON.stringify(json));
    return;
  }

  if (command === "sent") {
    const res = await fetch(`${CONTROL_URL}/control/sent`);
    if (!res.ok) {
      console.error("Failed to list sent messages:", await res.text());
      process.exit(1);
    }
    const json = await res.json();
    console.log(JSON.stringify(json, null, 2));
    return;
  }

  if (command === "clear") {
    const res = await fetch(`${CONTROL_URL}/control/clear`, { method: "POST" });
    if (!res.ok) {
      console.error("Failed to clear messages:", await res.text());
      process.exit(1);
    }
    const json = await res.json();
    console.log(JSON.stringify(json));
    return;
  }

  console.error("Unknown command. Available commands: inject, sent, clear");
  process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
