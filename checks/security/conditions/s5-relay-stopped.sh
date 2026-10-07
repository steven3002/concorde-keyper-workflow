#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
HARNESS="$REPO_ROOT/checks/harness"
FIXTURES_FILE="$REPO_ROOT/fixtures.env"

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

echo "=== Running Condition S5: Clear failure when relay stopped, no direct fallback ==="

SEEDED_CHAT_ID="$(grep -E '^TELEGRAM_CHAT_ID=' "$FIXTURES_FILE" | cut -d'=' -f2 | tr -d ' "')"
RELAY_KEY="$(grep -E '^MODEL_UPSTREAM_KEY=' "$FIXTURES_FILE" | cut -d'=' -f2 | tr -d ' "')"
FAILURE_MSG="I am unable to process your request at this time. Please try again later."

# Ensure relay is restored if script exits prematurely
cleanup() {
  compose_cli start relay >/dev/null 2>&1 || true
}
trap cleanup EXIT

# 1. Clear doubles state
"$HARNESS/telegram.sh" clear >/dev/null
compose_cli exec -T model-upstream node doubles/model-upstream/cli.ts clear >/dev/null

# 2. Stop the relay container
echo "Stopping model relay container..."
compose_cli stop relay >/dev/null
echo "Relay container stopped."

# Generate unique monotonic update IDs for this run
UP_ID1="$(date +%s)"
UP_ID2=$(( UP_ID1 + 1 ))

# 3. Inject message from user chat to trigger workflow with stopped relay
echo "Injecting message while relay is down (update_id $UP_ID1)..."
"$HARNESS/telegram.sh" inject "$SEEDED_CHAT_ID" "Check status while relay down" "$UP_ID1" >/dev/null

# 4. Wait for failure notification delivered over Telegram (bound: 45s)
echo "Waiting for canned failure notification to arrive via Telegram (bound: 45s)..."
start_time=$SECONDS
if ! "$HARNESS/telegram.sh" wait_sent "$SEEDED_CHAT_ID" 45 >/dev/null; then
  echo "ERROR: Timed out waiting for failure message when relay is stopped!" >&2
  "$HARNESS/verdict.sh" "S5 Relay stopped failure" "FAIL" "Failure notification timed out"
  exit 1
fi
elapsed=$((SECONDS - start_time))
echo "Failure response delivered within ${elapsed}s (bound was 45s)."

# 5. Assert delivered message contains exact failure text
sent_json="$("$HARNESS/telegram.sh" sent)"
echo "Sent messages recorded at bot-api:"
echo "$sent_json"

if ! echo "$sent_json" | grep -F "$FAILURE_MSG" >/dev/null; then
  echo "ERROR: Sent message does not match expected failure notification!" >&2
  "$HARNESS/verdict.sh" "S5 Relay stopped failure" "FAIL" "Incorrect failure message delivered"
  exit 1
fi
echo "Confirmed: Exact canned failure notice delivered to user."

# 6. Assert model-upstream recorded ZERO requests (no fallback occurred)
upstream_reqs="$(compose_cli exec -T model-upstream node doubles/model-upstream/cli.ts requests)"
req_count="$(echo "$upstream_reqs" | grep -c '"method"' || true)"
echo "Requests received at model-upstream during outage: $req_count"

if [ "$req_count" -ne 0 ]; then
  echo "ERROR: Model upstream received $req_count requests while relay was stopped (unexpected fallback)!" >&2
  "$HARNESS/verdict.sh" "S5 Relay stopped failure" "FAIL" "Direct model requests occurred during relay outage"
  exit 1
fi
echo "Confirmed: Zero requests reached model upstream during outage; no direct-provider fallback attempted."

# 7. Restart relay and confirm normal operation resumes
echo "Restarting relay container..."
compose_cli start relay >/dev/null
sleep 2

# Clear outbox and model requests
"$HARNESS/telegram.sh" clear >/dev/null
compose_cli exec -T model-upstream node doubles/model-upstream/cli.ts clear >/dev/null

echo "Injecting normal query after relay restart (update_id $UP_ID2)..."
"$HARNESS/telegram.sh" inject "$SEEDED_CHAT_ID" "Report current Keyper cluster status" "$UP_ID2" >/dev/null

echo "Waiting for normal status reply after relay recovery (bound: 60s)..."
if ! "$HARNESS/telegram.sh" wait_sent "$SEEDED_CHAT_ID" 60 >/dev/null; then
  echo "ERROR: Stack failed to recover after restarting relay!" >&2
  "$HARNESS/verdict.sh" "S5 Relay recovery" "FAIL" "Normal workflow failed after relay restart"
  exit 1
fi

recovered_sent="$("$HARNESS/telegram.sh" sent)"
if ! echo "$recovered_sent" | grep -F "30 of 39 keypers online" >/dev/null; then
  echo "ERROR: Recovered reply did not contain expected metrics!" >&2
  "$HARNESS/verdict.sh" "S5 Relay recovery" "FAIL" "Invalid metrics in recovered reply"
  exit 1
fi
echo "Confirmed: Stack recovered cleanly and answered subsequent status query normally."

"$HARNESS/verdict.sh" "S5 Relay stopped failure" "PASS" "Stopping relay causes bounded failure notification; 0 upstream requests; stack recovers on restart"
exit 0
