#!/usr/bin/env bash
# Tears down all billable resources across all three layers, in dependency
# order (most-dependent first): compute -> data-tier -> foundation.
#
# enable_billable_resources is git-tracked per layer via dev.auto.tfvars,
# not a runtime -var flag -- this script writes "false" into each layer's
# file before applying, so local state and whatever CI applies next always
# agree. After running this, commit and push the dev.auto.tfvars changes
# (a normal PR) so CI's own apply doesn't try to undo them on the next
# merge that touches terraform/**.
#
# Run from the repo root: ./teardown.sh
set -euo pipefail

REGION="eu-central-1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_ROOT="$REPO_ROOT/terraform/environments/dev"

set_off() {
  echo 'enable_billable_resources = false' > "$TF_ROOT/$1/dev.auto.tfvars"
}

echo "=== 1/3: compute (ASG + ALB) ==="
set_off compute
(cd "$TF_ROOT/compute" && terraform apply -auto-approve)
echo

echo "=== 2/3: data-tier (RDS + ElastiCache -- this deletes DB/cache content) ==="
set_off data-tier
(cd "$TF_ROOT/data-tier" && terraform apply -auto-approve)
echo

echo "=== 3/3: foundation (NAT Gateway) ==="
set_off foundation
if ! (cd "$TF_ROOT/foundation" && terraform apply -auto-approve); then
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
    (cd "$TF_ROOT/foundation" && terraform apply -auto-approve)
  else
    echo "Could not find a dangling EIP in state to auto-recover -- check manually:"
    echo "  cd $TF_ROOT/foundation && terraform state list | grep eip"
    exit 1
  fi
fi

echo
echo "=== Teardown complete. All billable resources are off locally. ==="
echo "Now commit + push the dev.auto.tfvars changes so CI agrees:"
echo "  git add terraform/environments/dev/*/dev.auto.tfvars"
echo "  git commit -m 'chore: toggle billable resources off for the night'"
echo "  git push ... (open a PR, merge -- 0 required approvals, but still needs a PR)"
