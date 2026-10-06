#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
PINS_FILE="$REPO_ROOT/pins.env"
FIXTURES_FILE="$REPO_ROOT/fixtures.env"
COMPOSE_BASE="$REPO_ROOT/compose.yml"
COMPOSE_FIXTURES="$REPO_ROOT/compose.fixtures.yml"

PROJECT_NAME="${CONCORDE_PROJECT_NAME:-concorde-baseline}"

compose_cmd() {
  docker compose \
    --env-file "$PINS_FILE" \
    --env-file "$FIXTURES_FILE" \
    -f "$COMPOSE_BASE" \
    -f "$COMPOSE_FIXTURES" \
    -p "$PROJECT_NAME" \
    "$@"
}

action="${1:-start}"

case "$action" in
  start)
    compose_cmd up --build -d
    # Wait for gateway to be healthy
    echo "Waiting for gateway to become healthy..."
    for i in $(seq 1 40); do
      status="$(docker inspect --format '{{.State.Health.Status}}' "${PROJECT_NAME}-gateway-1" 2>/dev/null || echo "starting")"
      if [ "$status" = "healthy" ]; then
        echo "Gateway is healthy"
        exit 0
      fi
      sleep 2
    done
    echo "Gateway failed to become healthy within timeout" >&2
    compose_cmd ps >&2
    docker logs "${PROJECT_NAME}-gateway-1" --tail 50 >&2 || true
    exit 1
    ;;
  stop)
    compose_cmd down -v --remove-orphans
    ;;
  reset)
    compose_cmd down -v --remove-orphans
    compose_cmd up --build -d
    ;;
  exec)
    shift
    compose_cmd exec "$@"
    ;;
  ps)
    compose_cmd ps
    ;;
  logs)
    shift
    compose_cmd logs "$@"
    ;;
  *)
    echo "Usage: stack.sh {start|stop|reset|exec|ps|logs}" >&2
    exit 1
    ;;
esac
