#!/bin/sh
set -eu

# Probe to verify absence of secrets from agent container
# Usage: probe-secrets.sh <secret1> [secret2] ...

if [ "$#" -eq 0 ]; then
  echo "ERROR: At least one secret value required as argument" >&2
  exit 2
fi

found_leak=0

for secret in "$@"; do
  [ -n "$secret" ] || continue

  # 1. Check environment variables
  if env | grep -F "$secret" >/dev/null 2>&1; then
    echo "LEAK DETECTED: Secret found in agent environment" >&2
    found_leak=1
  fi

  # 2. Check process environments
  for p in /proc/[0-9]*/environ; do
    [ -f "$p" ] || continue
    if tr '\0' '\n' < "$p" 2>/dev/null | grep -F "$secret" >/dev/null 2>&1; then
      echo "LEAK DETECTED: Secret found in process environment $p" >&2
      found_leak=1
    fi
  done

  # 3. Check accessible filesystem directories
  for dir in /workspace /home/agent/.pi /sessions /tmp; do
    [ -d "$dir" ] || continue
    # Search readable files
    leak_file="$(grep -Frl "$secret" "$dir" 2>/dev/null | head -n 1 || true)"
    if [ -n "$leak_file" ]; then
      echo "LEAK DETECTED: Secret found in file $leak_file" >&2
      found_leak=1
    fi
  done
done

if [ "$found_leak" -ne 0 ]; then
  echo "FAILED: One or more secrets were discovered in the agent container" >&2
  exit 1
fi

echo "PASSED: All checked secrets are absent from environment, processes, and files"
exit 0
