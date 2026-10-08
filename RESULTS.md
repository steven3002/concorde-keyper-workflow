# Verification Results

Test execution results captured from clean runs on the supported host environment.

## Environment & Provenance

- **Date:** 2026-10-08
- **Commit:** `023755d0fa68cc785b2322a80b75bc2a073f6161`
- **Host:** Ubuntu 24.04.4 LTS (`x86_64`, Linux kernel `6.17.0-1022-azure`)
- **Docker Engine:** `29.8.0` (cgroup v2, overlayfs, isolated gateway mode supported)
- **Docker Compose:** `v5.5.1`
- **Pinned Upstream Revisions & Digests:**
  - `shutter-network/concorde`: `03dda6a0b1a79077737342709f346bf463a94e20`
  - `shutter-network/keyper-concorde-agent`: `f5a5c17e1f39570f84d953bb46dba0f35f15b3dc`
  - `node:24-alpine`: `sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1`
  - `postgres:17`: `sha256:ae69c452f483507a6b99fb654cf93aad7fe156ffd2c56247707eef4e36d3c12b`
  - `nginx:1.30.5-alpine`: `sha256:0985e772fb9f729e6fa0980da05fca5d9c468e870eed43071545afa9d2e27d94`
  - `@earendil-works/pi-coding-agent`: `0.85.1`

---

## Results Summary

| Suite / Check | Mode | Command | Output Log | Verdict |
|---|---|---|---|---|
| Upstream Channel | **fixture** | `./checks/harness/capture.sh upstream-channel ./checks/upstream-channel/run.sh` | [`results/fixture/upstream-channel/output.log`](results/fixture/upstream-channel/output.log) | **PASS** (21/21 passed) |
| Baseline Deployment | **fixture** | `./checks/harness/capture.sh baseline ./checks/baseline/run.sh` | [`results/fixture/baseline/output.log`](results/fixture/baseline/output.log) | **PASS** (5/5 passed) |
| Model Relay | **fixture** | `./checks/harness/capture.sh relay ./checks/relay/run.sh` | [`results/fixture/relay/output.log`](results/fixture/relay/output.log) | **PASS** (8/8 passed) |
| Status Workflow | **fixture** | `./checks/harness/capture.sh workflow ./checks/workflow/run.sh` | [`results/fixture/workflow/output.log`](results/fixture/workflow/output.log) | **PASS** (6/6 passed) |
| Security Conditions (S1–S5) | **fixture** | `./checks/harness/capture.sh security ./checks/security/run.sh` | [`results/fixture/security/output.log`](results/fixture/security/output.log) | **PASS** (5/5 passed with paired controls) |
| Live Operational Run | **live** | `docker compose --env-file pins.env --env-file .env -f compose.yml up -d` | [`results/live/output.log`](results/live/output.log) | **PASS** (End-to-end live flow verified) |

---

## Detailed Check Results

### 1. Upstream Telegram Channel (`upstream-channel`) — Fixture

- **What it shows:** Verifies that the Telegram channel extracted from `shutter-network/keyper-concorde-agent` (`f5a5c17`) compiles and passes all its unit/integration tests against the tarball build of `shutter-network/concorde` (`03dda6a`) and PostgreSQL 17.
- **Command:**
  ```bash
  ./checks/harness/capture.sh upstream-channel ./checks/upstream-channel/run.sh
  ```
- **Faithful Excerpt:**
  ```text
  channel-tests-1  | ℹ tests 21
  channel-tests-1  | ℹ suites 6
  channel-tests-1  | ℹ pass 21
  channel-tests-1  | ℹ fail 0
  channel-tests-1  | ℹ cancelled 0
  channel-tests-1  | ℹ skipped 0
  channel-tests-1  | ℹ todo 0
  channel-tests-1  | ℹ duration_ms 6027.174716
  channel-tests-1 exited with code 0
  ```
- **Verdict:** **PASS** (All 21 tests passed across 6 test suites; exit code 0).
- **Log Link:** [`results/fixture/upstream-channel/output.log`](results/fixture/upstream-channel/output.log)

