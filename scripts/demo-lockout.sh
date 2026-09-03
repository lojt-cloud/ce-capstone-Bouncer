#!/usr/bin/env bash
set -euo pipefail

REGION="eu-central-1"
BASE_URL="https://app.projectbouncer.org"

USERNAME="${1:-testuser}"
PASSWORD="${2:?Usage: $0 <username> <correct-password>}"

WRONG_BODY=$(python3 -c \
  "import json,sys; print(json.dumps({'username':sys.argv[1],'password':'wrongpassword'}))" \
  "$USERNAME"
)

CORRECT_BODY=$(python3 -c \
  "import json,sys; print(json.dumps({'username':sys.argv[1],'password':sys.argv[2]}))" \
  "$USERNAME" "$PASSWORD"
)

echo "==> Target: ${BASE_URL}"
echo "==> Username: ${USERNAME}"
echo

echo "==> Sending 5 wrong-password attempts..."

for i in 1 2 3 4 5; do
  CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
    -X POST "${BASE_URL}/login" \
    -H "Content-Type: application/json" \
    -d "$WRONG_BODY")

  echo "  attempt ${i}: HTTP ${CODE}"
done

echo
echo "==> Trying the correct password while the account is locked..."

curl -sS -i \
  -X POST "${BASE_URL}/login" \
  -H "Content-Type: application/json" \
  -d "$CORRECT_BODY"
