const CONTROL_URL = "http://127.0.0.1:8081";

async function main(): Promise<void> {
  const [command] = process.argv.slice(2);

  if (command === "routes") {
    const res = await fetch(`${CONTROL_URL}/control/routes`);
    if (!res.ok) {
      console.error("Failed to list recorded routes:", await res.text());
      process.exit(1);
    }
    const json = await res.json();
    console.log(JSON.stringify(json, null, 2));
    return;
  }

  if (command === "clear") {
    const res = await fetch(`${CONTROL_URL}/control/clear`, { method: "POST" });
    if (!res.ok) {
      console.error("Failed to clear recorded routes:", await res.text());
      process.exit(1);
    }
    const json = await res.json();
    console.log(JSON.stringify(json));
    return;
  }

  console.error("Unknown command. Available commands: routes, clear");
  process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
