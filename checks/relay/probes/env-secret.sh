#!/bin/sh
set -eu

secret_val="${1:?secret value required as first argument}"

echo "Checking agent environment variables..."
if env | grep -i "MODEL_UPSTREAM_KEY" >/dev/null; then
  echo "ERROR: MODEL_UPSTREAM_KEY variable found in agent environment" >&2
  exit 1
fi

if env | grep -F "$secret_val" >/dev/null; then
  echo "ERROR: Upstream model secret value found in agent environment" >&2
  exit 1
fi

echo "Checking process environments in agent container..."
found_in_proc=0
for p in /proc/[0-9]*/environ; do
  [ -f "$p" ] || continue
  if tr '\0' '\n' < "$p" | grep -F "$secret_val" >/dev/null 2>&1; then
    echo "ERROR: Secret value found in process environ $p" >&2
    found_in_proc=1
  fi
done

if [ "$found_in_proc" -ne 0 ]; then
  exit 1
fi

echo "Checking agent configuration files..."
if grep -Fr "$secret_val" /workspace /home/agent/.pi 2>/dev/null; then
  echo "ERROR: Secret value found in files accessible to agent" >&2
  exit 1
fi

echo "Confirmed: model upstream secret is absent from agent container."
