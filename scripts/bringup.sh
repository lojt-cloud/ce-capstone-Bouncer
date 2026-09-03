#!/usr/bin/env bash
# Bring up the billable Bouncer resources for a local working/demo session.
#
# Order:
#   foundation -> data-tier -> compute
#
# This script updates the three dev.auto.tfvars files so local Terraform,
# committed desired state, and the environment agree.
#
# This is a LOCAL operational script. It uses the AWS credentials configured
# in the local environment. GitHub Actions uses the separate OIDC deploy role.
#
# Run:
#   ./scripts/bringup.sh
#
# After a full teardown, RDS is recreated empty. Reseed the demo data using
# scripts/reseed-test-user.sh.

set -euo pipefail

REGION="eu-central-1"
RDS_WAIT_MAX_ATTEMPTS=40
ASG_WAIT_MAX_ATTEMPTS=40

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_ROOT="$REPO_ROOT/terraform/environments/dev"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

set_billable_state() {
  local layer="$1"
  local value="$2"
  local tfvars="$TF_ROOT/$layer/dev.auto.tfvars"

  if [[ ! -f "$tfvars" ]]; then
    echo "ERROR: missing $tfvars" >&2
    exit 1
  fi

  if grep -q '^enable_billable_resources[[:space:]]*=' "$tfvars"; then
    sed -i \
      "s/^enable_billable_resources[[:space:]]*=.*/enable_billable_resources = $value/" \
      "$tfvars"
  else
    printf '\nenable_billable_resources = %s\n' "$value" >> "$tfvars"
  fi
}

require_command terraform
require_command aws

echo "=== Bouncer local bring-up ==="
echo "Repository: $REPO_ROOT"
echo "Region:     $REGION"
echo

echo "=== 1/3: foundation (NAT Gateway) ==="
set_billable_state foundation true
(
  cd "$TF_ROOT/foundation"
  terraform apply -auto-approve
)
echo

echo "=== 2/3: data-tier (RDS + ElastiCache) ==="
set_billable_state data-tier true
(
  cd "$TF_ROOT/data-tier"
  terraform apply -auto-approve
)
echo

DB_INSTANCE_ID="$(
  cd "$TF_ROOT/data-tier"
  terraform output -raw db_instance_id
)"

echo "Waiting for RDS ($DB_INSTANCE_ID) to become available..."
attempt=0

while true; do
  attempt=$((attempt + 1))

  STATUS="$(
    aws rds describe-db-instances \
      --db-instance-identifier "$DB_INSTANCE_ID" \
      --region "$REGION" \
      --query 'DBInstances[0].DBInstanceStatus' \
      --output text 2>/dev/null || echo "not-found"
  )"

  echo "  [$attempt/$RDS_WAIT_MAX_ATTEMPTS] RDS status: $STATUS"

  if [[ "$STATUS" == "available" ]]; then
    break
  fi

  if (( attempt >= RDS_WAIT_MAX_ATTEMPTS )); then
    echo "ERROR: timed out waiting for RDS to become available." >&2
    echo "Check:"
    echo "  aws rds describe-db-instances \\"
    echo "    --db-instance-identifier $DB_INSTANCE_ID \\"
    echo "    --region $REGION"
    exit 1
  fi

  sleep 15
done

echo
echo "=== 3/3: compute (ASG + ALB + WAF) ==="
set_billable_state compute true
(
  cd "$TF_ROOT/compute"
  terraform apply -auto-approve
)
echo

ASG_NAME="$(
  cd "$TF_ROOT/compute"
  terraform output -raw asg_name
)"

TARGET_GROUP_ARN="$(
  cd "$TF_ROOT/compute"
  terraform output -raw target_group_arn
)"

DESIRED_CAPACITY="$(
  aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region "$REGION" \
    --query 'AutoScalingGroups[0].DesiredCapacity' \
    --output text
)"

if [[ -z "$DESIRED_CAPACITY" || "$DESIRED_CAPACITY" == "None" ]]; then
  echo "ERROR: could not determine ASG desired capacity." >&2
  exit 1
fi

echo "Waiting for ASG ($ASG_NAME) to have $DESIRED_CAPACITY healthy InService instance(s)..."
attempt=0

while true; do
  attempt=$((attempt + 1))

  HEALTHY_COUNT="$(
    aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names "$ASG_NAME" \
      --region "$REGION" \
      --query "length(AutoScalingGroups[0].Instances[?LifecycleState=='InService' && HealthStatus=='Healthy'])" \
      --output text
  )"

  echo "  [$attempt/$ASG_WAIT_MAX_ATTEMPTS] Healthy InService instances: $HEALTHY_COUNT / $DESIRED_CAPACITY"

  if [[ "$HEALTHY_COUNT" -ge "$DESIRED_CAPACITY" ]]; then
    break
  fi

  if (( attempt >= ASG_WAIT_MAX_ATTEMPTS )); then
    echo "ERROR: timed out waiting for ASG instances to become healthy." >&2
    echo "Check:"
    echo "  aws autoscaling describe-auto-scaling-groups \\"
    echo "    --auto-scaling-group-names $ASG_NAME \\"
    echo "    --region $REGION"
    exit 1
  fi

  sleep 15
done

echo
echo "Checking ALB target health..."

HEALTHY_TARGETS="$(
  aws elbv2 describe-target-health \
    --target-group-arn "$TARGET_GROUP_ARN" \
    --region "$REGION" \
    --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
    --output text
)"

echo "Healthy ALB targets: $HEALTHY_TARGETS / $DESIRED_CAPACITY"

if [[ "$HEALTHY_TARGETS" -lt "$DESIRED_CAPACITY" ]]; then
  echo "ERROR: not all expected ALB targets are healthy." >&2
  echo "Check:"
  echo "  aws elbv2 describe-target-health \\"
  echo "    --target-group-arn $TARGET_GROUP_ARN \\"
  echo "    --region $REGION"
  exit 1
fi

echo
echo "=== Bring-up complete ==="
echo
echo "Billable-resource toggles are now set to true."
echo "The script did not commit or push the tfvars changes."
echo
echo "If this followed a full teardown, RDS was recreated empty."
echo "Next step: reseed demo data before testing the purchase flow."
