#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
HARNESS="$REPO_ROOT/checks/harness"
CONDITIONS_DIR="$DIR/conditions"

PROJECT_NAME="concorde-s5-security"
export CONCORDE_PROJECT_NAME="$PROJECT_NAME"

cleanup() {
  echo "Tearing down security check stack..."
  "$HARNESS/stack.sh" stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=========================================================="
echo "Starting Concorde Security Conditions Test Suite (s5)"
echo "=========================================================="

# 1. Start clean fixture stack
echo "Resetting and starting fixture stack under project $PROJECT_NAME..."
"$HARNESS/stack.sh" reset >/dev/null 2>&1 || true
"$HARNESS/stack.sh" start

echo ""
echo "=== Step 1: Condition S1 (Key Absence) ==="
"$CONDITIONS_DIR/s1-key-absence.sh"

echo ""
echo "=== Step 2: Condition S2 (Prohibited Destination Unreachable) ==="
"$CONDITIONS_DIR/s2-prohibited-destination.sh"

echo ""
echo "=== Step 3: Condition S3 (Excluded Internal Services & Docker Host) ==="
"$CONDITIONS_DIR/s3-excluded-internal.sh"

echo ""
echo "=== Step 4: Condition S4 (Unapproved Relay Routes Rejected) ==="
"$CONDITIONS_DIR/s4-relay-routes.sh"

echo ""
echo "=== Step 5: Condition S5 (Relay Stopped Clear Failure) ==="
"$CONDITIONS_DIR/s5-relay-stopped.sh"

echo ""
echo "=========================================================="
echo "All five security conditions (S1–S5) passed successfully!"
echo "=========================================================="
exit 0