---

### 2. Baseline Deployment (`baseline`) — Fixture

- **What it shows:** Proves the basic service wiring, database migrations, signal workers, and unknown chat filtering before introducing the model relay. An unconfigured agent run fails cleanly and delivers the canned failure notice to Telegram.
- **Command:**
  ```bash
  ./checks/harness/capture.sh baseline ./checks/baseline/run.sh
  ```
- **Faithful Excerpt:**
  ```text
  Database verification:
  Inbound messages: 1, Outbound messages: 1, Runs: 1 (Failed: 1)
  [PASS] S2.2 Seeded message run and failure notice - Message produced Run, Run failed as intended, failure notice recorded
  Injecting update from unknown chat 888777666...
  {"ok":true,"update_id":20002}
  Waiting for response to unknown chat...
  {
    "ok": true,
    "sent": [
      {
        "messageId": 1,
        "chatId": "100000001",
        "text": "I am unable to process your request at this time. Please try again later.",
        "recordedAt": "2026-10-08T00:31:00.060Z"
      },
      {
        "messageId": 2,
        "chatId": "888777666",
        "text": "This chat is not registered with the agent. Its id is 888777666.",
        "recordedAt": "2026-10-08T00:31:01.956Z"
      }
    ]
  }
  [PASS] S2.3 Unknown chat rejection - Answered with chat id and stored nothing in message log
  Checking agent container environment...
  [PASS] S2.4 Agent environment secret isolation - Agent environment contains no Telegram token and no database URL
  Checking for Docker socket mounts across all containers...
  [PASS] S2.5 Docker socket confinement - No container mounts the Docker socket
  === All baseline checks passed successfully ===
  ```
- **Verdict:** **PASS** (All 5 baseline conditions met; exit code 0).
- **Log Link:** [`results/fixture/baseline/output.log`](results/fixture/baseline/output.log)

---

### 3. Model Relay (`relay`) — Fixture

- **What it shows:** Verifies that the Nginx model relay injects the upstream API key, replaces placeholder headers, delivers Server-Sent Event (SSE) completion deltas unbuffered, performs tool-call round trips, rejects unapproved paths/methods, and triggers a prompt failure notice if the relay stops.
- **Command:**
  ```bash
  ./checks/harness/capture.sh relay ./checks/relay/run.sh
  ```
- **Faithful Excerpt:**
  ```text
  [PASS] S3.6 Relay credential replacement - Relay substituted real key; agent placeholder never reached upstream
  [PASS] S3.7 Tool result in follow-up request - Stand-in received tool result in follow-up request
  Testing unreachable model behavior (stopping relay)...
   Container concorde-s3-relay-relay-1 Stopping 
   Container concorde-s3-relay-relay-1 Stopped 
  Injecting Telegram update while relay is stopped...
  {"ok":true,"update_id":30002}
  Waiting for failure notice to be delivered...
  Sent messages during relay outage:
  {
    "ok": true,
    "sent": [
      {
        "messageId": 1,
        "chatId": "100000001",
        "text": "I am unable to process your request at this time. Please try again later.",
        "recordedAt": "2026-10-08T00:32:15.110Z"
      }
    ]
  }
  [PASS] S3.8 Unreachable model failure handling - Run failed promptly with failure notice; zero requests reached upstream
  === All relay checks (s3) passed successfully ===
  ```
- **Verdict:** **PASS** (All 8 conditions verified; exit code 0).
- **Log Link:** [`results/fixture/relay/output.log`](results/fixture/relay/output.log)

---

### 4. End-to-End Status Workflow (`workflow`) — Fixture

- **What it shows:** Proves the full end-to-end hermetic flow under isolated gateway network settings: Telegram message → Concorde gateway → agent RPC prompt → model relay completion → metrics gate panel query → Agent API reply → Telegram outbox transmission.
- **Command:**
  ```bash
  ./checks/harness/capture.sh workflow ./checks/workflow/run.sh
  ```
