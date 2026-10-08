# Concorde Keyper Workflow

A credential-isolated reference deployment for a Shutter Keyper status monitoring agent built on the Concorde framework.

## 1. What This Is (and What It Is Not)

This repository provides an automated, credential-isolated reference deployment for an operations agent that monitors Shutter Keyper node health, uptime, and sync status.

- **What it is:** A read-only status workflow. Incoming status queries over Telegram reach a Concorde gateway, triggering an agent runner that queries permitted public Keyper metrics via an allowlisting proxy and returns formatted answers to the operator. The agent executes in a hardened container with strict network isolation and zero access to external credentials.
- **What it is not:** It is **not** a conversational chatbot, **not** an administrative dashboard, **not** a general-purpose security platform, and **not** a Keyper node controller. It holds no signing keys, sends no transactions, and cannot modify Keyper node state.

For component boundaries and upstream code acquisition details, see [`SCOPE.md`](SCOPE.md). For verified execution outputs, see [`RESULTS.md`](RESULTS.md).

---

## 2. Prerequisites

The deployment targets a native Linux host running Docker Engine and Docker Compose with bridge network isolation capabilities:

| Component | Pinned Version / Digest | Notes |
|---|---|---|
| **Operating System** | Linux x86_64 (tested on Ubuntu 24.04.4 LTS, kernel `6.17.0-1022-azure`) | Requires standard Linux bridge networking support |
| **Docker Engine** | `29.8.0` (or >= `28.0.0`) | Minimum version floor `28.0.0` required for isolated gateway mode (`com.docker.network.bridge.gateway_mode_ipv4=isolated`) |
| **Docker Compose** | `v5.5.1` | Supports multi-file env overlays and compose overlay inheritance |
| **Node Image** | `node:24-alpine@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1` | Pinned in `pins.env`; all Node code runs in containers |
| **PostgreSQL Image**| `postgres:17@sha256:ae69c452f483507a6b99fb654cf93aad7fe156ffd2c56247707eef4e36d3c12b` | Pinned in `pins.env` |
| **Nginx Image** | `nginx:1.30.5-alpine@sha256:0985e772fb9f729e6fa0980da05fca5d9c468e870eed43071545afa9d2e27d94` | Pinned in `pins.env`; used for `relay` and `metrics-gate` |
| **Upstream Concorde** | `shutter-network/concorde` @ `03dda6a0b1a79077737342709f346bf463a94e20` | Fetched during image build |
| **Upstream Prototype**| `shutter-network/keyper-concorde-agent` @ `f5a5c17e1f39570f84d953bb46dba0f35f15b3dc` | Fetched during image build |
| **Agent CLI** | `@earendil-works/pi-coding-agent@0.85.1` | Pinned in `pins.env` |

---

## 3. Clean-Install Commands (Fixture Mode)

In Fixture Mode, the deployment runs completely hermetically:
- No real credentials are required; all secrets are recognisable synthetic dummy values defined in `fixtures.env`.
- Test doubles (`model-upstream`, `bot-api`, `metrics-fixture`, `canary`) stand in for external services on an internal egress network.
- No outbound internet traffic is permitted or needed.

To install and run the complete verification suite from a fresh clone:

```bash
# 1. Clone repository
git clone https://github.com/steven3002/concorde-keyper-workflow.git
cd concorde-keyper-workflow

# 2. Make verification scripts executable
chmod +x checks/run-all.sh checks/harness/*.sh checks/*/run.sh

# 3. Execute the master test runner
./checks/run-all.sh
```

To run the fixture stack manually in the background:

```bash
docker compose \
  --env-file pins.env \
  --env-file fixtures.env \
  -f compose.yml \
  -f compose.fixtures.yml \
  up -d
```

To stop and remove fixture containers and volumes:

```bash
docker compose \
  --env-file pins.env \
  --env-file fixtures.env \
  -f compose.yml \
  -f compose.fixtures.yml \
  down -v
```

---

## 4. Running Workflow & Security Checks

All checks run via standard bash harness scripts without requiring any host-level dependencies beyond Docker, Compose, and bash.

### 4.1 Workflow Check

Runs the end-to-end message → metrics → reply workflow test:

```bash
./checks/harness/capture.sh workflow ./checks/workflow/run.sh
```

**What a pass looks like:**
```text
=== Starting end-to-end workflow check (s4) ===
Resetting and starting stack...
Waiting for gateway healthy status...
Injecting user query into bot-api: "What is the current status of keypers?"
Waiting for response to arrive via Telegram (bound: 60s)...
Received outbound message from agent:
"Keyper cluster status: 30 of 39 keypers are currently online..."
[PASS] S4.1 Network isolation settings - agent network is internal and uses isolated gateway mode
[PASS] S4.2 Inbound message to agent prompt - Telegram message was received and dispatched to agent
[PASS] S4.3 Permitted Grafana panel queries - Agent queried permitted panel routes via metrics-gate
[PASS] S4.4 Agent outbound message posting - Agent posted status response via Concorde Agent API
[PASS] S4.5 Outbound message delivery - Status response was delivered to Telegram outbox
[PASS] S4.6 Relay credential substitution in workflow - Every model request arrived with substituted relay key; placeholder never leaked
=== All workflow checks (s4) passed successfully ===
=== Run ended with exit code 0 ===
```

### 4.2 Security Conditions Check (S1–S5)

Runs the comprehensive security test suite verifying all five security conditions from within the caged agent container with paired negative and positive controls:

