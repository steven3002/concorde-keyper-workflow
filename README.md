# Concorde Keyper Workflow

A credential-isolated reference deployment for a Shutter Keyper status monitoring agent built on the Concorde framework.

## Overview

This repository demonstrates a secure architecture for deploying an automated Keyper status agent with strict isolation:
- **Credential Separation**: The upstream model API key is held exclusively by the `relay` reverse proxy and never enters the `agent` container, filesystem, or process environment.
- **Strict Network Confinement**: The `agent` container resides solely on an internal bridge network configured with isolated gateway mode (`com.docker.network.bridge.gateway_mode_ipv4: isolated`), preventing any direct outbound internet access and blocking reachability to the Docker host.
- **Allowlisted Metrics Egress**: Metrics access is restricted via a dedicated `metrics-gate` proxy that forwards only permitted public Grafana dashboard panel queries and rejects all other methods, paths, and destinations.
- **Deterministic Automated Testing**: Automated test suites run against hermetic doubles (`model-upstream`, `bot-api`, `metrics-fixture`) with zero external internet dependencies and zero real credentials.

---

## Operating Modes

This deployment supports two strictly separated modes: **Fixture Mode** and **Live Mode**. The underlying Compose topology (`compose.yml`) remains identical between both modes.

### 1. Fixture Mode (Hermetic Automated Testing)

In Fixture Mode:
- No real credentials are used; all secrets are recognisable synthetic dummy values defined in `fixtures.env`.
- The `compose.fixtures.yml` overlay activates three test doubles on the `egress` network:
  - `model-upstream`: Scripted OpenAI-compatible Chat Completions endpoint.
  - `bot-api`: Telegram Bot API stand-in capturing sent messages and updates.
  - `metrics-fixture`: Static server returning recorded Grafana panel responses.
- The `egress` network is set to `internal: true`, guaranteeing that no traffic leaves the Docker environment.

To run tests in Fixture Mode:
```bash
# Execute end-to-end workflow verification (message -> metrics -> reply)
./checks/harness/capture.sh workflow ./checks/workflow/run.sh

# Execute relay credential substitution and streaming verification
./checks/harness/capture.sh relay ./checks/relay/run.sh
```

To run the fixture stack manually:
```bash
docker compose \
  --env-file pins.env \
  --env-file fixtures.env \
  -f compose.yml \
  -f compose.fixtures.yml \
  up -d
```

### 2. Live Mode (Production Operation)

In Live Mode:
- The deployment interacts with the real Telegram Bot API (`https://api.telegram.org`), the live Shutter metrics dashboard (`https://grafana.metrics.shutter.network`), and an external OpenAI-compatible model provider.
- `compose.yml` runs standalone without the fixtures overlay (`compose.fixtures.yml`).
- Secrets and operational configurations are loaded from an untracked `.env` file.

#### Switching to Live Mode

1. **Configure Environment Variables**:
   Copy `.env.example` to `.env` and fill in real values:
   ```bash
   cp .env.example .env
   ```
   Required variables:
   - `MODEL_UPSTREAM_ORIGIN`: Base URL of your provider (e.g. `https://api.openai.com`).
   - `MODEL_UPSTREAM_KEY`: Provider API key (held solely by the `relay` container).
   - `TELEGRAM_BOT_TOKEN`: Secret Telegram bot token issued by BotFather.
   - `TELEGRAM_CHAT_ID`: Authorized Telegram chat ID of the operator.
   - `TELEGRAM_API_BASE`: `https://api.telegram.org`
   - `METRICS_UPSTREAM_ORIGIN`: `https://grafana.metrics.shutter.network`
   - `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`: PostgreSQL database credentials.

2. **Configure Model Identifiers**:
   Update `agent/models.json` and `agent/settings.json` with the target model ID (for example, `gpt-4o`):
   - In `agent/models.json`: set `providers.relay.models[0].id` to the provider model name.
   - In `agent/settings.json`: set `defaultModel` to match the model ID.

3. **Start the Deployment**:
   ```bash
   docker compose \
     --env-file pins.env \
     --env-file .env \
     -f compose.yml \
     up -d
   ```

4. **Verify Health**:
   ```bash
   docker compose --env-file pins.env --env-file .env -f compose.yml ps
   ```

---

## Directory Layout

- `agent/`: Dockerfile and configuration (`models.json`, `settings.json`, `AGENTS.md`) for the RPC agent runner.
- `gateway/`: Concorde gateway service sources, database migrations, and Telegram channel integration.
- `relay/`: Nginx template for the credential-injecting model reverse proxy.
- `metrics-gate/`: Nginx template for the allowlisting metrics gate proxy.
- `doubles/`: Self-contained TypeScript doubles for testing (`model-upstream`, `bot-api`, `metrics-fixture`).
- `checks/`: Verification scripts and test runners.
- `results/`: Test execution logs captured by automated runs.
- `pins.env`: Pinned upstream Git commits, package versions, and container image references.
- `fixtures.env`: Synthetic environment values for test fixtures.
- `.env.example`: Template for live deployment environment variables.