- **Faithful Excerpt:**
  ```text
  [PASS] S4.1 Network isolation settings - agent network is internal and uses isolated gateway mode
  [PASS] S4.2 Inbound message to agent prompt - Telegram message was received and dispatched to agent
  [PASS] S4.3 Permitted Grafana panel queries - Agent queried permitted panel routes via metrics-gate
  [PASS] S4.4 Agent outbound message posting - Agent posted status response via Concorde Agent API
  [PASS] S4.5 Outbound message delivery - Status response was delivered to Telegram outbox
  [PASS] S4.6 Relay credential substitution in workflow - Every model request arrived with substituted relay key; placeholder never leaked
  === All workflow checks (s4) passed successfully ===
  ```
- **Verdict:** **PASS** (All 6 workflow milestones verified; exit code 0).
- **Log Link:** [`results/fixture/workflow/output.log`](results/fixture/workflow/output.log)

---

### 5. Security Conditions (S1–S5) (`security`) — Fixture

- **What it shows:** Evaluates the five security conditions from inside the caged agent container with paired negative and positive controls.
- **Command:**
  ```bash
  ./checks/harness/capture.sh security ./checks/security/run.sh
  ```
- **Faithful Excerpt:**
  ```text
  [PASS] S1 Key absence from agent - Model upstream key is absent from agent env and filesystem; injected key detected by control
  [PASS] S2 Prohibited destination unreachable - External IPs and domains unreachable from agent; canary hits: 0; canary hit verified by weakened control
  [PASS] S3 Excluded internal services unreachable - PostgreSQL, doubles, gateway public, and Docker host unreachable from agent; all paired controls succeeded
  [PASS] S4 Unapproved relay routes rejected - Unapproved methods and routes rejected (404/405/400); absolute targets and forged Host rewrite verified; canary hits: 0
  [PASS] S5 Relay stopped failure - Stopping relay causes bounded failure notification; 0 upstream requests; stack recovers on restart
  ==========================================================
  All five security conditions (S1–S5) passed successfully!
  ==========================================================
  ```
- **Controls Breakdown:**
  - **S1 (Key Absence):** Upstream model key `dummy-upstream-key-0000`, Telegram token `123456789:dummy-token-for-testing-0000`, and database password `dummy-pg-password-0000` absent from environment variables, process `/proc/*/environ`, `/workspace`, `/home/agent/.pi`, `/sessions`, `/tmp`. Paired control: synthetic key injected into filesystem detected; weakened deployment with key in environment detected.
  - **S2 (Prohibited Destination):** Agent curl probes to public IP (`1.1.1.1`), external domain (`example.com`), and canary (`canary:8080`) failed with exit code 6 or 7. Canary connection log: 0 hits. Paired control: relay successfully hits canary; weakened deployment attaching agent to egress hits canary and records 1 connection.
  - **S3 (Excluded Internal Services & Docker Host):** Agent probes to `postgres:5432`, `model-upstream:8080`, `metrics-fixture:8080`, `bot-api:8080`, gateway public `127.0.0.1:8081`, and host listener (`0.0.0.0:39485` on all candidate IPs) failed. Host listener recorded 0 hits. Paired control: host listener reached from container on plain internal network (`HIT 172.22.0.2`); PostgreSQL reachable from gateway; model-upstream reachable from relay; bot-api reachable from gateway.
  - **S4 (Unapproved Relay Routes Rejected):** GET/PUT/DELETE on `/v1/chat/completions` returned HTTP 405. POST to unapproved routes (`/v1/models`, `/v1/embeddings`, `/`, `/random/path`, trailing slashes, traversals, case variants) returned HTTP 404. Absolute-URI targets and forged `Host` headers had authority stripped and were proxied only to fixed upstream; canary recorded 0 hits. Unapproved metrics-gate queries returned HTTP 404/405.
  - **S5 (Relay Stopped Failure):** Stopping relay container delivered failure message to Telegram in 36 seconds (bound 45 seconds). Zero requests reached model upstream. Restarting relay restored normal status query execution.
