#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
HARNESS="$REPO_ROOT/checks/harness"
FIXTURES_FILE="$REPO_ROOT/fixtures.env"

PROJECT_NAME="concorde-s4-workflow"
export CONCORDE_PROJECT_NAME="$PROJECT_NAME"

cleanup() {
  echo "Tearing down workflow test stack..."
  "$HARNESS/stack.sh" stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== Starting end-to-end workflow check (s4) ==="

SEEDED_CHAT_ID="$(grep -E '^TELEGRAM_CHAT_ID=' "$FIXTURES_FILE" | cut -d'=' -f2 | tr -d ' "')"
RELAY_KEY="$(grep -E '^MODEL_UPSTREAM_KEY=' "$FIXTURES_FILE" | cut -d'=' -f2 | tr -d ' "')"

# 1. Clean stack start
echo "Resetting and starting stack..."
"$HARNESS/stack.sh" reset >/dev/null 2>&1 || true
"$HARNESS/stack.sh" start

"$HARNESS/verdict.sh" "S4.1 Stack startup and service health" "PASS" "All six services and doubles started cleanly"

# 2. Verify network construction and isolation
echo "Verifying network configurations..."
agent_net_inspect="$(docker network inspect concorde_agent)"
egress_net_inspect="$(docker network inspect concorde_egress)"

agent_internal="$(echo "$agent_net_inspect" | grep -o '"Internal": true' || true)"
agent_isolated="$(echo "$agent_net_inspect" | grep -o '"com.docker.network.bridge.gateway_mode_ipv4": "isolated"' || true)"
egress_internal="$(echo "$egress_net_inspect" | grep -o '"Internal": true' || true)"

if [ -z "$agent_internal" ] || [ -z "$agent_isolated" ]; then
  echo "ERROR: concorde_agent network missing internal: true or gateway_mode_ipv4: isolated" >&2
  "$HARNESS/verdict.sh" "S4.2 Network isolation" "FAIL" "Agent network lacks required isolation driver options"
  exit 1
fi

if [ -z "$egress_internal" ]; then
  echo "ERROR: concorde_egress network in fixture mode is not internal" >&2
  "$HARNESS/verdict.sh" "S4.2 Network isolation" "FAIL" "Egress network in fixture mode has external route"
  exit 1
fi
"$HARNESS/verdict.sh" "S4.2 Network isolation" "PASS" "Agent network isolated and internal; egress network has no external route"

# 3. Test metrics gate rejection from inside agent container
echo "Testing metrics gate method and route rejection from agent container..."
docker exec -i "${PROJECT_NAME}-agent-1" sh -c '
  set -eu

  # GET on permitted panel 5 -> 405 Method Not Allowed
  status_get="$(curl -s -o /dev/null -w "%{http_code}" -X GET "$METRICS_GATE_URL/api/public/dashboards/2b52906b091a445989638922fbe69e5e/panels/5/query")"
  echo "GET on permitted panel 5 -> HTTP $status_get"
  if [ "$status_get" != "405" ]; then
    echo "ERROR: Expected HTTP 405 for GET on panel 5, got $status_get" >&2
    exit 1
  fi

  # POST on unlisted panel 3 -> 404 Not Found
  status_unlisted="$(curl -s -o /dev/null -w "%{http_code}" -X POST "$METRICS_GATE_URL/api/public/dashboards/2b52906b091a445989638922fbe69e5e/panels/3/query")"
  echo "POST on unlisted panel 3 -> HTTP $status_unlisted"
  if [ "$status_unlisted" != "404" ]; then
    echo "ERROR: Expected HTTP 404 for unlisted panel 3, got $status_unlisted" >&2
    exit 1
  fi

  # POST on random path -> 404 Not Found
  status_path="$(curl -s -o /dev/null -w "%{http_code}" -X POST "$METRICS_GATE_URL/random/metrics/path")"
  echo "POST on unlisted path -> HTTP $status_path"
  if [ "$status_path" != "404" ]; then
    echo "ERROR: Expected HTTP 404 for unlisted path, got $status_path" >&2
    exit 1
  fi

  echo "Metrics gate rejection verified from agent."
'
"$HARNESS/verdict.sh" "S4.3 Metrics gate rejection" "PASS" "Non-POST methods and unlisted panel routes rejected by gate"

# 4. Clear doubles state before workflow test
echo "Clearing doubles state..."
"$HARNESS/telegram.sh" clear >/dev/null

docker compose \
  --env-file "$REPO_ROOT/pins.env" \
  --env-file "$FIXTURES_FILE" \
  -f "$REPO_ROOT/compose.yml" \
  -f "$REPO_ROOT/compose.fixtures.yml" \
  -p "$PROJECT_NAME" \
  exec -T model-upstream node doubles/model-upstream/cli.ts clear >/dev/null

docker compose \
  --env-file "$REPO_ROOT/pins.env" \
  --env-file "$FIXTURES_FILE" \
  -f "$REPO_ROOT/compose.yml" \
  -f "$REPO_ROOT/compose.fixtures.yml" \
  -p "$PROJECT_NAME" \
  exec -T metrics-fixture node doubles/metrics-fixture/cli.ts clear >/dev/null

# 5. Inject Telegram update to trigger full workflow
echo "Injecting Telegram update from chat $SEEDED_CHAT_ID..."
"$HARNESS/telegram.sh" inject "$SEEDED_CHAT_ID" "Report current Keyper cluster status" 40001

echo "Waiting for workflow response to be delivered via Telegram (bound: 60s)..."
"$HARNESS/telegram.sh" wait_sent "$SEEDED_CHAT_ID" 60

sent_json="$("$HARNESS/telegram.sh" sent)"
echo "Sent messages recorded at bot-api double:"
echo "$sent_json"

# 6. Assert delivered message contains fixture values
if ! echo "$sent_json" | grep -F "30 of 39 keypers online" >/dev/null; then
  echo "ERROR: Sent reply does not contain fixture online count (30 of 39 keypers online)" >&2
  "$HARNESS/verdict.sh" "S4.4 Reply contains fixture metrics" "FAIL" "Fixture online count missing from Telegram message"
  exit 1
fi

if ! echo "$sent_json" | grep -F "kpr-dappnode-2-gnosis-keyper" >/dev/null; then
  echo "ERROR: Sent reply does not contain fixture instance name (kpr-dappnode-2-gnosis-keyper)" >&2
  "$HARNESS/verdict.sh" "S4.4 Reply contains fixture metrics" "FAIL" "Fixture instance identifier missing from Telegram message"
  exit 1
fi
"$HARNESS/verdict.sh" "S4.4 Reply contains fixture metrics" "PASS" "Telegram reply contained exact fixture metrics (node counts and instance identifier)"

# 7. Assert metrics fixture recorded routes
metrics_routes="$(docker compose \
  --env-file "$REPO_ROOT/pins.env" \
  --env-file "$FIXTURES_FILE" \
  -f "$REPO_ROOT/compose.yml" \
  -f "$REPO_ROOT/compose.fixtures.yml" \
  -p "$PROJECT_NAME" \
  exec -T metrics-fixture node doubles/metrics-fixture/cli.ts routes)"

echo "Recorded routes at metrics-fixture double:"
echo "$metrics_routes"

if ! echo "$metrics_routes" | grep -F "/api/public/dashboards/2b52906b091a445989638922fbe69e5e/panels/5/query" >/dev/null; then
  echo "ERROR: Expected permitted panel 5 query not found in metrics-fixture log" >&2
  "$HARNESS/verdict.sh" "S4.5 Metrics gate permitted forwarding" "FAIL" "Permitted panel query not forwarded to metrics fixture"
  exit 1
fi

if echo "$metrics_routes" | grep '"panelId": "[^5]"' >/dev/null; then
  echo "ERROR: Unpermitted panel ID observed at metrics-fixture!" >&2
  "$HARNESS/verdict.sh" "S4.5 Metrics gate permitted forwarding" "FAIL" "Unpermitted panel ID reached fixture"
  exit 1
fi
"$HARNESS/verdict.sh" "S4.5 Metrics gate permitted forwarding" "PASS" "Gate forwarded query to permitted panel 5; zero unpermitted queries reached upstream"

# 8. Assert model requests and credential isolation
upstream_requests="$(docker compose \
  --env-file "$REPO_ROOT/pins.env" \
  --env-file "$FIXTURES_FILE" \
  -f "$REPO_ROOT/compose.yml" \
  -f "$REPO_ROOT/compose.fixtures.yml" \
  -p "$PROJECT_NAME" \
  exec -T model-upstream node doubles/model-upstream/cli.ts requests)"

echo "Recorded requests at model-upstream double:"
echo "$upstream_requests"

if echo "$upstream_requests" | grep -F "dummy-agent-placeholder-key" >/dev/null; then
  echo "ERROR: Dummy placeholder key leaked to model upstream" >&2
  "$HARNESS/verdict.sh" "S4.6 Relay credential substitution in workflow" "FAIL" "Placeholder key observed at model upstream"
  exit 1
fi

if ! echo "$upstream_requests" | grep -F "Bearer $RELAY_KEY" >/dev/null; then
  echo "ERROR: Real model key missing from model upstream requests" >&2
  "$HARNESS/verdict.sh" "S4.6 Relay credential substitution in workflow" "FAIL" "Relay key not received by model upstream"
  exit 1
fi
"$HARNESS/verdict.sh" "S4.6 Relay credential substitution in workflow" "PASS" "Every model request arrived with substituted relay key; placeholder never leaked"

echo "=== All workflow checks (s4) passed successfully ==="
