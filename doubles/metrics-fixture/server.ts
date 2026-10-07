import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

export interface RecordedRoute {
  timestamp: string;
  method: string;
  url: string;
  panelId: string;
}

class RouteStore {
  private routes: RecordedRoute[] = [];

  record(route: RecordedRoute): void {
    this.routes.push(route);
  }

  list(): RecordedRoute[] {
    return [...this.routes];
  }

  clear(): void {
    this.routes = [];
  }
}

const store = new RouteStore();

// Pre-load panel fixtures into memory
const panelsDir = join(__dirname, "panels");
const panelCache = new Map<string, string>();
const permittedPanels = ["1", "2", "5", "6", "7", "9"];

for (const id of permittedPanels) {
  const filePath = join(panelsDir, `panel-${id}.json`);
  if (existsSync(filePath)) {
    panelCache.set(id, readFileSync(filePath, "utf8"));
  }
}

function sendJson(res: ServerResponse, status: number, data: unknown): void {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(data));
}

const PANEL_ROUTE_REGEX = /^\/api\/public\/dashboards\/2b52906b091a445989638922fbe69e5e\/panels\/([0-9]+)\/query$/;

// Public metrics fixture server (called by metrics-gate)
const metricsServer = createServer((req: IncomingMessage, res: ServerResponse) => {
  const url = req.url || "";
  const match = url.match(PANEL_ROUTE_REGEX);

  if (!match) {
    return sendJson(res, 404, { error: "Not Found", message: "Unknown dashboard or panel route" });
  }

  const panelId = match[1];

  if (!permittedPanels.includes(panelId)) {
    return sendJson(res, 404, { error: "Not Found", message: `Panel ${panelId} not permitted` });
  }

  if (req.method !== "POST") {
    return sendJson(res, 405, { error: "Method Not Allowed", message: "Only POST is permitted" });
  }

  const fixtureContent = panelCache.get(panelId);
  if (!fixtureContent) {
    return sendJson(res, 500, { error: "Fixture Missing", message: `No fixture found for panel ${panelId}` });
  }

  store.record({
    timestamp: new Date().toISOString(),
    method: req.method,
    url,
    panelId,
  });

  res.writeHead(200, {
    "content-type": "application/json",
    "cache-control": "no-cache",
  });
  res.end(fixtureContent);
});

// Control server: loopback only, used by cli.ts via docker compose exec
const controlServer = createServer((req: IncomingMessage, res: ServerResponse) => {
  if (req.url === "/control/routes" && req.method === "GET") {
    return sendJson(res, 200, { ok: true, routes: store.list() });
  }

  if (req.url === "/control/clear" && req.method === "POST") {
    store.clear();
    return sendJson(res, 200, { ok: true });
  }

  return sendJson(res, 404, { error: "Not Found" });
});

const METRICS_SERVER_PORT = 8080;
const CONTROL_PORT = 8081;

metricsServer.listen(METRICS_SERVER_PORT, "0.0.0.0", () => {
  console.log(`Metrics fixture double listening on 0.0.0.0:${METRICS_SERVER_PORT}`);
});

controlServer.listen(CONTROL_PORT, "127.0.0.1", () => {
  console.log(`Metrics fixture control server listening on 127.0.0.1:${CONTROL_PORT}`);
});