```bash
./checks/harness/capture.sh security ./checks/security/run.sh
```

**What a pass looks like:**
```text
=== Starting security conditions verification (s5) ===
=== Step 1: Condition S1 (Upstream Key Absence) ===
[PASS] S1 Key absence from agent - Model upstream key is absent from agent env and filesystem; injected key detected by control
=== Step 2: Condition S2 (Prohibited Destination Unreachable) ===
[PASS] S2 Prohibited destination unreachable - External IPs and domains unreachable from agent; canary hits: 0; canary hit verified by weakened control
=== Step 3: Condition S3 (Excluded Internal Services Unreachable) ===
[PASS] S3 Excluded internal services unreachable - PostgreSQL, doubles, gateway public, and Docker host unreachable from agent; all paired controls succeeded
=== Step 4: Condition S4 (Unapproved Relay Routes Rejected) ===
[PASS] S4 Unapproved relay routes rejected - Unapproved methods and routes rejected (404/405/400); absolute targets and forged Host rewrite verified; canary hits: 0
=== Step 5: Condition S5 (Relay Stopped Clear Failure) ===
[PASS] S5 Relay stopped failure - Stopping relay causes bounded failure notification; 0 upstream requests; stack recovers on restart
==========================================================
All five security conditions (S1–S5) passed successfully!
==========================================================
=== Run ended with exit code 0 ===
```

---

## 5. Switching to Live Mode

In Live Mode:
- The deployment connects directly to an OpenAI-compatible provider endpoint, the live Telegram Bot API (`https://api.telegram.org`), and the public Grafana metrics service (`https://grafana.metrics.shutter.network`).
- `compose.yml` runs standalone without `compose.fixtures.yml`.
- Credentials live strictly in an untracked `.env` file that is never committed.

### Step 1: Create `.env`

Copy `.env.example` to `.env`:

```bash
cp .env.example .env
```

Set the operational variables in `.env`:

```bash
# Model provider endpoint and API key (held solely by the relay container)
MODEL_UPSTREAM_ORIGIN=https://api.openai.com
MODEL_UPSTREAM_KEY=sk-...

# Telegram bot token and authorized chat ID
TELEGRAM_BOT_TOKEN=123456789:ABCdef...
TELEGRAM_CHAT_ID=123456789
TELEGRAM_API_BASE=https://api.telegram.org

# Grafana metrics upstream
METRICS_UPSTREAM_ORIGIN=https://grafana.metrics.shutter.network

# Local PostgreSQL database credentials
POSTGRES_USER=concorde
POSTGRES_PASSWORD=your_secure_password
POSTGRES_DB=concorde
```

### Step 2: Configure Model Identifier

Configure the model name in `agent/models.json` and `agent/settings.json` (for example, `gpt-4o-mini`):

- In `agent/models.json`:
  ```json
  "models": [
    {
      "id": "gpt-4o-mini",
      "name": "GPT-4o Mini",
      ...
    }
  ]
  ```
- In `agent/settings.json`:
  ```json
  {
    "defaultProvider": "relay",
    "defaultModel": "gpt-4o-mini"
  }
  ```

### Step 3: Start Live Stack

```bash
docker compose \
  --env-file pins.env \
  --env-file .env \
  -f compose.yml \
  up -d
```

### Step 4: Verify Services

```bash
docker compose --env-file pins.env --env-file .env -f compose.yml ps
docker compose --env-file pins.env --env-file .env -f compose.yml logs -f gateway
```

---

## 6. Hard Limits

The security and operational design enforces explicit, well-defined boundaries:

1. **Prompt injection is not prevented.** The deployment bounds what an injected agent holds and can reach; it does not prevent a malicious user from instructing the model.
2. **The reply channel is open.** The agent can put anything it discovers into an outbound message delivered to the operator over Telegram.
3. **The relay is a credential boundary, not an authorization boundary.** The agent can consume the upstream key's quota. There is no rate limit and no inspection of request bodies; model name selection is not constrained by the proxy.
4. **The metrics gate filters by route and method only.** Request bodies are not parsed or validated.
5. **The gateway is trusted.** It holds the Telegram bot token and database credentials. A compromised gateway is outside this threat model.
6. **One host configuration.** Native Linux x86_64 with Docker Engine >= 28.0.0. Rootless Docker, Docker Desktop, macOS, Windows, Podman, Kubernetes, and IPv6 are untested.
7. **Host isolation depends on isolated gateway mode.** Linux bridge driver option `com.docker.network.bridge.gateway_mode_ipv4=isolated` is required to block host-bound listeners (`0.0.0.0`).
8. **One model API profile.** OpenAI-compatible Chat Completions with streaming Server-Sent Events (SSE) and tool calls.
9. **One user, one chat.** Group routing, multi-user channels, and multi-keyper mapping are out of scope.
10. **Not a product.** No monitoring dashboards, administrative tooling, or automated node interventions are included.

---

## 7. Deliverables & Documentation

- [`SCOPE.md`](SCOPE.md): Architectural boundaries, upstream reuse analysis, and implementation scope.
- [`RESULTS.md`](RESULTS.md): Full captured test execution outputs, logs, synthetic inputs, and untested items.
- [`compose.yml`](compose.yml): The production service topology (6 services, 3 isolated networks).
- [`compose.fixtures.yml`](compose.fixtures.yml): Fixture overlay adding hermetic doubles.
- [`checks/run-all.sh`](checks/run-all.sh): Master test runner for all verification suites.
