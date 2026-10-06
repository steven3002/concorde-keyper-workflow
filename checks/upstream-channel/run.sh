#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
PINS_FILE="$REPO_ROOT/pins.env"
COMPOSE_FILE="$DIR/compose.yml"
PROJECT_NAME="concorde-channel-tests"

cleanup() {
  docker compose --env-file "$PINS_FILE" -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker compose --env-file "$PINS_FILE" -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up --build --abort-on-container-exit --exit-code-from channel-tests
