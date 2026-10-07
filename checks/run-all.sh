#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/.." && pwd)"
HARNESS="$DIR/harness"

echo "=========================================================="
echo "Concorde Keyper Workflow Test Suite Runner"
echo "=========================================================="

all_suites=(
  "upstream-channel:$DIR/upstream-channel/run.sh:Upstream Telegram channel tests (s1)"
  "baseline:$DIR/baseline/run.sh:Baseline deployment & signal flow (s2)"
  "relay:$DIR/relay/run.sh:Model relay & credential boundary (s3)"
  "workflow:$DIR/workflow/run.sh:End-to-end metrics & status workflow (s4)"
  "security:$DIR/security/run.sh:Security conditions S1–S5 & controls (s5)"
)

target_suites=()
if [ "$#" -gt 0 ]; then
  for arg in "$@"; do
    for suite_info in "${all_suites[@]}"; do
      IFS=":" read -r s_name s_cmd s_desc <<< "$suite_info"
      if [ "$s_name" = "$arg" ]; then
        target_suites+=("$suite_info")
      fi
    done
  done
  if [ "${#target_suites[@]}" -eq 0 ]; then
    echo "ERROR: Unknown suite '$*'. Available suites: upstream-channel, baseline, relay, workflow, security" >&2
    exit 1
  fi
else
  target_suites=("${all_suites[@]}")
fi

failed=0
summary=()

for suite_info in "${target_suites[@]}"; do
  IFS=":" read -r suite_name suite_cmd suite_desc <<< "$suite_info"
  echo ""
  echo "----------------------------------------------------------"
  echo "Starting Suite: $suite_name ($suite_desc)"
  echo "----------------------------------------------------------"

  start_ts=$SECONDS
  if "$HARNESS/capture.sh" "$suite_name" "$suite_cmd"; then
    dur=$((SECONDS - start_ts))
    summary+=("[PASS] $suite_name (${dur}s) - $suite_desc")
  else
    dur=$((SECONDS - start_ts))
    summary+=("[FAIL] $suite_name (${dur}s) - $suite_desc")
    failed=$((failed + 1))
  fi
done

echo ""
echo "=========================================================="
echo "Overall Test Suites Summary"
echo "=========================================================="
for res in "${summary[@]}"; do
  echo "$res"
done
echo "=========================================================="

if [ "$failed" -eq 0 ]; then
  echo "ALL TEST SUITES PASSED"
  exit 0
else
  echo "FAILURES DETECTED: $failed suite(s) failed"
  exit 1
fi
