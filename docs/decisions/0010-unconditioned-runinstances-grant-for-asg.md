# 10. Unconditioned ec2:RunInstances grant for ASG launch-template instances

Date: 2026-09-01

## Status

Accepted

## Context

Bringing compute's Auto Scaling Group up for the first real time through the
CI deploy role (`ce-capstone-bouncer-deploy`) — `enable_billable_resources`
had previously only ever been tested at `false` (a 0-change no-op) — required
authorizing `autoscaling:CreateAutoScalingGroup` end to end. That surfaced a
requirement not obvious from the Auto Scaling side of the API alone: AWS's
Auto Scaling service internally performs the equivalent of an `ec2:RunInstances`
call to launch the group's instances, so the calling principal needs
`ec2:RunInstances` (and, since this project's launch template has a
`tag_specifications` block, `ec2:CreateTags`) in addition to the
`autoscaling:*` actions.

Following this project's least-privilege convention, the first attempt tried
to scope `ec2:RunInstances` to exactly this account's own launch template,
using AWS's documented `ec2:LaunchTemplate` / `ec2:IsLaunchTemplateResource`
condition keys — AWS's own recommended pattern for restricting instance
launches to a specific pre-approved launch template with no overrides
(AMI, subnet, security group, etc. all locked to what the template defines).

That condition-scoped grant failed identically across multiple real applies:
`AccessDenied: You are not authorized to use launch template: lt-xxx`. Before
concluding the condition keys themselves were the problem, propagation delay,
an IAM permissions boundary on the deploy role, and an AWS Organizations SCP
were all checked and ruled out (`aws iam simulate-principal-policy` confirmed
the identity policy *did* allow `ec2:RunInstances` on the launch-template ARN;
`aws iam get-role --query 'Role.PermissionsBoundary'` returned `null`; `aws
organizations describe-organization` confirmed this account isn't in an
Organization at all). Cross-checking AWS's own EC2 Auto Scaling
service-authorization reference settled it: `autoscaling:CreateAutoScalingGroup`
does not list `ec2:LaunchTemplate` or `ec2:IsLaunchTemplateResource` among its
supported condition keys. Those two keys only populate when the authorization
check originates from a *direct* `ec2:RunInstances` or `ec2:CreateFleet` API
call — not from the internal check Auto Scaling performs when a group is
created from a launch template. Since Terraform's `aws_autoscaling_group`
resource always creates the group via `CreateAutoScalingGroup`, never a direct
`RunInstances` call, this condition-scoping approach is structurally unusable
for this project's compute layer — not a mistake in how it was written, a real
gap in what AWS's API supports here.

## Decision

Grant `ec2:RunInstances` and `ec2:CreateTags` on `Resource: "*"`, unconditioned,
in `ce-capstone-bouncer-dev-deploy-compute` — matching AWS's own primary
documented example policy for "create/update an Auto Scaling group using a
launch template." No further attempt to scope these two actions by resource
ARN or tag condition, since the condition keys that would do so don't apply
to this call path.

## Consequences

This is broader than this project's general least-privilege convention — most
other actions in `ce-capstone-bouncer-dev-deploy-compute` are scoped to
specific resource ARNs or `RequestTag`/`ResourceTag` conditions. In practice
the actual blast radius stays narrow for two reasons:

1. `ec2:RunInstances`/`ec2:CreateTags` are the only unconditioned EC2-launch
   actions in this policy. The deploy role still can't modify security
   groups, launch templates, or anything else EC2-side beyond what's
   separately (and tightly) scoped elsewhere in the same policy.
2. `autoscaling:CreateAutoScalingGroup` itself remains tightly scoped — exact
   ASG name, `aws:RequestTag/Layer` condition. The deploy role can't create
   an arbitrarily-named or arbitrarily-tagged Auto Scaling group; it can only
   ever launch instances as a side effect of creating *this one, already-scoped*
   group.

Documented here so a future review doesn't mistake the unconditioned
`Resource: "*"` for an oversight. Revisit if AWS ever adds resource-level or
condition-key support for `RunInstances`-via-`CreateAutoScalingGroup`
specifically — not supported as of the service-authorization reference
checked 2026-09-01.