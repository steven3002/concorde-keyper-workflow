#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
HARNESS="$REPO_ROOT/checks/harness"
FIXTURES_FILE="$REPO_ROOT/fixtures.env"

PROJECT_NAME="concorde-s2-baseline"
export CONCORDE_PROJECT_NAME="$PROJECT_NAME"

cleanup() {
  echo "Tearing down baseline test stack..."
  "$HARNESS/stack.sh" stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== Starting baseline deployment check (s2) ==="

# Read seeded chat id and secrets from fixtures.env
SEEDED_CHAT_ID="$(grep -E '^TELEGRAM_CHAT_ID=' "$FIXTURES_FILE" | cut -d'=' -f2 | tr -d ' "')"
TELEGRAM_TOKEN="$(grep -E '^TELEGRAM_BOT_TOKEN=' "$FIXTURES_FILE" | cut -d'=' -f2 | tr -d ' "')"

# 1. Stack starts and reaches healthy gateway on an empty database
"$HARNESS/stack.sh" reset >/dev/null 2>&1 || true
"$HARNESS/stack.sh" start

"$HARNESS/verdict.sh" "S2.1 Gateway health" "PASS" "Gateway reached healthy state on empty database"

# Clear any previous messages in the mock bot API
"$HARNESS/telegram.sh" clear >/dev/null

# 2. Inject update from seeded chat: produces stored inbound message and Run
echo "Injecting update from seeded chat $SEEDED_CHAT_ID..."
"$HARNESS/telegram.sh" inject "$SEEDED_CHAT_ID" "Check node status" 20001

echo "Waiting for failure notice to be sent back to chat $SEEDED_CHAT_ID..."
# The Run will fail because no model endpoint is connected. Time bound: 45 seconds.
"$HARNESS/telegram.sh" wait_sent "$SEEDED_CHAT_ID" 45

sent_json="$("$HARNESS/telegram.sh" sent)"
echo "Sent messages recorded by bot-api double:"
echo "$sent_json"

# Verify in postgres database:
# 1 inbound message, 1 outbound message, 1 failed run
db_query() {
  docker exec "${PROJECT_NAME}-postgres-1" psql -U concorde -d concorde -t -A -c "$1"
}

inbound_count="$(db_query "SELECT count(*) FROM concorde_messenger.messages WHERE direction = 'inbound';")"
outbound_count="$(db_query "SELECT count(*) FROM concorde_messenger.messages WHERE direction = 'outbound';")"
runs_count="$(db_query "SELECT count(*) FROM concorde_signals.runs;")"
failed_runs_count="$(db_query "SELECT count(*) FROM concorde_signals.runs WHERE state = 'failed';")"

echo "Database verification:"
echo "Inbound messages: $inbound_count, Outbound messages: $outbound_count, Runs: $runs_count (Failed: $failed_runs_count)"

if [ "$inbound_count" -ge 1 ] && [ "$outbound_count" -ge 1 ] && [ "$failed_runs_count" -ge 1 ]; then
  "$HARNESS/verdict.sh" "S2.2 Seeded message run and failure notice" "PASS" "Message produced Run, Run failed as intended, failure notice recorded"
else
  "$HARNESS/verdict.sh" "S2.2 Seeded message run and failure notice" "FAIL" "Expected stored messages and failed run"
fi

# 3. Inject update from unknown chat: answered with chat id, stores nothing in messages
UNKNOWN_CHAT_ID="888777666"
echo "Injecting update from unknown chat $UNKNOWN_CHAT_ID..."
"$HARNESS/telegram.sh" inject "$UNKNOWN_CHAT_ID" "Unauthorized request" 20002

echo "Waiting for response to unknown chat..."
"$HARNESS/telegram.sh" wait_sent "$UNKNOWN_CHAT_ID" 15

sent_unknown="$("$HARNESS/telegram.sh" sent)"
if echo "$sent_unknown" | grep -F "This chat is not registered with the agent. Its id is $UNKNOWN_CHAT_ID"; then
  # Check that message table did not gain new inbound messages
  current_inbound="$(db_query "SELECT count(*) FROM concorde_messenger.messages WHERE direction = 'inbound';")"
  if [ "$current_inbound" -eq "$inbound_count" ]; then
    "$HARNESS/verdict.sh" "S2.3 Unknown chat rejection" "PASS" "Answered with chat id and stored nothing in message log"
  else
    "$HARNESS/verdict.sh" "S2.3 Unknown chat rejection" "FAIL" "Inbound message was erroneously stored"
  fi
else
  "$HARNESS/verdict.sh" "S2.3 Unknown chat rejection" "FAIL" "Did not answer with unregistered notice"
fi

# 4. Agent container environment contains no Telegram token and no database URL
echo "Checking agent container environment..."
agent_env="$(docker exec "${PROJECT_NAME}-agent-1" env)"

if echo "$agent_env" | grep -qi "DATABASE_URL"; then
  "$HARNESS/verdict.sh" "S2.4 Agent secret leakage: DATABASE_URL" "FAIL" "DATABASE_URL found in agent env"
fi
if echo "$agent_env" | grep -qi "TELEGRAM_BOT_TOKEN"; then
  "$HARNESS/verdict.sh" "S2.4 Agent secret leakage: TELEGRAM_BOT_TOKEN" "FAIL" "TELEGRAM_BOT_TOKEN found in agent env"
fi
if echo "$agent_env" | grep -Fq "$TELEGRAM_TOKEN"; then
  "$HARNESS/verdict.sh" "S2.4 Agent secret leakage: token value" "FAIL" "Telegram token value found in agent env"
fi
"$HARNESS/verdict.sh" "S2.4 Agent environment secret isolation" "PASS" "Agent environment contains no Telegram token and no database URL"

# 5. No container mounts the Docker socket
echo "Checking for Docker socket mounts across all containers..."
containers="$(docker compose -p "$PROJECT_NAME" ps -q)"
socket_found=0
for c in $containers; do
  c_name="$(docker inspect --format '{{.Name}}' "$c")"
  mounts="$(docker inspect --format '{{json .Mounts}}' "$c")"
  if echo "$mounts" | grep -qi "docker.sock"; then
    echo "Container $c_name mounts docker socket!" >&2
    socket_found=1
  fi
done

if [ "$socket_found" -eq 0 ]; then
  "$HARNESS/verdict.sh" "S2.5 Docker socket confinement" "PASS" "No container mounts the Docker socket"
else
  "$HARNESS/verdict.sh" "S2.5 Docker socket confinement" "FAIL" "Docker socket mounted in container"
fi

echo "=== All baseline checks passed successfully ==="
