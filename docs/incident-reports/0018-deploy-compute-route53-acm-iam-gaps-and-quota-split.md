# Incident Report 0018: deploy-compute IAM policy quota hit again + three new write-path gaps on first real HTTPS listener bring-up

**Date:** 2026-09-02
**Severity:** Blocking (05-product-security module bring-up), no production/data impact
**Status:** Resolved

## Summary

Standing up the Route53+ACM HTTPS listener for the first time through the
CI deploy role hit four distinct problems in a single failed apply run:
an IAM managed-policy size quota breach (the third hit on
`deploy-compute` this project, see Incident Report 0016 for the second),
and three separate `AccessDenied` errors — ACM, Route53's
`GetHostedZone`, and S3's `PutObjectTagging` — none of which had ever been
exercised through the deploy role before, since this was the module's
first real (non-zero-diff) apply. This is the same recurring class of gap
as Incident Reports 0015 and 0017: invisible on `plan`, invisible on a
`0 changes` apply, and only surfacing the first time the deploy role is
actually asked to create the resource for real.

## Impact

Two failed apply runs before all four problems were resolved and a clean
apply landed. The first failure was near-instant (policy version never
applied, so the ACM/Route53/S3 errors that followed were downstream of a
`terraform apply` that had already lost its plan's IAM changes). The
second failure, after the policy fix, reproduced the identical
ACM/Route53/S3 errors roughly a second after the policy update itself
reported success — an IAM propagation-lag artifact, not a remaining
permissions gap (see Root Cause).

## Timeline

- Terraform plan for the Route53+ACM module (new `aws_acm_certificate`,
  `aws_route53_record` for DNS validation, `aws_route53_record` for the
  ALB alias, plus the new HTTPS listener and HTTP→HTTPS redirect on the
  existing ALB) passes CI cleanly — as expected, since none of these gaps
  are visible to `plan`.
- First real apply fails with four errors in one run:
  `LimitExceeded: Cannot exceed quota for PolicySize: 6144` on
  `iam:CreatePolicyVersion` for `deploy-compute`; `AccessDenied` on an ACM
  action; `AccessDenied` on `route53:GetHostedZone` for
  `aws_route53_record.app_alb_alias`; `AccessDenied` on
  `s3:PutObjectTagging` for the app artifact object. (The three
  `AccessDenied` errors were downstream noise from the same run — the
  intended policy update carrying ACM/Route53 grants never actually landed
  because of the size quota, so the run was still operating on the old,
  pre-update policy.)
- Diagnosed the size quota precisely: a Python script estimating the
  minified-JSON size of the proposed single-policy document put it at
  roughly 6,135/6,144 bytes with ACM+Route53 added — technically under the
  hard limit, but a 9-byte margin too thin to trust or build on. Decided
  against further statement-merging (already exhausted on this policy per
  Incident Report 0016) and split the policy into two
  (`deploy-compute` + new `deploy-compute-ext`), moving `BucketManage`
  into the new policy alongside ACM/Route53 to get a real margin on both
  sides (see ADR 0011 for the full design decision).
- Investigated `route53:GetHostedZone`. Initial hypothesis was that it was
  actually `route53:ListHostedZones` that was missing, tied to a
  `data "aws_route53_zone"` lookup — added `ListHostedZones` (an
  account-wide, unscopeable action) and reverted it once inspection of
  `alb.tf` showed no such data source exists; `zone_id` is passed as a
  plain Terraform variable throughout. The real cause: `aws_route53_record`
  calls `route53:GetHostedZone` internally on create regardless of whether
  a data source is used anywhere in the configuration. Unlike
  `ListHostedZones`, `GetHostedZone` *does* support resource-level scoping
  to a specific zone ARN, so this was fixed by granting `GetHostedZone`
  scoped to the known zone ARN — not by granting the broader, unscopeable
  action. This is case 16 of this project's recurring "looks scopeable,
  isn't" pattern (see `00-shared-context.md`'s CI/CD auth facts), and the
  same shape as `ec2:RunInstances` needing `ec2:CreateTags` alongside it
  for ASG (Incident Report 0015) — a hidden action dependency, not a
  missing-resource-level-support case.
