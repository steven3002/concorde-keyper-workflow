#!/bin/sh
set -eu

# Direct in-container probe to verify rejection of unapproved methods and paths on relay

check_route() {
  method="$1"
  path="$2"
  expected_status="$3"

  status="$(curl -s -o /dev/null -w "%{http_code}" -X "$method" "http://relay:8080$path")"
  echo "$method $path -> HTTP $status (expected $expected_status)"

  if [ "$status" != "$expected_status" ]; then
    echo "ERROR: Expected HTTP $expected_status but received $status for $method $path" >&2
    exit 1
  fi
}

echo "Testing unapproved methods on permitted route..."
check_route "GET" "/v1/chat/completions" "405"
check_route "PUT" "/v1/chat/completions" "405"
check_route "DELETE" "/v1/chat/completions" "405"

echo "Testing unapproved paths..."
check_route "GET" "/" "404"
check_route "POST" "/v1/models" "404"
check_route "GET" "/v1/models" "404"
check_route "POST" "/v1/embeddings" "404"
check_route "POST" "/v1/chat/completions/" "404"
check_route "POST" "/v1/chat/completions/extra" "404"

echo "All relay rejection tests passed successfully."
