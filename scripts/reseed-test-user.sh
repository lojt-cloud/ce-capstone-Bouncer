#!/usr/bin/env bash
set -euo pipefail

REGION="eu-central-1"
ASG_NAME="ce-capstone-bouncer-dev-app-asg"
DB_SECRET="ce-capstone-bouncer-dev-db-credentials"
ALB_NAME="ce-capstone-bouncer-dev-alb"

USERNAME="${1:-testuser}"
PASSWORD="${2:?Usage: $0 <username> <password>}"

echo "==> Checking ASG health..."
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" --region "$REGION" \
  --query "AutoScalingGroups[0].Instances[].{Id:InstanceId,Health:HealthStatus,State:LifecycleState}" \
  --output table

INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" --region "$REGION" \
  --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService']|[0].InstanceId" \
  --output text)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "None" ]; then
  echo "No InService instance found." >&2
  exit 1
fi
echo "==> Using instance: $INSTANCE_ID"

PASSWORD_B64=$(printf '%s' "$PASSWORD" | base64)
USERNAME_B64=$(printf '%s' "$USERNAME" | base64)

REMOTE_SCRIPT=$(cat <<'EOS'
set -e
which psql >/dev/null 2>&1 || sudo dnf install -y postgresql16 >/dev/null
DB_JSON=$(aws secretsmanager get-secret-value --secret-id __DB_SECRET__ --region __REGION__ --query SecretString --output text)
DB_HOST=$(echo "$DB_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin)['host'])")
DB_PASS=$(echo "$DB_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin)['password'])")

SQL=$(/opt/bouncer-app/venv/bin/python3 -c '
import bcrypt, base64

username = base64.b64decode("__USERNAME_B64__").decode()
password = base64.b64decode("__PASSWORD_B64__")
pw_hash = bcrypt.hashpw(password, bcrypt.gensalt()).decode()

q = chr(39)
def esc(s):
    return s.replace(q, q + q)

sql = "INSERT INTO users (username, password_hash) VALUES (" + q + esc(username) + q + ", " + q + esc(pw_hash) + q + ") ON CONFLICT (username) DO UPDATE SET password_hash = EXCLUDED.password_hash;"
print(sql)
')

PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p 5432 -U bouncer_admin -d bouncer -v ON_ERROR_STOP=1 -c "$SQL"
echo "SEEDED_OK"
EOS
)

REMOTE_SCRIPT="${REMOTE_SCRIPT//__DB_SECRET__/$DB_SECRET}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__REGION__/$REGION}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__PASSWORD_B64__/$PASSWORD_B64}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__USERNAME_B64__/$USERNAME_B64}"

PARAMS_FILE=$(mktemp)
python3 -c "
import json, sys
script = sys.stdin.read()
json.dump({'commands': [script]}, open(sys.argv[1], 'w'))
" "$PARAMS_FILE" <<< "$REMOTE_SCRIPT"

echo "==> Sending reseed command via SSM..."
CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "file://$PARAMS_FILE" \
  --region "$REGION" \
  --query "Command.CommandId" --output text)
rm -f "$PARAMS_FILE"

echo "==> Command ID: $CMD_ID (waiting for completion...)"
aws ssm wait command-executed --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" --region "$REGION" || true

RESULT=$(aws ssm get-command-invocation \
  --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" --region "$REGION" \
  --query "{Status:Status,StdOut:StandardOutputContent,StdErr:StandardErrorContent}" \
  --output json)
echo "$RESULT"

STATUS=$(echo "$RESULT" | python3 -c "import json,sys;print(json.load(sys.stdin)['Status'])")
if [ "$STATUS" != "Success" ]; then
  echo "Reseed command did not succeed (status: $STATUS). See StdErr above." >&2
  exit 1
fi

echo "==> Verifying login via ALB..."
ALB_DNS=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" --region "$REGION" --query 'LoadBalancers[0].DNSName' --output text)
BODY=$(python3 -c "import json,sys;print(json.dumps({'username':sys.argv[1],'password':sys.argv[2]}))" "$USERNAME" "$PASSWORD")

curl -i -X POST "https://app.projectbouncer.org/login" -H "Content-Type: application/json" -d "$BODY"
