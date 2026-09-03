#!/usr/bin/env bash
# Tear down the billable Bouncer resources for a local working/demo session.
#
# Order:
#   compute -> data-tier -> foundation
#
# This is destructive for RDS and ElastiCache. RDS row data is deleted when
# the data tier is destroyed.
#
# The script updates the three dev.auto.tfvars files so local Terraform,
# committed desired state, and the environment agree.
#
# This is a LOCAL operational script. It uses the AWS credentials configured
# in the local environment. GitHub Actions uses the separate OIDC deploy role.
#
# Run:
#   ./scripts/teardown.sh
#
# The script does not commit or push the tfvars changes.

set -euo pipefail

REGION="eu-central-1"

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

echo "=== Bouncer local teardown ==="
echo "Repository: $REPO_ROOT"
echo "Region:     $REGION"
echo
echo "WARNING: RDS and ElastiCache will be destroyed."
echo "RDS row data will be lost and must be reseeded on the next bring-up."
echo

read -r -p "Continue with teardown? Type 'yes' to continue: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Teardown cancelled."
  exit 0
fi

echo
echo "=== 1/3: compute (ASG + ALB + WAF) ==="
set_billable_state compute false
(
  cd "$TF_ROOT/compute"
  terraform apply -auto-approve
)
echo

echo "=== 2/3: data-tier (RDS + ElastiCache) ==="
set_billable_state data-tier false
(
  cd "$TF_ROOT/data-tier"
  terraform apply -auto-approve
)
echo

echo "=== 3/3: foundation (NAT Gateway) ==="
set_billable_state foundation false

if ! (
  cd "$TF_ROOT/foundation"
  terraform apply -auto-approve
); then
  echo
  echo "Foundation apply failed. Checking for the known NAT/EIP release race..."

  EIP_ALLOC_ID="$(
    cd "$TF_ROOT/foundation" && \
      terraform state show 'module.networking.aws_eip.nat[0]' 2>/dev/null \
      | sed -n 's/^[[:space:]]*id[[:space:]]*=[[:space:]]*"\(eipalloc-[a-z0-9]*\)".*/\1/p' \
      | head -1
  )"

  if [[ -z "$EIP_ALLOC_ID" ]]; then
    echo "ERROR: could not find the NAT EIP allocation in Terraform state." >&2
    exit 1
  fi

  echo "Retrying EIP release for $EIP_ALLOC_ID..."

  RELEASED=false

  for attempt in 1 2 3 4 5; do
    ERR_LOG=$(mktemp)

    if aws ec2 release-address \
      --allocation-id "$EIP_ALLOC_ID" \
      --region "$REGION" \
      2>"$ERR_LOG"; then
      RELEASED=true
      rm -f "$ERR_LOG"
      break
    fi

    if grep -q "InvalidAllocationID.NotFound" "$ERR_LOG"; then
      RELEASED=true
      rm -f "$ERR_LOG"
      break
    fi

    rm -f "$ERR_LOG"

    echo "  attempt $attempt/5 failed; waiting 15s..."
    sleep 15
  done

  if [[ "$RELEASED" != "true" ]]; then
    echo "ERROR: EIP release still failing after 5 attempts." >&2
    echo "Check:"
    echo "  aws ec2 describe-addresses \\"
    echo "    --allocation-ids $EIP_ALLOC_ID \\"
    echo "    --region $REGION"
    exit 1
  fi

  echo "EIP released. Finishing foundation apply..."

  (
    cd "$TF_ROOT/foundation"
    terraform apply -auto-approve
  )
fi

echo
echo "=== Teardown complete ==="
echo
echo "Billable-resource toggles are now set to false."
echo "The script did not commit or push the tfvars changes."
echo
echo "Before the next bring-up, remember that RDS data was destroyed."
