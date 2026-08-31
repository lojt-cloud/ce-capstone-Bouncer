#!/usr/bin/env bash
# Brings all billable resources back up across all three layers, in
# dependency order (least-dependent first): foundation -> data-tier
# (waits for RDS to be available) -> compute (waits for ASG instances
# to be healthy). Does NOT reseed test data -- follow RUNBOOK.md's
# "Reseeding test users after RDS recreate" section after this finishes.
# Run from the repo root: ./bringup.sh
set -euo pipefail

REGION="eu-central-1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_ROOT="$REPO_ROOT/terraform/environments/dev"

RDS_WAIT_MAX_ATTEMPTS=40   # 40 * 15s = 10 minutes
ASG_WAIT_MAX_ATTEMPTS=40   # 40 * 15s = 10 minutes

echo "=== 1/3: foundation (NAT Gateway) ==="
(cd "$TF_ROOT/foundation" && terraform apply -var="enable_billable_resources=true" -auto-approve)

echo
echo "=== 2/3: data-tier (RDS + ElastiCache) ==="
(cd "$TF_ROOT/data-tier" && terraform apply -var="enable_billable_resources=true" -auto-approve)

DB_INSTANCE_ID=$(cd "$TF_ROOT/data-tier" && terraform output -raw db_instance_id)
echo
echo "Waiting for RDS ($DB_INSTANCE_ID) to become available..."
attempt=0
while true; do
  attempt=$((attempt + 1))
  STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --region "$REGION" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text 2>/dev/null || echo "not-found")
  echo "  [$attempt/$RDS_WAIT_MAX_ATTEMPTS] RDS status: $STATUS"
  if [ "$STATUS" = "available" ]; then
    break
  fi
  if [ "$attempt" -ge "$RDS_WAIT_MAX_ATTEMPTS" ]; then
    echo "Timed out waiting for RDS to become available -- check manually:"
    echo "  aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_ID --region $REGION"
    exit 1
  fi
  sleep 15
done

echo
echo "=== 3/3: compute (ASG + ALB) ==="
(cd "$TF_ROOT/compute" && terraform apply -var="enable_billable_resources=true" -auto-approve)

ASG_NAME=$(cd "$TF_ROOT/compute" && terraform output -raw asg_name)
echo
echo "Waiting for ASG ($ASG_NAME) instances to be healthy/InService..."
attempt=0
while true; do
  attempt=$((attempt + 1))
  HEALTHY_COUNT=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region "$REGION" \
    --query "length(AutoScalingGroups[0].Instances[?LifecycleState=='InService' && HealthStatus=='Healthy'])" \
    --output text)
  echo "  [$attempt/$ASG_WAIT_MAX_ATTEMPTS] Healthy in-service instances: $HEALTHY_COUNT / 3"
  if [ "$HEALTHY_COUNT" -ge 3 ]; then
    break
  fi
  if [ "$attempt" -ge "$ASG_WAIT_MAX_ATTEMPTS" ]; then
    echo "Timed out waiting for ASG instances to become healthy -- check manually:"
    echo "  aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME --region $REGION"
    exit 1
  fi
  sleep 15
done

echo
echo "=== Bring-up complete. ==="
echo "Next: follow RUNBOOK.md's 'Reseeding test users after RDS recreate' steps."
