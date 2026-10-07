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

echo "=== Running Condition S1: Upstream key and credentials absent from agent ==="

MODEL_KEY="$(grep -E '^MODEL_UPSTREAM_KEY=' "$FIXTURES_FILE" | cut -d'=' -f2 | tr -d ' "')"
BOT_TOKEN="$(grep -E '^TELEGRAM_BOT_TOKEN=' "$FIXTURES_FILE" | cut -d'=' -f2 | tr -d ' "')"
DB_PASS="$(grep -E '^POSTGRES_PASSWORD=' "$FIXTURES_FILE" | cut -d'=' -f2 | tr -d ' "')"

# 1. Main check: probe agent container for all three dummy secrets
echo "Searching agent container environment, processes, and files for secrets..."
if docker exec -i "${PROJECT_NAME}-agent-1" sh -s -- "$MODEL_KEY" "$BOT_TOKEN" "$DB_PASS" < "$PROBES_DIR/probe-secrets.sh"; then
  echo "Confirmed: model key, bot token, and db password are absent from agent container."
else
  echo "ERROR: Secret search detected credentials in agent container!" >&2
  "$HARNESS/verdict.sh" "S1 The key is absent" "FAIL" "Credentials found in agent container"
  exit 1
fi

# 2. Control 1: In-container placement
echo "Testing Control 1: Injecting secret into readable file inside agent workspace..."
docker exec -i "${PROJECT_NAME}-agent-1" sh -c "echo 'secret_payload=$MODEL_KEY' > /workspace/control-canary.txt"

control1_passed=0
if docker exec -i "${PROJECT_NAME}-agent-1" sh -s -- "$MODEL_KEY" < "$PROBES_DIR/probe-secrets.sh" 2>/dev/null; then
  echo "ERROR: Probe unexpectedly succeeded with injected file secret!" >&2
else
  echo "Control 1 verified: probe successfully detected injected secret in file."
  control1_passed=1
fi

# Clean up injected file
docker exec -i "${PROJECT_NAME}-agent-1" rm -f /workspace/control-canary.txt

if [ "$control1_passed" -ne 1 ]; then
  "$HARNESS/verdict.sh" "S1 Control: File placement" "FAIL" "Probe failed to detect injected file secret"
  exit 1
fi

# 3. Control 2: Weakened deployment via temporary override file
echo "Testing Control 2: Weakened deployment with key in agent environment..."
WEAKENED_OVERRIDE="$WEAKENED_DIR/weakened-s1.override.yml"
cat > "$WEAKENED_OVERRIDE" <<EOF
services:
  agent:
    environment:
      MODEL_UPSTREAM_KEY: \${MODEL_UPSTREAM_KEY}
EOF

# Restart agent container with weakened override
docker compose \
  --env-file "$REPO_ROOT/pins.env" \
  --env-file "$FIXTURES_FILE" \
  -f "$REPO_ROOT/compose.yml" \
  -f "$REPO_ROOT/compose.fixtures.yml" \
  -f "$WEAKENED_OVERRIDE" \
  -p "$PROJECT_NAME" \
  up -d agent >/dev/null

control2_passed=0
if docker exec -i "${PROJECT_NAME}-agent-1" sh -s -- "$MODEL_KEY" < "$PROBES_DIR/probe-secrets.sh" 2>/dev/null; then
  echo "ERROR: Probe unexpectedly succeeded on weakened agent with environment secret!" >&2
else
  echo "Control 2 verified: probe successfully detected key in agent environment on weakened deployment."
  control2_passed=1
fi

# Restore normal hardened agent container
echo "Restoring hardened agent container..."
docker compose \
  --env-file "$REPO_ROOT/pins.env" \
  --env-file "$FIXTURES_FILE" \
  -f "$REPO_ROOT/compose.yml" \
  -f "$REPO_ROOT/compose.fixtures.yml" \
  -p "$PROJECT_NAME" \
  up -d agent >/dev/null

rm -f "$WEAKENED_OVERRIDE"

if [ "$control2_passed" -ne 1 ]; then
  "$HARNESS/verdict.sh" "S1 Control: Weakened environment" "FAIL" "Probe failed to detect environment secret"
  exit 1
fi

"$HARNESS/verdict.sh" "S1 The key is absent" "PASS" "All secrets absent from agent container; in-container placement and weakened deployment controls confirmed"
exit 0
