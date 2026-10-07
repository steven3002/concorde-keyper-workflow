#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
HARNESS="$REPO_ROOT/checks/harness"
FIXTURES_FILE="$REPO_ROOT/fixtures.env"
PROBES_DIR="$REPO_ROOT/checks/security/probes"
WEAKENED_DIR="$REPO_ROOT/checks/security/weakened"

mkdir -p "$WEAKENED_DIR"

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

echo "=== Running Condition S2: Prohibited destinations are unreachable ==="

# Clear canary hits
compose_cli exec -T canary node doubles/canary/cli.ts clear >/dev/null

CANARY_IP="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${PROJECT_NAME}-canary-1" 2>/dev/null || echo "")"
if [ -z "$CANARY_IP" ]; then
  echo "WARNING: Could not determine canary IP address; using fallback 172.21.0.2"
  CANARY_IP="172.21.0.2"
fi
echo "Target canary IP on egress network: $CANARY_IP"

# 1. Main check: probe destinations from agent container
echo "Probing prohibited destinations from agent container..."
if docker exec -i "${PROJECT_NAME}-agent-1" sh -s -- "canary" "8080" "$CANARY_IP" "1.1.1.1" "example.com" < "$PROBES_DIR/probe-destinations.sh"; then
  echo "Confirmed: all destination probes failed as expected."
else
  echo "ERROR: One or more prohibited destinations were reachable from agent!" >&2
  "$HARNESS/verdict.sh" "S2 Prohibited destination unreachable" "FAIL" "Destination reachable from agent"
  exit 1
fi

# Assert canary recorded zero hits
canary_hits="$(compose_cli exec -T canary node doubles/canary/cli.ts hits)"
hit_count="$(echo "$canary_hits" | grep -c '"remoteAddress"' || true)"
echo "Canary hit count after agent probes: $hit_count"

if [ "$hit_count" -ne 0 ]; then
  echo "ERROR: Canary recorded $hit_count hits during agent isolation test!" >&2
  echo "$canary_hits" >&2
  "$HARNESS/verdict.sh" "S2 Prohibited destination unreachable" "FAIL" "Canary recorded hits from agent"
  exit 1
fi

# 2. Control 1: Relay container (on egress) reaches canary
echo "Testing Control 1: Verifying relay container can reach canary..."
relay_status="$(docker exec -i "${PROJECT_NAME}-relay-1" curl -s -o /dev/null -w "%{http_code}" http://canary:8080/ --max-time 3 || echo "ERR")"
echo "Relay -> Canary HTTP status: $relay_status"

if [ "$relay_status" != "200" ]; then
  echo "ERROR: Control 1 failed! Relay could not reach canary (status: $relay_status)" >&2
  "$HARNESS/verdict.sh" "S2 Control: Relay to canary" "FAIL" "Relay unable to reach canary on egress"
  exit 1
fi

canary_control_hits="$(compose_cli exec -T canary node doubles/canary/cli.ts hits)"
if ! echo "$canary_control_hits" | grep -q '"remoteAddress"'; then
  echo "ERROR: Control 1 failed! Canary did not record hit from relay" >&2
  "$HARNESS/verdict.sh" "S2 Control: Relay to canary" "FAIL" "Canary failed to record connection"
  exit 1
fi
echo "Control 1 verified: relay cleanly reached canary and connection was recorded."

# Clear canary hits before weakened test
compose_cli exec -T canary node doubles/canary/cli.ts clear >/dev/null

# 3. Control 2: Weakened deployment: attach agent to egress network
echo "Testing Control 2: Weakened deployment with agent attached to egress network..."
WEAKENED_OVERRIDE="$WEAKENED_DIR/weakened-s2.override.yml"
cat > "$WEAKENED_OVERRIDE" <<EOF
services:
  agent:
    networks:
      - egress
EOF

docker compose \
  --env-file "$REPO_ROOT/pins.env" \
  --env-file "$FIXTURES_FILE" \
  -f "$REPO_ROOT/compose.yml" \
  -f "$REPO_ROOT/compose.fixtures.yml" \
  -f "$WEAKENED_OVERRIDE" \
  -p "$PROJECT_NAME" \
  up -d agent >/dev/null

# On weakened deployment, probe MUST fail (canary becomes reachable)
control2_passed=0
if docker exec -i "${PROJECT_NAME}-agent-1" sh -s -- "canary" "8080" "$CANARY_IP" "1.1.1.1" "example.com" < "$PROBES_DIR/probe-destinations.sh" 2>/dev/null; then
  echo "ERROR: Weakened check unexpectedly passed! Agent should have reached canary" >&2
else
  echo "Weakened check failed as expected (canary became reachable from agent)."
  weakened_hits="$(compose_cli exec -T canary node doubles/canary/cli.ts hits)"
  if echo "$weakened_hits" | grep -q '"remoteAddress"'; then
    echo "Control 2 verified: canary successfully recorded hit from weakened agent."
    control2_passed=1
  else
    echo "ERROR: Canary did not record hit from weakened agent!" >&2
  fi
fi

# Restore hardened agent container
echo "Restoring hardened agent container..."
docker compose \
  --env-file "$REPO_ROOT/pins.env" \
  --env-file "$FIXTURES_FILE" \
  -f "$REPO_ROOT/compose.yml" \
  -f "$REPO_ROOT/compose.fixtures.yml" \
  -p "$PROJECT_NAME" \
  up -d agent >/dev/null

rm -f "$WEAKENED_OVERRIDE"
compose_cli exec -T canary node doubles/canary/cli.ts clear >/dev/null

if [ "$control2_passed" -ne 1 ]; then
  "$HARNESS/verdict.sh" "S2 Control: Weakened egress attachment" "FAIL" "Failed to demonstrate failure under weakened network"
  exit 1
fi

"$HARNESS/verdict.sh" "S2 Prohibited destination unreachable" "PASS" "Canary and external destinations unreachable; zero hits recorded; relay and weakened controls confirmed"
exit 0
