#!/bin/sh
set -eu

# Probe to verify excluded internal services are unreachable from the agent container
# Usage: probe-internal-services.sh <host_listener_port> <host_addrs_comma_separated>

HOST_PORT="${1:?host listener port required}"
HOST_ADDRS="${2:-}"

probe_tcp() {
  label="$1"
  host="$2"
  port="$3"

  tmp_err="$(mktemp)"
  status=0

  # Use curl or nc with short timeouts
  if curl -s -S -o /dev/null --connect-timeout 2 --max-time 3 "http://${host}:${port}/" 2>"$tmp_err"; then
    status=0
  else
    status=$?
  fi
  err_msg="$(cat "$tmp_err" 2>/dev/null || true)"
  rm -f "$tmp_err"

  if [ "$status" -eq 0 ]; then
    echo "PROBE UNEXPECTED SUCCESS: $label (${host}:${port}) is reachable!" >&2
    return 1
  fi

  failure_mode="unknown error (code $status)"
  case "$status" in
    6)
      failure_mode="name resolution failed (NXDOMAIN / SERVFAIL)"
      ;;
    7)
      if echo "$err_msg" | grep -qi "Network unreachable"; then
        failure_mode="network unreachable (no route to host)"
      elif echo "$err_msg" | grep -qi "Connection refused"; then
        failure_mode="connection refused"
      else
        failure_mode="connection failed (code 7: $err_msg)"
      fi
      ;;
    28)
      failure_mode="connection timed out"
      ;;
    *)
      failure_mode="connection failed (code $status: $err_msg)"
      ;;
  esac

  echo "BLOCKED: $label (${host}:${port}) -> $failure_mode"
  return 0
}

all_blocked=1

echo "Probing excluded internal services from agent container..."

# 1. PostgreSQL
if ! probe_tcp "PostgreSQL" "postgres" "5432"; then
  all_blocked=0
fi

# 2. Model upstream stand-in
if ! probe_tcp "Model upstream stand-in" "model-upstream" "8080"; then
  all_blocked=0
fi

# 3. Metrics fixture server
if ! probe_tcp "Metrics fixture double" "metrics-fixture" "8080"; then
  all_blocked=0
fi

# 4. Bot API stand-in
if ! probe_tcp "Bot API stand-in" "bot-api" "8080"; then
  all_blocked=0
fi

# 5. Gateway public API server
if ! probe_tcp "Gateway public server" "gateway" "8081"; then
  all_blocked=0
fi

# 6. Docker host probes (M-02)
echo "Probing Docker host candidates on port ${HOST_PORT}..."
if [ -n "$HOST_ADDRS" ]; then
  # Comma-separated addresses
  old_ifs="$IFS"
  IFS=","
  for addr in $HOST_ADDRS; do
    [ -n "$addr" ] || continue
    if ! probe_tcp "Host candidate ($addr)" "$addr" "$HOST_PORT"; then
      all_blocked=0
    fi
  done
  IFS="$old_ifs"
fi

# Special host name
if ! probe_tcp "Special host name (host.docker.internal)" "host.docker.internal" "$HOST_PORT"; then
  all_blocked=0
fi

if [ "$all_blocked" -eq 1 ]; then
  echo "PASSED: All excluded internal services and Docker host are unreachable from agent"
  exit 0
else
  echo "FAILED: One or more excluded internal services were reachable from agent" >&2
  exit 1
fi
