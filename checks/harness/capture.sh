#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"

check_name="${1:?check name required}"
shift

out_dir="$REPO_ROOT/results/fixture/$check_name"
mkdir -p "$out_dir"
timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
log_file="$out_dir/output.log"

echo "=== Run started at $timestamp for $check_name ===" > "$log_file"

"$@" 2>&1 | tee -a "$log_file"
exit_code="${PIPESTATUS[0]}"

echo "=== Run ended with exit code $exit_code ===" >> "$log_file"
exit "$exit_code"
