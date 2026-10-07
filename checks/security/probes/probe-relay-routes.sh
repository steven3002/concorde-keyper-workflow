#!/bin/sh
set -eu

# Probe to verify rejection of unapproved routes and methods on relay and metrics-gate
# Usage: probe-relay-routes.sh [relay_url] [metrics_gate_url] [canary_host]

RELAY_URL="${1:-http://relay:8080}"
METRICS_GATE_URL="${2:-http://metrics-gate:8080}"
CANARY_HOST="${3:-canary}"

DASH_UID="2b52906b091a445989638922fbe69e5e"

errors=0

assert_status() {
  component="$1"
  label="$2"
  expected_status="$3"
  cmd_eval="$4"

  actual_status="$(eval "$cmd_eval" 2>/dev/null || echo "ERR")"
  echo "[$component] $label -> HTTP $actual_status (expected $expected_status)"

  if [ "$actual_status" != "$expected_status" ]; then
    echo "ERROR: [$component] $label failed! Expected HTTP $expected_status, got $actual_status" >&2
    errors=$((errors + 1))
  fi
}

echo "=== Testing Model Relay route and method controls ==="

# 1. Permitted route with unapproved methods (405)
assert_status "Relay" "GET on permitted /v1/chat/completions" "405" \
  "curl -s -o /dev/null -w '%{http_code}' -X GET '${RELAY_URL}/v1/chat/completions' --max-time 3"

assert_status "Relay" "PUT on permitted /v1/chat/completions" "405" \
  "curl -s -o /dev/null -w '%{http_code}' -X PUT '${RELAY_URL}/v1/chat/completions' --max-time 3"

assert_status "Relay" "DELETE on permitted /v1/chat/completions" "405" \
  "curl -s -o /dev/null -w '%{http_code}' -X DELETE '${RELAY_URL}/v1/chat/completions' --max-time 3"

# 2. Unapproved paths (404)
assert_status "Relay" "POST /v1/models" "404" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST '${RELAY_URL}/v1/models' -H 'Content-Type: application/json' -d '{}' --max-time 3"

assert_status "Relay" "GET /v1/models" "404" \
  "curl -s -o /dev/null -w '%{http_code}' -X GET '${RELAY_URL}/v1/models' --max-time 3"

assert_status "Relay" "POST /v1/embeddings" "404" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST '${RELAY_URL}/v1/embeddings' -H 'Content-Type: application/json' -d '{}' --max-time 3"

assert_status "Relay" "POST root /" "404" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST '${RELAY_URL}/' --max-time 3"

assert_status "Relay" "POST /random/path" "404" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST '${RELAY_URL}/random/path' --max-time 3"

# 3. Path variants
assert_status "Relay" "Trailing slash /v1/chat/completions/" "404" \
  "curl --path-as-is -s -o /dev/null -w '%{http_code}' -X POST '${RELAY_URL}/v1/chat/completions/' -H 'Content-Type: application/json' -d '{}' --max-time 3"

assert_status "Relay" "Traversal /v1/chat/completions/.." "404" \
  "curl --path-as-is -s -o /dev/null -w '%{http_code}' -X POST '${RELAY_URL}/v1/chat/completions/..' -H 'Content-Type: application/json' -d '{}' --max-time 3"

assert_status "Relay" "Different case /V1/chat/completions" "404" \
  "curl --path-as-is -s -o /dev/null -w '%{http_code}' -X POST '${RELAY_URL}/V1/chat/completions' -H 'Content-Type: application/json' -d '{}' --max-time 3"

assert_status "Relay" "Doubled slashes //v1/chat/completions (normalized)" "200" \
  "curl --path-as-is -s -o /dev/null -w '%{http_code}' -X POST '${RELAY_URL}//v1/chat/completions' -H 'Content-Type: application/json' -d '{}' --max-time 3"

assert_status "Relay" "Encoded character /v1/%63hat/completions (normalized)" "200" \
  "curl --path-as-is -s -o /dev/null -w '%{http_code}' -X POST '${RELAY_URL}/v1/%63hat/completions' -H 'Content-Type: application/json' -d '{}' --max-time 3"

# 4. Absolute URI request targets naming canary
assert_status "Relay" "Absolute URI target permitted path naming canary" "200" \
  "curl --request-target 'http://${CANARY_HOST}:8080/v1/chat/completions' -s -o /dev/null -w '%{http_code}' -X POST '${RELAY_URL}' -H 'Content-Type: application/json' -d '{}' --max-time 3"

assert_status "Relay" "Absolute URI target unapproved path naming canary" "404" \
  "curl --request-target 'http://${CANARY_HOST}:8080/v1/models' -s -o /dev/null -w '%{http_code}' -X POST '${RELAY_URL}' -H 'Content-Type: application/json' -d '{}' --max-time 3"

# 5. Forged Host header naming canary
assert_status "Relay" "Forged Host header naming canary" "200" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST '${RELAY_URL}/v1/chat/completions' -H 'Host: ${CANARY_HOST}:8080' -H 'Content-Type: application/json' -d '{}' --max-time 3"