- **Verdict:** **PASS** (All 5 conditions and paired controls satisfied; exit code 0).
- **Log Link:** [`results/fixture/security/output.log`](results/fixture/security/output.log)

---

### 6. Live Operational Run (`live`) — Live

- **What it shows:** An end-to-end status query executed against real external infrastructure: 0G Labs AI (`0GM-1.0-35B-A3B`) via the locked `relay`, live Shutter metrics (`grafana.metrics.shutter.network`) via `metrics-gate`, and Telegram Bot API (`@stevenhertbot`).
- **Command:**
  ```bash
  docker compose --env-file pins.env --env-file .env -f compose.yml up -d
  ```
- **Faithful Excerpt:**
  ```text
  --- Gateway Signal & Channel Logs ---
  gateway-1  | {"level":30,"time":1791419257367,"pid":1,"hostname":"af3b4a378394","update":593497116,"userId":"771f3712-72e2-42c0-b5b6-835454b6219e","msg":"a Telegram message became a Message"}
  gateway-1  | {"level":30,"time":1791419257372,"pid":1,"hostname":"af3b4a378394","signalId":"50d66340-d2fa-4a59-a7fe-423b02518028","kind":"message.received","msg":"Signal claimed"}
  gateway-1  | {"level":30,"time":1791419257377,"pid":1,"hostname":"af3b4a378394","runId":"f08174f3-1de0-46a1-a374-e5218210987c","signalId":"50d66340-d2fa-4a59-a7fe-423b02518028","session":"user_771f3712-72e2-42c0-b5b6-835454b6219e","msg":"Run started"}
  gateway-1  | {"level":30,"time":1791419279616,"pid":1,"hostname":"af3b4a378394","message":"8aedc89d-7e21-424a-a34d-f372c597a6a4","userId":"771f3712-72e2-42c0-b5b6-835454b6219e","msg":"a Message reached Telegram"}
  gateway-1  | {"level":30,"time":1791419281743,"pid":1,"hostname":"af3b4a378394","runId":"f08174f3-1de0-46a1-a374-e5218210987c","signalId":"50d66340-d2fa-4a59-a7fe-423b02518028","session":"user_771f3712-72e2-42c0-b5b6-835454b6219e","msg":"Run finished"}
  gateway-1  | {"level":30,"time":1791419281747,"pid":1,"hostname":"af3b4a378394","signalId":"50d66340-d2fa-4a59-a7fe-423b02518028","kind":"message.received","state":"done","msg":"Signal finished"}

  --- Metrics Gate Logs ---
  metrics-gate-1  | 172.20.0.1 - - [08/Oct/2026:00:27:40 +0000] "POST /api/public/dashboards/2b52906b091a445989638922fbe69e5e/panels/5/query HTTP/1.1" 200 22426 "-" "curl/8.22.0" "-"

  --- Messenger Database Inbound & Outbound Records ---
  id          : 57074797-9429-492f-b58a-14d543c6540f
  direction   : inbound
  text        : How many keypers are online now?
  created_at  : 2026-10-08 00:27:37.362445+00

  id          : 8aedc89d-7e21-424a-a34d-f372c597a6a4
  direction   : outbound
  text        : There are **30 out of 39 keypers** currently online.

                **Breakdown by network:**
                - Mainnet: 20 online, 9 offline
                - Chiado: 10 online, 0 offline

                **9 offline keypers:**
                - kpr-gnosh-initial-keyper-01 (mainnet)
                - kpr-shutter_api_gnosis_1002_keyper_1 through _5 (mainnet, 5 keypers)
                - set1-keyper1, set1-keyper2, set1-keyper3 (mainnet)

                All Chiado keypers are online. The mainnet 1002 keyper set (first generation) and set1 are currently offline.
  created_at  : 2026-10-08 00:27:59.277999+00
  ```