- Fixed `s3:PutObjectTagging` by adding it to the existing `ObjectAccess`
  statement (alongside `GetObject`/`PutObject`/`GetObjectTagging`) — root
  cause was `tags_all` being applied to the `app.zip` object for the first
  time.
- Second apply attempt (after all three fixes plus the policy split)
  reproduced the identical ACM/Route53/S3 `AccessDenied` errors roughly a
  second after `CreatePolicyVersion` reported success. `terraform fmt`
  also failed on this same push, adding one extra small commit/PR cycle.
  Consulted with a bootcamp instructor about the recurring quota hits
  independently around this point; her suggestion (use AWS-managed
  policies for trivial, generic permissions like plain S3 reads, to save
  custom-policy budget for the genuinely scoped statements) is logged
  here as a follow-up, not yet implemented.
- Along the way, PR #69 (carrying the original fix attempt) turned out to
  have already been squash-merged (confirmed `mergedAt: 2026-09-02T11:46:24Z`)
  while further commits kept being pushed to its now-dead branch — this
  produced real merge conflicts and a separate incident, tracked in
  Incident Report 0019, before a fresh PR #70 could carry the actual fix.
- `gh run rerun <run-id> --failed` (no code change) on the post-fix apply
  succeeded once roughly a minute had passed — confirming the second
  failure was IAM propagation lag, not a remaining gap. This is the third
  confirmed instance of this exact lag pattern on this project (previously
  seen twice during the data-tier RDS/ElastiCache work, Incident
  Report 0017).
- PR #70 merged, apply green. HTTPS verified live end to end via curl
  (`HTTP/1.1 301` HTTP→HTTPS redirect, `HTTP/2 200` on the HTTPS listener)
  and a real browser with no certificate warning.

## Root Cause

Four independent causes converging in one bring-up:

1. **IAM policy size quota**, third hit on this policy — this time
   requiring a genuine second managed policy rather than further
   statement-merging, since headroom from merging was already exhausted.
2. **`route53:GetHostedZone` hidden dependency** — `aws_route53_record`
   calls this action internally on every create, independent of whether
   the configuration uses a `data "aws_route53_zone"` source. It does
   support resource-level scoping (unlike `ListHostedZones`), so the fix
   is a scoped grant, not the broader unscopeable action.
3. **`s3:PutObjectTagging` gap** — never previously needed because
   `tags_all` had never been applied to this specific object before.
4. **IAM propagation lag**, third confirmed instance — a newly
   created/attached policy's exact new permissions can still 403 for under
   a minute after the attach API call itself reports success.

## Resolution

- Policy split into `deploy-compute` + `deploy-compute-ext` per ADR 0011.
- `route53:GetHostedZone` granted, scoped to the known hosted zone ARN, in
  the new `deploy-compute-ext` policy's `Route53` statement (alongside
  `ChangeResourceRecordSets`/`ListResourceRecordSets`/`GetChange`).
- `s3:PutObjectTagging` added to `deploy-compute`'s existing `ObjectAccess`
  statement.
- Propagation-lag failure resolved with a plain rerun, no further code
  change.

## Prevention / Follow-up

- Before adding new resource types to a Terraform-managed AWS resource
  (especially DNS, ACM, or anything IAM-conditioned), check whether the
  resource's *create* call has action dependencies beyond the obviously
  relevant one — `aws_route53_record`'s implicit `GetHostedZone` call is
  not documented in the resource's own schema, only in AWS's IAM
  service-authorization reference for the Route53 API.
- Evaluate the instructor's AWS-managed-policy suggestion (using AWS
  managed policies like `AmazonS3ReadOnlyAccess`-style grants for
  genuinely generic, non-project-specific permissions) as a way to reduce
  future custom-policy budget pressure — not yet implemented, worth a
  deliberate look before the next quota hit rather than after.
- Continue treating any newly-added IAM action/resource pair as unproven
  until it has been exercised through the deploy role on a real (non-zero)
  apply at least once — `plan` and no-op applies will never surface this
  class of gap.