# 6. Forwarding headers naming canary
assert_status "Relay" "Forwarding headers naming canary" "200" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST '${RELAY_URL}/v1/chat/completions' -H 'X-Forwarded-Host: ${CANARY_HOST}' -H 'Forwarded: host=${CANARY_HOST}' -H 'Content-Type: application/json' -d '{}' --max-time 3"

# 7. CONNECT method
assert_status "Relay" "CONNECT method" "400" \
  "curl -s -o /dev/null -w '%{http_code}' -X CONNECT '${RELAY_URL}/v1/chat/completions' --max-time 3"


echo "=== Testing Metrics Gate route and method controls ==="

# 1. Permitted panel with other methods
assert_status "Gate" "GET on permitted panel 5" "405" \
  "curl -s -o /dev/null -w '%{http_code}' -X GET '${METRICS_GATE_URL}/api/public/dashboards/${DASH_UID}/panels/5/query' --max-time 3"

assert_status "Gate" "PUT on permitted panel 5" "405" \
  "curl -s -o /dev/null -w '%{http_code}' -X PUT '${METRICS_GATE_URL}/api/public/dashboards/${DASH_UID}/panels/5/query' --max-time 3"

# 2. Unlisted panel numbers
assert_status "Gate" "POST unlisted panel 3" "404" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST '${METRICS_GATE_URL}/api/public/dashboards/${DASH_UID}/panels/3/query' -H 'Content-Type: application/json' -d '{}' --max-time 3"

assert_status "Gate" "POST unlisted panel 4" "404" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST '${METRICS_GATE_URL}/api/public/dashboards/${DASH_UID}/panels/4/query' -H 'Content-Type: application/json' -d '{}' --max-time 3"

assert_status "Gate" "POST unlisted panel 8" "404" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST '${METRICS_GATE_URL}/api/public/dashboards/${DASH_UID}/panels/8/query' -H 'Content-Type: application/json' -d '{}' --max-time 3"

# 3. Unlisted dashboard id
assert_status "Gate" "POST unlisted dashboard id" "404" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST '${METRICS_GATE_URL}/api/public/dashboards/11111111111111111111111111111111/panels/5/query' -H 'Content-Type: application/json' -d '{}' --max-time 3"

# 4. Path variants
assert_status "Gate" "Trailing slash .../query/" "404" \
  "curl --path-as-is -s -o /dev/null -w '%{http_code}' -X POST '${METRICS_GATE_URL}/api/public/dashboards/${DASH_UID}/panels/5/query/' -H 'Content-Type: application/json' -d '{}' --max-time 3"

assert_status "Gate" "Different case .../Query" "404" \
  "curl --path-as-is -s -o /dev/null -w '%{http_code}' -X POST '${METRICS_GATE_URL}/api/public/dashboards/${DASH_UID}/panels/5/Query' -H 'Content-Type: application/json' -d '{}' --max-time 3"

assert_status "Gate" "Traversal .../query/.." "404" \
  "curl --path-as-is -s -o /dev/null -w '%{http_code}' -X POST '${METRICS_GATE_URL}/api/public/dashboards/${DASH_UID}/panels/5/query/..' -H 'Content-Type: application/json' -d '{}' --max-time 3"

# 5. Absolute URI target naming canary
assert_status "Gate" "Absolute URI target permitted panel naming canary" "200" \
  "curl --request-target 'http://${CANARY_HOST}:8080/api/public/dashboards/${DASH_UID}/panels/5/query' -s -o /dev/null -w '%{http_code}' -X POST '${METRICS_GATE_URL}' -H 'Content-Type: application/json' -d '{}' --max-time 3"

assert_status "Gate" "Absolute URI target unlisted panel naming canary" "404" \
  "curl --request-target 'http://${CANARY_HOST}:8080/api/public/dashboards/${DASH_UID}/panels/4/query' -s -o /dev/null -w '%{http_code}' -X POST '${METRICS_GATE_URL}' -H 'Content-Type: application/json' -d '{}' --max-time 3"

# 6. Forged Host header naming canary
assert_status "Gate" "Forged Host header naming canary" "200" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST '${METRICS_GATE_URL}/api/public/dashboards/${DASH_UID}/panels/5/query' -H 'Host: ${CANARY_HOST}:8080' -H 'Content-Type: application/json' -d '{}' --max-time 3"

# 7. CONNECT method
assert_status "Gate" "CONNECT method" "400" \
  "curl -s -o /dev/null -w '%{http_code}' -X CONNECT '${METRICS_GATE_URL}/api/public/dashboards/${DASH_UID}/panels/5/query' --max-time 3"

# 8. Controls: permitted route succeeds
echo "=== Testing Controls (permitted routes succeed) ==="
assert_status "Relay Control" "Permitted POST /v1/chat/completions" "200" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST '${RELAY_URL}/v1/chat/completions' -H 'Content-Type: application/json' -d '{}' --max-time 3"

assert_status "Gate Control" "Permitted POST panel 5 query" "200" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST '${METRICS_GATE_URL}/api/public/dashboards/${DASH_UID}/panels/5/query' -H 'Content-Type: application/json' -d '{}' --max-time 3"

if [ "$errors" -eq 0 ]; then
  echo "PASSED: All relay and metrics-gate route controls behaved as expected"
  exit 0
else
  echo "FAILED: $errors route checks failed" >&2
  exit 1
fi
