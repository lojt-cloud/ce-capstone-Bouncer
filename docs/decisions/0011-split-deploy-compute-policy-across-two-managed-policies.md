# ADR 0011: Split deploy-compute IAM permissions across two managed policies

**Date:** 2026-09-02
**Status:** Accepted

## Context

`ce-capstone-bouncer-dev-deploy-compute` hit IAM's hard 6,144-byte
managed-policy size quota for the third documented time on this project
(see Incident Report 0016 for the second hit, and
`claude/cicd-checkov-interview-qa.md` for the first, both during compute's
original build). This time the trigger was adding the ACM
(`RequestCertificate`/`DescribeCertificate`/`DeleteCertificate`/
`AddTagsToCertificate`/`ListTagsForCertificate`) and Route53
(`GetHostedZone`/`ChangeResourceRecordSets`/`ListResourceRecordSets`/
`GetChange`) permissions the Route53+ACM HTTPS module needs.

Incident Report 0016 already flagged this as the next lever if the quota
was hit again: "splitting compute's deploy permissions across two managed
policies attached to the same role... is the next lever before any
permission has to be cut." Unlike 0016, statement-merging alone wasn't
enough headroom this time — a size estimate (minified-JSON byte count via
a Python script) showed adding ACM+Route53 to the existing single policy
would land at ~6,135/6,144 bytes, a 9-byte margin too thin to be workable
for future changes.

The previous blocker to a genuine multi-policy split was AWS's
managed-policies-per-role default quota of 10. AWS raised that default to
20 in August 2026
([source](https://aws.amazon.com/about-aws/whats-new/2026/08/aws-iam-quota-increase/)),
which is what makes this option viable now without a quota-increase
support ticket.

## Decision

Split `deploy-compute`'s permissions across two separate customer-managed
IAM policies, both attached to the same `ce-capstone-bouncer-deploy` role:

- **`ce-capstone-bouncer-dev-deploy-compute`** (existing, unchanged name):
  keeps `ReadOnly`, launch-template create/manage, ASG create/manage, ELBv2
  create/manage/no-scope, S3 object read/write/tag on the artifact bucket
  (`ObjectAccess`), CloudWatch log group manage, policy self-manage,
  role-policy-attach, Terraform state object/list access, and the
  unconditioned `RunInstances`/`CreateTags` grant from ADR 0010.
- **`ce-capstone-bouncer-dev-deploy-compute-ext`** (new): the S3 *bucket*
  config statement (`BucketManage` — versioning, encryption, lifecycle,
  public-access-block, etc. on the artifact bucket, 22 actions), plus the
  new ACM and Route53 statements.

`BucketManage` moved to the new policy alongside ACM/Route53 rather than
staying in the original — it was the single largest remaining statement,
and moving it (not just the smaller ACM/Route53 additions) was what
produced a workable margin on both policies (original policy dropped to
roughly 5,439 bytes used; new policy at roughly 1,197 bytes), instead of
leaving one policy still uncomfortably close to the ceiling.

Both policies are attached to the same role, so this is a pure
size-quota workaround, not a permissions-boundary or blast-radius change —
`ce-capstone-bouncer-deploy` gains the union of both policies' permissions
exactly as if they were one document.

## Consequences

- Compute's deploy-role permissions now live in two Terraform-managed
  policy resources (`aws_iam_policy.deploy_compute` and
  `aws_iam_policy.deploy_compute_ext`) instead of one. Anyone auditing
  "what can the compute deploy role do" needs to read both.
  `PolicySelfManage` and `RoleAttach` (in the original policy) were both
  updated to reference all three of the role's policy ARNs (app policy +
  both compute policies), so the role can still manage/attach its own
  policies without a further gap.
- This buys headroom for compute's deploy role but doesn't eliminate the
  underlying quota — a future compute change that adds enough new
  statements will hit it again, on whichever of the two policies it grows.
  At that point, the next lever is a genuine third policy (headroom to 20
  per role is large), not statement-merging (already exhausted on the
  original policy) or a support-ticket quota increase (unnecessary given
  the 2026 default bump).
- This pattern (two-plus managed policies on one role, size-driven, not
  boundary-driven) is now precedent for any other layer's deploy-compute
  policy that hits the same wall — data-tier and foundation should reach
  for this before requesting a manual AWS quota increase.
