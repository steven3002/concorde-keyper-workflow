#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
HARNESS="$REPO_ROOT/checks/harness"
FIXTURES_FILE="$REPO_ROOT/fixtures.env"
PROBES_DIR="$REPO_ROOT/checks/security/probes"

PROJECT_NAME="${CONCORDE_PROJECT_NAME:-concorde-security-check}"
export CONCORDE_PROJECT_NAME="$PROJECT_NAME"

compose_cli() {
  docker compose \
    --env-file "$REPO_ROOT/pins.env" \
    --env-file "$FIXTURES_FILE" \
    -f "$REPO_ROOT/compose.yml" \
    -f "$REPO_ROOT/compose.fixtures.yml" \
    -p "$PROJECT_NAME" \
    "$@"
}

echo "=== Running Condition S4: Unapproved relay routes and methods rejected ==="

# 1. Clear state in doubles before running probes
compose_cli exec -T canary node doubles/canary/cli.ts clear >/dev/null
compose_cli exec -T model-upstream node doubles/model-upstream/cli.ts clear >/dev/null
compose_cli exec -T metrics-fixture node doubles/metrics-fixture/cli.ts clear >/dev/null

# 2. Pipe route probes into agent container
echo "Running route rejection and canary-naming probes from agent container..."
if docker exec -i "${PROJECT_NAME}-agent-1" sh -s -- "http://relay:8080" "http://metrics-gate:8080" "canary" < "$PROBES_DIR/probe-relay-routes.sh"; then
  echo "All in-container route probes completed successfully."
else
  echo "ERROR: One or more route probes failed!" >&2
  "$HARNESS/verdict.sh" "S4 Unapproved relay routes rejected" "FAIL" "Route probe failure"
  exit 1
fi

# 3. Assert canary recorded ZERO hits despite forged Host, absolute URI targets, and forwarding headers
canary_hits="$(compose_cli exec -T canary node doubles/canary/cli.ts hits)"
hit_count="$(echo "$canary_hits" | grep -c '"remoteAddress"' || true)"
echo "Canary hit count after route probes: $hit_count"

if [ "$hit_count" -ne 0 ]; then
  echo "ERROR: Canary recorded $hit_count connections during S4 probes!" >&2
  echo "$canary_hits" >&2
  "$HARNESS/verdict.sh" "S4 Unapproved relay routes rejected" "FAIL" "Relay forwarded request to destination named in request"
  exit 1
fi
echo "Confirmed (M-08): Canary recorded zero hits. Neither relay nor gate forwarded to client-specified destination."

# 4. Assert model-upstream received only permitted route requests with rewritten Host header
model_reqs="$(compose_cli exec -T model-upstream node doubles/model-upstream/cli.ts requests)"
if echo "$model_reqs" | grep '"url":' | grep -v '"/v1/chat/completions"' | grep -q .; then
  echo "ERROR: Model upstream received unapproved URL path!" >&2
  "$HARNESS/verdict.sh" "S4 Unapproved relay routes rejected" "FAIL" "Unapproved path forwarded to model upstream"
  exit 1
fi

if echo "$model_reqs" | grep -F '"host": "canary' >/dev/null; then
  echo "ERROR: Forged Host header leaked through to model upstream!" >&2
  "$HARNESS/verdict.sh" "S4 Unapproved relay routes rejected" "FAIL" "Client Host header leaked to upstream"
  exit 1
fi
echo "Confirmed: All requests forwarded to model upstream used strictly approved path and rewritten Host header."

# 5. Assert metrics-fixture received only permitted panel queries
metrics_routes="$(compose_cli exec -T metrics-fixture node doubles/metrics-fixture/cli.ts routes)"
if echo "$metrics_routes" | grep '"panelId": "[^125679]"' >/dev/null; then
  echo "ERROR: Unapproved panel ID reached metrics fixture!" >&2
  "$HARNESS/verdict.sh" "S4 Unapproved relay routes rejected" "FAIL" "Unapproved panel ID reached fixture"
  exit 1
fi
echo "Confirmed: Only permitted panel queries reached metrics fixture."

"$HARNESS/verdict.sh" "S4 Unapproved relay routes rejected" "PASS" "Unapproved methods and routes rejected (404/405/400); absolute targets and forged Host rewrite verified; canary hits: 0"
exit 0
