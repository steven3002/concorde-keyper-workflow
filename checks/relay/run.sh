#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
HARNESS="$REPO_ROOT/checks/harness"
FIXTURES_FILE="$REPO_ROOT/fixtures.env"

PROJECT_NAME="concorde-s3-relay"
export CONCORDE_PROJECT_NAME="$PROJECT_NAME"

cleanup() {
  echo "Tearing down relay test stack..."
  "$HARNESS/stack.sh" stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== Starting model relay check (s3) ==="

SEEDED_CHAT_ID="$(grep -E '^TELEGRAM_CHAT_ID=' "$FIXTURES_FILE" | cut -d'=' -f2 | tr -d ' "')"
RELAY_KEY="$(grep -E '^MODEL_UPSTREAM_KEY=' "$FIXTURES_FILE" | cut -d'=' -f2 | tr -d ' "')"

# 1. Stack startup and health
"$HARNESS/stack.sh" reset >/dev/null 2>&1 || true
"$HARNESS/stack.sh" start

"$HARNESS/verdict.sh" "S3.1 Stack startup and relay availability" "PASS" "Gateway, agent, relay, and doubles started cleanly"

# 2. Probe relay route and method rejection from agent container
echo "Running relay route rejection probe from agent container..."
docker exec -i "${PROJECT_NAME}-agent-1" sh < "$DIR/probes/rejection.sh"
"$HARNESS/verdict.sh" "S3.2 Relay route and method rejection" "PASS" "Unapproved routes (404) and non-POST methods (405) rejected"

# 3. Probe unbuffered incremental streaming through relay
echo "Running streaming timing probe from agent container..."
docker exec -i "${PROJECT_NAME}-agent-1" sh < "$DIR/probes/streaming.sh"
"$HARNESS/verdict.sh" "S3.3 Unbuffered incremental streaming" "PASS" "Streamed SSE events arrived incrementally through relay"

# 4. Probe agent container environment and readable files for credential absence
echo "Running agent credential isolation probe..."
docker exec -i "${PROJECT_NAME}-agent-1" sh -s "$RELAY_KEY" < "$DIR/probes/env-secret.sh"
"$HARNESS/verdict.sh" "S3.4 Credential isolation in agent container" "PASS" "Real model key absent from agent environment, proc, and files"

# 5. End-to-end tool call round trip and credential replacement
echo "Clearing doubles state..."
"$HARNESS/telegram.sh" clear >/dev/null
docker compose \
  --env-file "$REPO_ROOT/pins.env" \
  --env-file "$FIXTURES_FILE" \
  -f "$REPO_ROOT/compose.yml" \
  -f "$REPO_ROOT/compose.fixtures.yml" \
  -p "$PROJECT_NAME" \
  exec -T model-upstream node doubles/model-upstream/cli.ts clear >/dev/null

echo "Injecting Telegram update to trigger model tool call round-trip..."
"$HARNESS/telegram.sh" inject "$SEEDED_CHAT_ID" "Check Keyper node status" 30001

echo "Waiting for agent reply to be delivered over Telegram..."
"$HARNESS/telegram.sh" wait_sent "$SEEDED_CHAT_ID" 45

sent_json="$("$HARNESS/telegram.sh" sent)"
echo "Sent messages recorded by bot-api double:"
echo "$sent_json"

if ! echo "$sent_json" | grep -Fq "Keyper status: all systems operational."; then
  echo "ERROR: Expected reply text not found in Telegram sent messages" >&2
  "$HARNESS/verdict.sh" "S3.5 Tool call round-trip and Telegram reply" "FAIL" "Reply text missing from Telegram outbox"
  exit 1
fi
"$HARNESS/verdict.sh" "S3.5 Tool call round-trip and Telegram reply" "PASS" "Tool call executed and reply delivered via Telegram"

# Inspect model-upstream recorded requests
upstream_requests="$(docker compose \
  --env-file "$REPO_ROOT/pins.env" \
  --env-file "$FIXTURES_FILE" \
  -f "$REPO_ROOT/compose.yml" \
  -f "$REPO_ROOT/compose.fixtures.yml" \
  -p "$PROJECT_NAME" \
  exec -T model-upstream node doubles/model-upstream/cli.ts requests)"

echo "Recorded requests at model-upstream:"
echo "$upstream_requests"

# Verify that the relay replaced the Authorization header with the real key
if echo "$upstream_requests" | grep -Fq "dummy-agent-placeholder-key"; then
  echo "ERROR: Agent placeholder key leaked to model upstream!" >&2
  "$HARNESS/verdict.sh" "S3.6 Relay credential replacement" "FAIL" "Agent placeholder key observed at upstream"
  exit 1
fi

if ! echo "$upstream_requests" | grep -Fq "Bearer $RELAY_KEY"; then
  echo "ERROR: Upstream model key was not received by model upstream!" >&2
  "$HARNESS/verdict.sh" "S3.6 Relay credential replacement" "FAIL" "Relay key not found in upstream request headers"
  exit 1
fi
"$HARNESS/verdict.sh" "S3.6 Relay credential replacement" "PASS" "Relay substituted real key; agent placeholder never reached upstream"

# Verify tool result present in follow-up request
if ! echo "$upstream_requests" | grep -Fq '"role": "tool"'; then
  echo "ERROR: Follow-up request did not contain role: tool" >&2
  "$HARNESS/verdict.sh" "S3.7 Tool result in follow-up request" "FAIL" "Follow-up request lacked tool result"
  exit 1
fi
"$HARNESS/verdict.sh" "S3.7 Tool result in follow-up request" "PASS" "Stand-in received tool result in follow-up request"

# 6. Unreachable model behavior (relay stopped)
echo "Testing unreachable model behavior (stopping relay)..."
docker compose \
  --env-file "$REPO_ROOT/pins.env" \
  --env-file "$FIXTURES_FILE" \
  -f "$REPO_ROOT/compose.yml" \
  -f "$REPO_ROOT/compose.fixtures.yml" \
  -p "$PROJECT_NAME" \
  stop relay

"$HARNESS/telegram.sh" clear >/dev/null
docker compose \
  --env-file "$REPO_ROOT/pins.env" \
  --env-file "$FIXTURES_FILE" \
  -f "$REPO_ROOT/compose.yml" \
  -f "$REPO_ROOT/compose.fixtures.yml" \
  -p "$PROJECT_NAME" \
  exec -T model-upstream node doubles/model-upstream/cli.ts clear >/dev/null

echo "Injecting Telegram update while relay is stopped..."
"$HARNESS/telegram.sh" inject "$SEEDED_CHAT_ID" "Check status while relay down" 30002

echo "Waiting for failure notice to be delivered..."
"$HARNESS/telegram.sh" wait_sent "$SEEDED_CHAT_ID" 45

failure_sent="$("$HARNESS/telegram.sh" sent)"
echo "Sent messages during relay outage:"
echo "$failure_sent"

if ! echo "$failure_sent" | grep -Fq "I am unable to process your request at this time. Please try again later."; then
  echo "ERROR: Failure notice not delivered when relay was stopped" >&2
  "$HARNESS/verdict.sh" "S3.8 Unreachable model failure handling" "FAIL" "Failure notice not delivered"
  exit 1
fi

requests_during_outage="$(docker compose \
  --env-file "$REPO_ROOT/pins.env" \
  --env-file "$FIXTURES_FILE" \
  -f "$REPO_ROOT/compose.yml" \
  -f "$REPO_ROOT/compose.fixtures.yml" \
  -p "$PROJECT_NAME" \
  exec -T model-upstream node doubles/model-upstream/cli.ts requests)"

if [ "$(echo "$requests_during_outage" | grep -c '"method":' || true)" -ne 0 ]; then
  echo "ERROR: Model upstream received requests while relay was stopped!" >&2
  "$HARNESS/verdict.sh" "S3.8 Unreachable model failure handling" "FAIL" "Unexpected requests received at upstream"
  exit 1
fi
"$HARNESS/verdict.sh" "S3.8 Unreachable model failure handling" "PASS" "Run failed promptly with failure notice; zero requests reached upstream"

echo "=== All relay checks (s3) passed successfully ==="
