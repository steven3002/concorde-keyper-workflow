#!/bin/sh
set -eu

# Probe to verify prohibited destinations are unreachable from the agent container
# Usage: probe-destinations.sh <canary_host> <canary_port> <canary_ip> <public_ip> <external_dns>

CANARY_HOST="${1:-canary}"
CANARY_PORT="${2:-8080}"
CANARY_IP="${3:-127.0.0.1}"
PUBLIC_IP="${4:-1.1.1.1}"
EXTERNAL_DNS="${5:-example.com}"

probe_target() {
  label="$1"
  url="$2"

  output=""
  status=""
  code=0

  # Use curl with explicit short timeouts
  tmp_err="$(mktemp)"
  if output="$(curl -s -S -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 3 "$url" 2>"$tmp_err")"; then
    code=0
  else
    code=$?
  fi
  err_msg="$(cat "$tmp_err" 2>/dev/null || true)"
  rm -f "$tmp_err"

  if [ "$code" -eq 0 ]; then
    echo "PROBE UNEXPECTED SUCCESS: $label ($url) is reachable (HTTP $output)" >&2
    return 1
  fi

  failure_mode="unknown error (code $code)"
  case "$code" in
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
      failure_mode="connection failed (curl code $code: $err_msg)"
      ;;
  esac

  echo "BLOCKED: $label -> $failure_mode"
  return 0
}

all_blocked=1

echo "Probing prohibited destinations from agent container..."

# 1. Canary by name
if ! probe_target "Canary by name" "http://${CANARY_HOST}:${CANARY_PORT}/"; then
  all_blocked=0
fi

# 2. Canary by IP address
if ! probe_target "Canary by IP address" "http://${CANARY_IP}:${CANARY_PORT}/"; then
  all_blocked=0
fi

# 3. Public IP address
if ! probe_target "Public IP address" "http://${PUBLIC_IP}:80/"; then
  all_blocked=0
fi

# 4. External DNS name
if ! probe_target "External DNS name" "http://${EXTERNAL_DNS}/"; then
  all_blocked=0
fi

if [ "$all_blocked" -eq 1 ]; then
  echo "PASSED: All prohibited destinations are unreachable from the agent"
  exit 0
else
  echo "FAILED: One or more prohibited destinations were reached from the agent" >&2
  exit 1
fi