- **Verdict:** **PASS** (Live message parsed; real metrics returned 200; formatted answer transmitted to Telegram chat; zero secrets leaked).
- **Log Link:** [`results/live/output.log`](results/live/output.log)

---

## Synthetic Inputs, Assumptions, and Untested Items

### 1. Synthetic Inputs

- **Synthetic Credentials (`fixtures.env`):**
  - Upstream Key: `dummy-upstream-key-0000`
  - Telegram Bot Token: `123456789:dummy-token-for-testing-0000`
  - Database Password: `dummy-pg-password-0000`
  - Agent Client Placeholder Key: `dummy-agent-placeholder-key`
- **Scripted Model Responses (`doubles/model-upstream/`):**
  - Scripted responses in `script.ts` inspect the incoming conversation messages and return predetermined tool calls (`bash` running `curl` against `metrics-gate`, then `curl` posting to `$AGENT_SERVER_URL/messages/`), or canned plain text. They do not invoke an LLM during fixture tests.
- **Recorded Grafana Metrics Fixtures (`doubles/metrics-fixture/panels/`):**
  - Captured on **2026-10-07** via HTTP POST against `https://grafana.metrics.shutter.network/api/public/dashboards/2b52906b091a445989638922fbe69e5e/panels/<id>/query`:
    - Panel 1: Seven-day uptime for API set (16,029 bytes).
    - Panel 2: Seven-day uptime for Gnosis set (4,653 bytes).
    - Panel 5: Keypers online now (22,390 bytes).
    - Panel 6: Sync status across keypers (22,822 bytes).
    - Panel 7: Running software version information (25,822 bytes).
    - Panel 9: Last seen timestamps (17,191 bytes).
- **Injected Telegram Updates (`doubles/bot-api/`):**
  - Synthetically queued via `checks/harness/telegram.sh` into `doubles/bot-api/cli.ts` with incrementing synthetic `update_id` and chat ID `100000001`.

### 2. Supported Network Assumptions

- **Host Platform:** Native Linux kernel with Docker Engine supporting Linux bridge networks and `com.docker.network.bridge.gateway_mode_ipv4=isolated` (Docker Engine >= 28.0.0; tested on 29.8.0).
- **Bridge Gateway Addressing:** The host bridge interface (`br-...`) receives no IPv4 address on isolated networks, rendering host-bound listeners (`0.0.0.0`) unreachable from caged containers.
- **Single Egress Interface:** The outward-facing `egress` bridge network carries external traffic for gateway, relay, and metrics-gate in live mode, or is marked `internal: true` carrying hermetic doubles in fixture mode.
- **DNS Resolution:** Docker embedded DNS (`127.0.0.11`) answers internal container service names within the shared network namespace; external queries on internal networks return `SERVFAIL`.

### 3. Untested Items

To maintain strict fidelity regarding what was validated:

- **Alternative Container Engines:** Rootless Docker, Docker Desktop (macOS/Windows), Podman, Containerd, Kubernetes, and Colima are untested.
- **IPv6 Networking:** Global IPv6 reachability, IPv6 isolated bridge driver options, and dual-stack firewalls are untested.
- **Prompt Injection Defense:** Prompt hardening and input sanitization were not tested; this deployment bounds the agent's reachability and secrets exposure rather than preventing prompt hijacking.
- **Model API Profiles Other than OpenAI Chat Completions:** Anthropic Messages API, Google Gemini Native API, and raw completions APIs are untested.
- **Multi-Tenant / Group Routing:** Multi-user chats, Telegram group topics, and multi-keyper onboarding flows are out of scope and untested.
- **High-Concurrency Rate Limiting:** The relay and metrics gate enforce route and method filtering, not token bucket rate limits or burst quotas.
- **Request Body Inspection:** Neither relay nor metrics-gate parses or validates request payloads (e.g. model name or SQL/GraphQL payloads).
- **Database Failover & High Availability:** PostgreSQL runs as a single container instance; replication, failover, and point-in-time recovery are untested.
