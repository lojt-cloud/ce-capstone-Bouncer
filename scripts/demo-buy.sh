#!/usr/bin/env bash
set -euo pipefail

BASE_URL="https://app.projectbouncer.org"

USERNAME="${1:?Usage: $0 <username> <password>}"
PASSWORD="${2:?Usage: $0 <username> <password>}"

COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT

LOGIN_BODY=$(python3 -c \
  "import json,sys; print(json.dumps({'username':sys.argv[1],'password':sys.argv[2]}))" \
  "$USERNAME" "$PASSWORD"
)

BUY_BODY='{"event_id":1}'

echo "==> Target: ${BASE_URL}"
echo "==> Username: ${USERNAME}"
echo

echo "==> Logging in..."
LOGIN_CODE=$(curl -sS -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -o /dev/null -w "%{http_code}" \
  -X POST "${BASE_URL}/login" \
  -H "Content-Type: application/json" \
  -d "$LOGIN_BODY")

echo "  login: HTTP ${LOGIN_CODE}"

if [[ "$LOGIN_CODE" != "200" ]]; then
  echo "ERROR: Login failed."
  exit 1
fi

echo
echo "==> Attempting first purchase..."
FIRST_CODE=$(curl -sS -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -o /dev/null -w "%{http_code}" \
  -X POST "${BASE_URL}/buy" \
  -H "Content-Type: application/json" \
  -d "$BUY_BODY")

echo "  first buy: HTTP ${FIRST_CODE}"

if [[ "$FIRST_CODE" != "201" ]]; then
  echo "ERROR: Expected first purchase to return HTTP 201."
  exit 1
fi

echo
echo "==> Attempting second purchase as the same user..."
SECOND_RESPONSE=$(curl -sS -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -X POST "${BASE_URL}/buy" \
  -H "Content-Type: application/json" \
  -d "$BUY_BODY" \
  -w "\nHTTP_STATUS:%{http_code}")

SECOND_CODE=$(printf '%s\n' "$SECOND_RESPONSE" | sed -n 's/^HTTP_STATUS://p')

printf '%s\n' "$SECOND_RESPONSE" | sed '/^HTTP_STATUS:/d'

echo
echo "  second buy: HTTP ${SECOND_CODE}"

if [[ "$SECOND_CODE" != "409" ]]; then
  echo "ERROR: Expected second purchase to return HTTP 409."
  exit 1
fi

echo
echo "PASS: One user can purchase once, but a second purchase is rejected."