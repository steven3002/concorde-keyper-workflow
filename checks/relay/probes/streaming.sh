#!/bin/sh
set -eu

# Direct in-container probe to verify incremental unbuffered streaming through the relay
node -e '
const http = require("http");

const payload = JSON.stringify({
  model: "keyper-status-model",
  messages: [{ role: "user", content: "Probe streaming check" }],
  stream: true
});

const req = http.request("http://relay:8080/v1/chat/completions", {
  method: "POST",
  headers: {
    "content-type": "application/json",
    "authorization": "Bearer dummy-agent-placeholder-key"
  }
}, (res) => {
  if (res.statusCode !== 200) {
    console.error("Relay returned HTTP status:", res.statusCode);
    process.exit(1);
  }

  const events = [];
  let buffer = "";

  res.on("data", (chunk) => {
    const now = Date.now();
    buffer += chunk.toString("utf8");
    const lines = buffer.split("\n\n");
    buffer = lines.pop(); // keep remainder

    for (const line of lines) {
      if (line.startsWith("data:")) {
        events.push({ time: now, raw: line });
        console.log(`[STREAM EVENT ${events.length}] +${events.length === 1 ? 0 : now - events[0].time}ms: ${line.slice(0, 60)}...`);
      }
    }
  });

  res.on("end", () => {
    if (events.length < 2) {
      console.error("Expected at least 2 streamed events, received:", events.length);
      process.exit(1);
    }
    const deltaMs = events[1].time - events[0].time;
    console.log(`Measured delay between event 1 and event 2: ${deltaMs}ms`);
    if (deltaMs < 250) {
      console.error("Events arrived virtually simultaneously; response appears buffered!");
      process.exit(1);
    }
    console.log("Stream unbuffering verified successfully.");
    process.exit(0);
  });
});

req.on("error", (err) => {
  console.error("Request failed:", err.message);
  process.exit(1);
});

req.write(payload);
req.end();
'
