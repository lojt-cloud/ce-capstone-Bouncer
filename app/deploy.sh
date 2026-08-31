#!/usr/bin/env bash
set -euo pipefail

# Re-syncs app/src to the compute layer's S3 artifact bucket and triggers
# an ASG instance refresh so running instances pick up the change --
# without touching Terraform state. Run from anywhere.
#
# Requires: AWS CLI configured for the target account, and the compute
# layer already applied at least once (so the bucket and ASG exist).

REGION="eu-central-1"
ENVIRONMENT="${ENVIRONMENT:-dev}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SRC_DIR="$SCRIPT_DIR/src"
COMPUTE_DIR="$SCRIPT_DIR/../terraform/environments/$ENVIRONMENT/compute"

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

ZIP_PATH="$BUILD_DIR/app.zip"
(cd "$APP_SRC_DIR" && zip -rq "$ZIP_PATH" . -x '__pycache__/*' '*.pyc' 'venv/*')

BUCKET=$(cd "$COMPUTE_DIR" && terraform output -raw app_artifact_bucket_name)
ASG_NAME=$(cd "$COMPUTE_DIR" && terraform output -raw asg_name)

echo "Uploading app.zip to s3://$BUCKET/app.zip"
aws s3 cp "$ZIP_PATH" "s3://$BUCKET/app.zip" --region "$REGION"

echo "Triggering instance refresh on $ASG_NAME"
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name "$ASG_NAME" \
  --region "$REGION" \
  --preferences '{"MinHealthyPercentage": 66, "InstanceWarmup": 120}'

echo "Instance refresh started. Watch progress with:"
echo "aws autoscaling describe-instance-refreshes --auto-scaling-group-name $ASG_NAME --region $REGION"