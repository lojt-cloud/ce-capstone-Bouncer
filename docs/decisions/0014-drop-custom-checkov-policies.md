# 0014 - Drop custom Checkov policies from scope

Status: Accepted, 2026-09-02

## Context

The module brief for `06-observability-cost` named custom Checkov
policies (1-2 rules reflecting this project's own least-privilege
conventions) as the priority Excellence-requirement pick — "need 1,
targeting 2," with FinOps Dashboard scoped as a stretch/cut-first
second pick.

Base Checkov (the built-in AWS ruleset) has been wired into
`terraform-plan.yml` since the CI/CD module and is fully tuned: 273/273
checks passing, every real finding either fixed or permanently
skip-checked in `.checkov.yaml` with an inline justification. This
project's actual least-privilege posture, in practice, has come from a
different mechanism than static rule-writing: 17 confirmed
"looks scopeable, isn't" AWS IAM permission gaps, each found only by
running real Terraform plans/applies through the OIDC deploy role in
CI and fixed at the point they broke something real.

## Decision

Custom Checkov policies are dropped from scope entirely. The built-in
ruleset stands as the project's only Checkov layer, unchanged. The
FinOps Dashboard is promoted from stretch to the project's committed
Excellence pick in its place.

## Rationale

Writing 1-2 project-specific static rules on top of an already-tuned
built-in ruleset would add narrow, hand-picked coverage of whatever
pattern the rules happened to target — without addressing the actual
class of gap this project has repeatedly hit (permissions that look
correctly scoped in the policy JSON but aren't, discoverable only by
exercising the real role). That gap is real and already has a working,
proven detection mechanism (CI running under the actual deploy role);
custom Checkov rules would be a second, weaker mechanism for a
different and narrower problem.

## Trade-off accepted

No custom, project-specific policy-as-code rules exist. Anyone
reviewing this project via Checkov output alone (rather than the
CI-verified-permissions record in `00-shared-context.md`) won't see
this project's least-privilege conventions expressed as automated
checks. Compensating control: the built-in ruleset (273/273 passing)
plus the documented, repeatedly-exercised pattern of verifying every
new IAM statement against the real deploy role before calling it done.

## Consequence

FinOps Dashboard (`06-observability-cost` task 5) is no longer a
cut-first stretch item — it's required to satisfy the project's "need
1" Excellence requirement, and should be built and documented
accordingly.