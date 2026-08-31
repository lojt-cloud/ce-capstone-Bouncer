#!/usr/bin/env bash
# Tears down all billable resources across all three layers, in dependency
# order (most-dependent first): compute -> data-tier -> foundation.
# Run from the repo root: ./teardown.sh
set -euo pipefail

REGION="eu-central-1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_ROOT="$REPO_ROOT/terraform/environments/dev"

echo "=== 1/3: compute (ASG + ALB) ==="
(cd "$TF_ROOT/compute" && terraform apply -var="enable_billable_resources=false" -auto-approve)

echo
echo "=== 2/3: data-tier (RDS + ElastiCache -- this deletes DB/cache content) ==="
(cd "$TF_ROOT/data-tier" && terraform apply -var="enable_billable_resources=false" -auto-approve)

echo
echo "=== 3/3: foundation (NAT Gateway) ==="
if ! (cd "$TF_ROOT/foundation" && terraform apply -var="enable_billable_resources=false" -auto-approve); then
  echo
  echo "foundation apply failed -- checking for the known stale-EIP release bug"
  echo "(AWS's ReleaseAddress API sometimes errors on a stale ENI reference"
  echo "right after the NAT Gateway that used it is destroyed)."
  EIP_ALLOC_ID=$(
    cd "$TF_ROOT/foundation" && \
    terraform state show 'module.networking.aws_eip.nat[0]' 2>/dev/null \
      | sed -n 's/^[[:space:]]*id[[:space:]]*=[[:space:]]*"\(eipalloc-[a-z0-9]*\)".*/\1/p' \
      | head -1
  )
  if [ -n "$EIP_ALLOC_ID" ]; then
    echo "Found $EIP_ALLOC_ID still in state -- releasing directly and retrying apply"
    aws ec2 release-address --allocation-id "$EIP_ALLOC_ID" --region "$REGION" || true
    (cd "$TF_ROOT/foundation" && terraform apply -var="enable_billable_resources=false" -auto-approve)
  else
    echo "Could not find a dangling EIP in state to auto-recover -- check manually:"
    echo "  cd $TF_ROOT/foundation && terraform state list | grep eip"
    exit 1
  fi
fi

echo
echo "=== Teardown complete. All billable resources are off. ==="
