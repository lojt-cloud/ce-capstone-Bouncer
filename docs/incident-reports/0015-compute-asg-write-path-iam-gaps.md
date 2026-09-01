# Incident Report 0015: Compute ASG write-path IAM gaps on first real create

**Date:** 2026-09-01
**Severity:** Blocking (compute layer bring-up), no production/data impact
**Status:** Resolved

## Summary

Bringing compute's Auto Scaling Group up for the first real time through the
CI deploy role (`ce-capstone-bouncer-deploy`) — via `terraform-apply.yml`,
not a local admin apply — took five follow-up PRs (#48–#52) after the initial
toggle-flip PR (#47) before a `terraform apply` of
`terraform/environments/dev/compute` actually succeeded end to end. Every gap
was a real, previously-unexercised write-path permission: `enable_billable_resources`
had only ever been tested at `false` (a 0-change no-op) before this session,
so nothing about creating the ASG through the deploy role — as opposed to
through local admin credentials, as it was originally built — had ever been
proven.

No data loss, no security exposure, no cost impact beyond normal CI minutes.
The ALB, target group, and listener all created cleanly on the very first
attempt with no IAM issues at all — this incident is scoped entirely to the
ASG's own creation path.

## Impact

Compute layer bring-up blocked for approximately 90 minutes of active
debugging. Three intermediate applies left a "tainted" ASG behind (AWS
registered the group but couldn't launch its instances, so Terraform marked
it for destroy-and-replace on the next apply) — each cost roughly 1–2 minutes
of destroy/recreate cycling once the root cause was actually fixed, but no
lasting effect since the ASG never had real traffic or state to lose.

## Timeline (all times 2026-09-01, UTC)

- **~13:50** — PR #47 merged (`enable_billable_resources = true` for
  compute). First real apply: ALB, target group, and listener all create
  cleanly. ASG creation fails: `AccessDenied ... no identity-based policy
  allows the autoscaling:CreateAutoScalingGroup action`.
- **~13:55** — Root cause 1 found: `aws_autoscaling_group`'s `tag {}` block
  scheme doesn't inherit the provider's `default_tags` (unlike nearly every
  other resource type in this project). The ASG had no `Layer` tag, so the
  `ASGCreate` statement's `aws:RequestTag/Layer` condition could never be
  satisfied. Fixed (PR #48): explicit `tag {}` blocks added for
  `Project`/`Environment`/`Layer`/`ManagedBy`.
- **~14:04** — Retry. New error: `AccessDenied: You are not authorized to
  use launch template: lt-0dd28f7f5404156a9`. Root cause 2 found:
  `autoscaling:CreateAutoScalingGroup` also requires `ec2:RunInstances` —
  Auto Scaling performs the equivalent of a `RunInstances` call internally
  to launch the group's instances. Fixed (PR #49): `ec2:RunInstances`
  granted, initially scoped via the `ec2:LaunchTemplate`/
  `ec2:IsLaunchTemplateResource` condition keys (AWS's documented pattern
  for restricting to one launch template).
- **~14:13** — Retry fails differently: `LimitExceeded: Cannot exceed quota
  for PolicySize: 6144` on the policy update itself — the new statement
  pushed `ce-capstone-bouncer-dev-deploy-compute` over IAM's managed-policy
  size quota (see Incident Report 0016 for the size-quota side of this).
  Consolidated the new grant into one statement (PR #50) to reclaim budget;
  policy update succeeds, but the *same* "not authorized to use launch
  template" error persists on the ASG create.
- **~14:20** — Multiple retries of the identical conditioned grant produce
  the identical error. Propagation delay, an IAM permissions boundary on
  the deploy role, and an AWS Organizations SCP all checked and ruled out.
  Root cause 3 found via AWS's EC2 Auto Scaling service-authorization
  reference: `autoscaling:CreateAutoScalingGroup` does not support the
  `ec2:LaunchTemplate`/`ec2:IsLaunchTemplateResource` condition keys at
  all — they only populate on a *direct* `ec2:RunInstances`/`CreateFleet`
  call, not on the internal check `CreateAutoScalingGroup` performs. Fixed
  (PR #51): dropped the condition, `ec2:RunInstances` unconditioned on
  `Resource: "*"`, matching AWS's own primary documented example for this
  scenario (see ADR 0010).
- **~14:39** — Retry: identical error persists a fourth time, still with
  `ec2:RunInstances` granted unconditioned. Root cause 4 found: the launch
  template has a `tag_specifications` block (tags the `Name` on launch),
  and tagging on launch also requires `ec2:CreateTags` — a missing grant
  here produces the *identical* generic "not authorized to use launch
  template" error text as a missing `RunInstances` grant, making the two
  causes indistinguishable from the error message alone. Fixed (PR #52
  scope, folded into the same statement): `ec2:CreateTags` added alongside
  `ec2:RunInstances`.
- **~14:43** — Retry: the ASG itself finally creates successfully (no more
  "not authorized" error). New failure, much later in the apply (1m51s vs.
  the near-instant prior failures): `waiting for Auto Scaling Group ...
  capacity satisfied: ... AccessDenied ... elasticloadbalancing:DescribeTargetHealth`.
  Root cause 5: Terraform's post-create wait-for-capacity step polls
  target-group instance health, needing a plain read/poll action never
  previously granted. Fixed: `elasticloadbalancing:DescribeTargetHealth`
  added to the existing `ReadOnly` statement.
- **~14:50** — Final apply succeeds end to end. Verified live: `/health`
  returns `200`, and repeated `curl` against the ALB rotates across three
  distinct real instance IDs (`i-090517fefa26fc911`, `i-02d1b86ca2d513c33`,
  `i-0765dc79ced0e6cf0`) — confirms genuine load balancing, not just a
  clean `terraform apply`.

## Root Cause

Five independent, previously-unexercised write-path permission gaps,
compounding:

1. `aws_autoscaling_group`'s `tag {}` scheme doesn't inherit `default_tags`.
2. `autoscaling:CreateAutoScalingGroup` requires `ec2:RunInstances`
   separately — not documented anywhere in the Auto Scaling action's own
   description.
3. The `ec2:LaunchTemplate`/`ec2:IsLaunchTemplateResource` condition keys
   don't apply to the `CreateAutoScalingGroup` call path at all, despite
   being AWS's own documented pattern for exactly this use case.
4. `ec2:CreateTags` is required whenever the launch template tags on
   launch, and its absence is indistinguishable from a missing
   `RunInstances` grant by error message alone.
5. `elasticloadbalancing:DescribeTargetHealth` was needed for Terraform's
   own post-create verification step, not for anything AWS's Auto Scaling
   API itself does.

All five are instances of this project's recurring "looks scopeable, isn't"
IAM pattern (see `00-shared-context.md`'s "CI/CD auth facts," cases 8–12) —
each one only surfaces on the first real *write* through the deploy role,
never on a `plan` (read-only) or on an apply that resolves to 0 changes.

## Resolution

All five gaps fixed and verified against the real OIDC-assumed deploy role
(never against broader local admin credentials, per this project's standing
verification rule). Final state of `ce-capstone-bouncer-dev-deploy-compute`:
`ec2:RunInstances` + `ec2:CreateTags` unconditioned on `Resource: "*"` (see
ADR 0010 for the trade-off this accepts), plus
`elasticloadbalancing:DescribeTargetHealth` added to the existing read-only
statement.

## Prevention / Follow-up

- Data-tier's own first real write-path apply (RDS/ElastiCache create
  through the deploy role) is flagged as an open risk in
  `00-shared-context.md` — expect a similar class of gap, budget time for
  an iterative fix-and-retry cycle rather than assuming a clean first pass.
- When a generic AWS "not authorized" error persists across multiple
  seemingly-correct policy fixes, reach for `aws iam
  simulate-principal-policy` and the service's own
  service-authorization-reference condition-key table *before* continuing
  to iterate on the policy — both cut through this incident's most
  time-consuming loop (repeatedly re-testing a condition that could never
  have worked).