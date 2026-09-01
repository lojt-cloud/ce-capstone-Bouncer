# Incident 0011: CreateNatGateway denied — IAM resource-level check against a referenced Elastic IP
**Date:** 2026-09-01
**Module:** CI/CD (Foundation deploy-role policy)
**Severity:** Low — caught by CI before any real impact; no resource loss, no downtime (foundation networking was already intentionally torn down for cost at the time).

## Summary
The first-ever automated `terraform apply` for the foundation layer
through the CI/CD deploy role (`terraform-apply.yml`, newly added) failed
with `UnauthorizedOperation` on `ec2:CreateNatGateway`, naming a specific
pre-existing Elastic IP ARN as the unauthorized resource — not the new
NAT Gateway itself.

## Root cause
Foundation's `NetworkingCreate` IAM statement granted
`ec2:CreateNatGateway` under `resources = ["*"]` with an
`aws:RequestTag/Project` condition. That's correct for the new NAT
Gateway resource (tagged in the same request), but `CreateNatGateway`
also checks resource-level permission against the pre-existing Elastic
IP it attaches to via `AllocationId` — that EIP is never tagged in this
request (it isn't being created), so the `RequestTag` condition can
never be satisfied for it, and the action is denied against that
resource specifically. The gap was invisible until now because it's a
write-path permission: `terraform plan` never exercises
`CreateNatGateway` (read-only refresh), and the original NAT Gateway had
been created locally with admin credentials, never through the deploy
role.

## How it was caught
`terraform-apply.yml` ran for real against foundation for the first time
(all prior applies had been local, admin-credentialed).
`gh run view --log` on the failed run surfaced the exact error and
offending resource ARN.

## Resolution
Moved `ec2:CreateNatGateway` out of the tag-conditioned `NetworkingCreate`
statement into `NetworkingNoScopeSupport` (unconditioned,
`resources = ["*"]`) — the same statement already used for other actions
AWS doesn't support clean resource/tag scoping on.
`terraform/modules/iam/main.tf`.

## Prevention / lesson
`terraform plan` passing clean under a scoped role proves read/refresh
permissions are sufficient — it proves nothing about write/create
permissions the role has never actually been asked to exercise. Any
layer/action combination that's never been created or destroyed through
the deploy role before should be treated as unverified, even after many
clean `plan` runs. Related: `0003` (deploy-role permission gaps),
`0006` (S3 bucket phantom recreation) — same underlying class of "plan
can't see this," different specific mechanism each time.
