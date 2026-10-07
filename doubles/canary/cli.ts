const CONTROL_URL = "http://127.0.0.1:8081";

async function main(): Promise<void> {
  const [command] = process.argv.slice(2);

  if (command === "hits" || command === "connections") {
    const res = await fetch(`${CONTROL_URL}/control/hits`);
    if (!res.ok) {
      console.error("Failed to list canary connections:", await res.text());
      process.exit(1);
    }
    const json = await res.json();
    console.log(JSON.stringify(json, null, 2));
    return;
  }

  if (command === "clear") {
    const res = await fetch(`${CONTROL_URL}/control/clear`, { method: "POST" });
    if (!res.ok) {
      console.error("Failed to clear canary connections:", await res.text());
      process.exit(1);
    }
    const json = await res.json();
    console.log(JSON.stringify(json));
    return;
  }

  console.error("Unknown command. Available commands: hits, clear");
  process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
