#!/usr/bin/env bash
# smoke-test.sh — Post-deploy smoke test for the devops-challenge app.
#
# Usage:
#   ./scripts/smoke-test.sh
#
# Environment variables:
#   BASE_URL     — Base URL to test (default: http://devops-challenge.local)
#   HOST_HEADER  — Optional Host header override. Use when BASE_URL is an IP
#                  address so Traefik can route to the correct ingress.
#                  Example: HOST_HEADER=devops-challenge.local BASE_URL=http://192.168.122.10
#   MAX_RETRIES  — Number of attempts before giving up (default: 5)
#   RETRY_DELAY  — Seconds between retries (default: 10)

set -euo pipefail

BASE_URL="${BASE_URL:-http://devops-challenge.local}"
HOST_HEADER="${HOST_HEADER:-}"
EXPECTED="LatestPrices"
MAX_RETRIES="${MAX_RETRIES:-5}"
RETRY_DELAY="${RETRY_DELAY:-10}"

CURL_OPTS=(-s -o /tmp/smoke-response.html -w "%{http_code}")
[[ -n "$HOST_HEADER" ]] && CURL_OPTS+=(-H "Host: ${HOST_HEADER}")

echo "Running smoke test against ${BASE_URL} ..."

HTTP_STATUS="000"
for attempt in $(seq 1 "$MAX_RETRIES"); do
  HTTP_STATUS=$(curl "${CURL_OPTS[@]}" "${BASE_URL}")
  if [[ "${HTTP_STATUS}" == "200" ]]; then
    break
  fi
  echo "Attempt ${attempt}/${MAX_RETRIES}: got HTTP ${HTTP_STATUS}"
  if [[ "$attempt" -lt "$MAX_RETRIES" ]]; then
    echo "Retrying in ${RETRY_DELAY}s..."
    sleep "$RETRY_DELAY"
  fi
done

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
