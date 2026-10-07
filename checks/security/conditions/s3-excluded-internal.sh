#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
HARNESS="$REPO_ROOT/checks/harness"
FIXTURES_FILE="$REPO_ROOT/fixtures.env"
PROBES_DIR="$REPO_ROOT/checks/security/probes"

PROJECT_NAME="${CONCORDE_PROJECT_NAME:-concorde-security-check}"
export CONCORDE_PROJECT_NAME="$PROJECT_NAME"

HOST_LISTENER_PORT="${HOST_LISTENER_PORT:-39485}"
LISTENER_PID=""
LISTENER_LOG="$(mktemp)"

cleanup() {
  if [ -n "$LISTENER_PID" ]; then
    kill "$LISTENER_PID" 2>/dev/null || true
    wait "$LISTENER_PID" 2>/dev/null || true
  fi
  rm -f "$LISTENER_LOG"
  docker network rm plain_internal_control_net 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Running Condition S3: Excluded internal services and Docker host unreachable ==="

# Check if port is already in use on host
if ss -tuln | grep -q ":${HOST_LISTENER_PORT} "; then
  echo "ERROR: Chosen host listener port ${HOST_LISTENER_PORT} is already in use on host!" >&2
  exit 1
fi

# 1. Start host-namespace listener on high port on 0.0.0.0
echo "Starting host listener on port ${HOST_LISTENER_PORT} in host network namespace..."
python3 -u -c "
import socket, sys

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', int(sys.argv[1])))
s.listen(10)
print('LISTENER_READY', flush=True)

while True:
    try:
        conn, addr = s.accept()
        print(f'HIT {addr[0]}:{addr[1]}', flush=True)
        conn.close()
    except Exception:
        break
" "$HOST_LISTENER_PORT" > "$LISTENER_LOG" 2>&1 &
LISTENER_PID=$!

# Wait for listener to bind
for i in $(seq 1 20); do
  if grep -q "LISTENER_READY" "$LISTENER_LOG" 2>/dev/null; then
    break
  fi
  sleep 0.2
done

# 2. Collect host candidate addresses
# Subnet .1 address for concorde_agent
agent_subnet="$(docker network inspect concorde_agent --format '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || echo "172.19.0.0/16")"
subnet_prefix="$(echo "$agent_subnet" | cut -d'.' -f1-3)"
subnet_dot1="${subnet_prefix}.1"

# Host interface IPv4 addresses
host_ips="$(ip -4 addr show | grep -oE 'inet [0-9.]+' | cut -d' ' -f2 | tr '\n' ',' | sed 's/,$//')"
docker0_ip="172.17.0.1"

all_host_candidates="${subnet_dot1},${docker0_ip},${host_ips}"
echo "Collected host candidate addresses to probe: $all_host_candidates"

# 3. Main check: probe excluded internal services and Docker host from agent
echo "Running in-container internal services probe from agent..."
if docker exec -i "${PROJECT_NAME}-agent-1" sh -s -- "$HOST_LISTENER_PORT" "$all_host_candidates" < "$PROBES_DIR/probe-internal-services.sh"; then
  echo "Confirmed: PostgreSQL, model-upstream, metrics-fixture, bot-api, gateway public, and Docker host all failed to connect."
else
  echo "ERROR: One or more excluded internal services were reachable from agent!" >&2
  "$HARNESS/verdict.sh" "S3 Excluded internal services unreachable" "FAIL" "Excluded service reached from agent"
  exit 1
fi

# Verify host listener recorded zero hits from agent
host_hits="$(grep "HIT" "$LISTENER_LOG" || true)"
if [ -n "$host_hits" ]; then
  echo "ERROR: Host listener recorded hits from agent during isolation test: $host_hits" >&2
  "$HARNESS/verdict.sh" "S3 Excluded internal services unreachable" "FAIL" "Host listener received connection from agent"
  exit 1
fi
echo "Confirmed: Host listener recorded zero connections from agent."

# 4. Control for Docker host (M-02):
# Verify that a container on a plain internal network without isolated mode DOES reach the host listener
echo "Testing Control for Docker Host (M-02): Starting container on plain internal network..."
docker network create --internal plain_internal_control_net >/dev/null
plain_gw="$(docker network inspect plain_internal_control_net --format '{{(index .IPAM.Config 0).Gateway}}')"
echo "Plain internal network gateway address: $plain_gw"

control_host_reached=0
if docker run --rm --network plain_internal_control_net alpine:latest nc -w 2 "$plain_gw" "$HOST_LISTENER_PORT" >/dev/null 2>&1; then
  control_host_reached=1
fi
docker network rm plain_internal_control_net >/dev/null 2>&1 || true

control_hits="$(grep "HIT" "$LISTENER_LOG" || true)"
if [ "$control_host_reached" -eq 1 ] && [ -n "$control_hits" ]; then
  echo "Control verified (M-02): Host listener was successfully reached from plain internal network ($control_hits)."
else
  echo "ERROR: Control failed! Plain internal network container failed to reach host listener" >&2
  "$HARNESS/verdict.sh" "S3 Control: Docker host reachability" "FAIL" "Plain internal network failed to reach host listener"
  exit 1
fi

# 5. Controls for excluded services (prove they are up and reachable from authorized peers)
echo "Testing Controls for other excluded services..."

# Postgres is reachable from gateway
if docker exec -i "${PROJECT_NAME}-gateway-1" node -e "
  const net = require('node:net');
  const s = net.createConnection({ host: 'postgres', port: 5432 }, () => { s.destroy(); process.exit(0); });
  s.on('error', () => process.exit(1));
" 2>/dev/null; then
  echo "Control: PostgreSQL is reachable from gateway on concorde_db network."
else
  echo "ERROR: Control failed: PostgreSQL unreachable from gateway" >&2
  exit 1
fi

# Model upstream is reachable from relay
if docker exec -i "${PROJECT_NAME}-relay-1" curl -s -o /dev/null -w "%{http_code}" http://model-upstream:8080/ | grep -q "200\|404\|405"; then
  echo "Control: Model upstream is reachable from relay on concorde_egress network."
else
  echo "ERROR: Control failed: Model upstream unreachable from relay" >&2
  exit 1
fi

# Metrics fixture is reachable from metrics-gate
if docker exec -i "${PROJECT_NAME}-metrics-gate-1" curl -s -o /dev/null -w "%{http_code}" http://metrics-fixture:8080/ | grep -q "200\|404\|405"; then
  echo "Control: Metrics fixture is reachable from metrics-gate on concorde_egress network."
else
  echo "ERROR: Control failed: Metrics fixture unreachable from metrics-gate" >&2
  exit 1
fi

# Bot API is reachable from gateway
if docker exec -i "${PROJECT_NAME}-gateway-1" node -e "
  fetch('http://bot-api:8080/').then(r => process.exit(0)).catch(() => process.exit(1));
" 2>/dev/null; then
  echo "Control: Bot API is reachable from gateway on concorde_egress network."
else
  echo "ERROR: Control failed: Bot API unreachable from gateway" >&2
  exit 1
fi

# Gateway public API is reachable on loopback inside gateway container
if docker exec -i "${PROJECT_NAME}-gateway-1" node -e "
  fetch('http://127.0.0.1:8081/openapi.json').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1));
" 2>/dev/null; then
  echo "Control: Gateway public API is reachable on loopback inside gateway container."
else
  echo "ERROR: Control failed: Gateway public API unreachable on loopback" >&2
  exit 1
fi

"$HARNESS/verdict.sh" "S3 Excluded internal services unreachable" "PASS" "PostgreSQL, doubles, gateway public, and Docker host unreachable from agent; all paired controls succeeded"
exit 0
