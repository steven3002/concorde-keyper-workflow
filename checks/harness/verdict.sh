#!/usr/bin/env bash
set -euo pipefail

condition="${1:?condition name required}"
status="${2:?status PASS|FAIL required}"
detail="${3:-}"

if [ "$status" = "PASS" ]; then
  if [ -n "$detail" ]; then
    printf "[PASS] %s - %s\n" "$condition" "$detail"
  else
    printf "[PASS] %s\n" "$condition"
  fi
  exit 0
else
  if [ -n "$detail" ]; then
    printf "[FAIL] %s - %s\n" "$condition" "$detail" >&2
  else
    printf "[FAIL] %s\n" "$condition" >&2
  fi
  exit 1
fi
