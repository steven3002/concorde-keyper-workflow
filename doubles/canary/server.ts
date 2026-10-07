import { createServer, type Socket } from "node:net";
import { createServer as createHttpServer, type IncomingMessage, type ServerResponse } from "node:http";

export interface RecordedConnection {
  timestamp: string;
  remoteAddress: string;
  remotePort: number;
  preview: string;
}

class ConnectionStore {
  private connections: RecordedConnection[] = [];

  record(conn: RecordedConnection): void {
    this.connections.push(conn);
  }

  list(): RecordedConnection[] {
    return [...this.connections];
  }

  clear(): void {
    this.connections = [];
  }
}

const store = new ConnectionStore();

// Canary listener on 0.0.0.0:8080 records every connection received from egress
const canaryServer = createServer((socket: Socket) => {
  const remoteAddress = socket.remoteAddress ?? "unknown";
  const remotePort = socket.remotePort ?? 0;
  let recorded = false;

  socket.on("data", (chunk: Buffer) => {
    if (!recorded) {
      recorded = true;
      const preview = chunk.toString("utf8", 0, Math.min(chunk.length, 256));
      store.record({
        timestamp: new Date().toISOString(),
        remoteAddress,
        remotePort,
        preview,
      });
    }

    // Respond with HTTP 200 or raw OK to allow caller to complete gracefully
    const text = chunk.toString("utf8");
    if (text.startsWith("GET ") || text.startsWith("POST ") || text.startsWith("HEAD ") || text.startsWith("PUT ")) {
      socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK");
    } else {
      socket.write("OK\n");
    }
    socket.end();
  });

  socket.on("error", () => {
    // Errors on client disconnect are ignored
  });
});

// Control server: loopback only on 127.0.0.1:8081 for cli.ts
const controlServer = createHttpServer((req: IncomingMessage, res: ServerResponse) => {
  const url = req.url ?? "";

  if ((url === "/control/hits" || url === "/control/connections") && req.method === "GET") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ ok: true, hits: store.list(), count: store.list().length }));
    return;
  }

  if (url === "/control/clear" && req.method === "POST") {
    store.clear();
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ ok: true }));
    return;
  }

  res.writeHead(404, { "content-type": "application/json" });
  res.end(JSON.stringify({ error: "Not Found" }));
});

const CANARY_PORT = 8080;
const CONTROL_PORT = 8081;

canaryServer.listen(CANARY_PORT, "0.0.0.0", () => {
  console.log(`Canary double listening on 0.0.0.0:${CANARY_PORT}`);
});

controlServer.listen(CONTROL_PORT, "127.0.0.1", () => {
  console.log(`Canary control server listening on 127.0.0.1:${CONTROL_PORT}`);
});
