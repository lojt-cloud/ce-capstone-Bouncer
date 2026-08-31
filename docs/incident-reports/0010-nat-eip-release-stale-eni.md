# Incident 0010: NAT Gateway EIP release fails with stale ENI reference on toggle-off

**Date:** 2026-08-31
**Module:** Foundation (`enable_billable_resources` toggle)
**Severity:** Low — teardown blocked temporarily, no resource loss, resolved same session.

## Summary
Toggling foundation's `enable_billable_resources` to `false` destroyed
the NAT Gateway cleanly, then failed releasing its Elastic IP:
`InvalidNetworkInterfaceID.NotFound`, referencing an ENI that no longer
existed. Retrying `terraform apply` immediately reproduced the
identical error, referencing the same already-gone ENI ID both times.

## Root cause
AWS's `ReleaseAddress` API path errored against a stale, already-gone
ENI reference left over from the just-destroyed NAT Gateway.
`aws ec2 describe-addresses` on the allocation confirmed the EIP had no
`AssociationId` or `NetworkInterfaceId` at all — AWS's own account
state considered it already fully disassociated — so this was an
API-level inconsistency on the delete path, not a real dependency
Terraform needed to wait out.

## How it was caught
The `terraform apply` output surfaced the error directly; diagnosed by
checking `aws ec2 describe-addresses --allocation-ids <id>` against
Terraform's assumption of a lingering association, which ruled that
out.

## Resolution
Released the EIP directly, bypassing Terraform's delete call:
`aws ec2 release-address --allocation-id <id> --region eu-central-1`,
then re-ran `terraform apply -var="enable_billable_resources=false"`,
which found no drift and completed with 0 changes.

## Prevention / lesson
When a destroy fails referencing an ID that "does not exist," check the
resource's real AWS-side state before assuming it's a timing issue
worth retrying blindly. `teardown.sh` (added this session) auto-detects
this specific failure and retries with a direct `release-address` call,
so this shouldn't need manual intervention going forward.