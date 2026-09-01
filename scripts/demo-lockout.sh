#!/usr/bin/env bash
set -euo pipefail

REGION="eu-central-1"
ALB_NAME="ce-capstone-bouncer-dev-alb"

USERNAME="${1:-testuser}"
PASSWORD="${2:?Usage: $0 <username> <correct-password>}"

ALB_DNS=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" --region "$REGION" --query 'LoadBalancers[0].DNSName' --output text)
echo "==> Target: http://${ALB_DNS}"

WRONG_BODY=$(python3 -c "import json,sys;print(json.dumps({'username':sys.argv[1],'password':'wrongpassword'}))" "$USERNAME")
CORRECT_BODY=$(python3 -c "import json,sys;print(json.dumps({'username':sys.argv[1],'password':sys.argv[2]}))" "$USERNAME" "$PASSWORD")

echo "==> Sending 5 wrong-password attempts..."
for i in 1 2 3 4 5; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://${ALB_DNS}/login" -H "Content-Type: application/json" -d "$WRONG_BODY")
  echo "  attempt $i: $CODE"
done

echo
echo "==> Now trying the CORRECT password while locked..."
curl -i -X POST "http://${ALB_DNS}/login" -H "Content-Type: application/json" -d "$CORRECT_BODY"
