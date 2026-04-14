#!/usr/bin/env bash
# smoke-test.sh — Post-deploy smoke test for the devops-challenge app.
#
# Usage:
#   ./scripts/smoke-test.sh
#
# Environment variables:
#   BASE_URL  — Base URL to test (default: http://devops-challenge.local:8080)
#               In CI the self-hosted runner hits Traefik directly on port 80,
#               so set BASE_URL=http://devops-challenge.local in the workflow.

set -euo pipefail

BASE_URL="${BASE_URL:-http://devops-challenge.local:8080}"
EXPECTED="Latest Crypto Prices"

echo "Running smoke test against ${BASE_URL} ..."

HTTP_STATUS=$(curl -s -o /tmp/smoke-response.html -w "%{http_code}" "${BASE_URL}")

if [[ "${HTTP_STATUS}" != "200" ]]; then
  echo "FAIL: Expected HTTP 200 but got ${HTTP_STATUS}"
  exit 1
fi

if ! grep -q "${EXPECTED}" /tmp/smoke-response.html; then
  echo "FAIL: Response did not contain expected string: '${EXPECTED}'"
  echo "--- Response body (first 20 lines) ---"
  head -20 /tmp/smoke-response.html
  exit 1
fi

echo "PASS: HTTP ${HTTP_STATUS} and response contains '${EXPECTED}'"
