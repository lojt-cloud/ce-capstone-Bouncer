# ADR 0006: Deploy-compute policy resource ARNs built from naming convention, not module outputs

## Status
Accepted

## Context
`ce-capstone-bouncer-dev-deploy-compute` scopes ASG/ALB/target-group/
listener permissions to specific resource ARNs, following ADR 0002's
pattern. The obvious source is `module.compute`'s own outputs (`asg_arn`,
`alb_arn`, etc.) — except those are wrapped in `try(...[0]..., null)`,
gated behind `enable_billable_resources`. When that flag is `false`, the
outputs are `null`, and a policy built directly from them would fail to
plan on every toggle-off — exactly the state this environment sits in
between work sessions.

## Decision
Build the ASG and ALB names in the policy from the same naming-convention
locals the modules use to name those resources, not from `module.compute`
outputs. The policy stays valid and plannable regardless of whether the
underlying resources currently exist.

## Consequences
The policy's scoping now depends on the naming convention staying in sync
with what the compute module actually creates, rather than being
mechanically guaranteed via the module's own output. A future rename of
the ASG/ALB without updating this policy would silently mis-scope it
rather than error. Acceptable here since the naming convention is a
locked project convention, not expected to change casually.