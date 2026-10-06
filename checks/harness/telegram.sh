#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
PINS_FILE="$REPO_ROOT/pins.env"
FIXTURES_FILE="$REPO_ROOT/fixtures.env"
COMPOSE_BASE="$REPO_ROOT/compose.yml"
COMPOSE_FIXTURES="$REPO_ROOT/compose.fixtures.yml"

PROJECT_NAME="${CONCORDE_PROJECT_NAME:-concorde-baseline}"

bot_cli() {
  docker compose \
    --env-file "$PINS_FILE" \
    --env-file "$FIXTURES_FILE" \
    -f "$COMPOSE_BASE" \
    -f "$COMPOSE_FIXTURES" \
    -p "$PROJECT_NAME" \
    exec -T bot-api node doubles/bot-api/cli.ts "$@"
}

action="${1:-}"

case "$action" in
  inject)
    shift
    bot_cli inject "$@"
    ;;
  sent)
    bot_cli sent
    ;;
  clear)
    bot_cli clear
    ;;
  wait_sent)
    target_chat="${2:?target chatId required}"
    timeout_sec="${3:-30}"
    deadline=$((SECONDS + timeout_sec))

    while [ $SECONDS -lt $deadline ]; do
      raw_sent="$(bot_cli sent 2>/dev/null || echo '{"sent":[]}')"
      found="$(echo "$raw_sent" | grep -F "\"chatId\": \"$target_chat\"" || true)"
      if [ -n "$found" ]; then
        echo "$raw_sent"
        exit 0
      fi
      sleep 1
    done

    echo "Timed out waiting for sent message to chat $target_chat after ${timeout_sec}s" >&2
    exit 1
    ;;
  *)
    echo "Usage: telegram.sh {inject <chatId> <text> [updateId] | wait_sent <chatId> [timeout] | sent | clear}" >&2
    exit 1
    ;;
esac
