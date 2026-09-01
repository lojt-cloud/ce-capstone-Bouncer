# ADR 0009: Git-track the billable-resource toggle instead of an ephemeral -var flag
## Status
Accepted
## Context
`enable_billable_resources` (Foundation, Compute, Data-tier) had been
toggled via `terraform apply -var="enable_billable_resources=false"` at
the CLI — fast, no git ceremony, matching the project's advisory
execution mode. Once `terraform-apply.yml` started running
merge-triggered applies for real (CI/CD module), this became a problem:
CI has no way to see a runtime `-var` flag that was never committed
anywhere, so it always resolves the variable's committed default.
Confirmed directly, not hypothetically: merging an unrelated CI/CD PR
(adding `terraform-apply.yml` itself) tried to auto-recreate a NAT
Gateway that had been torn down for cost the night before, because CI's
apply disagreed with local reality and "corrected" it back toward the
default.
## Decision
Each layer's `enable_billable_resources` value now lives in a committed
`dev.auto.tfvars` file (`terraform/environments/dev/<layer>/dev.auto.tfvars`),
which Terraform auto-loads with no flag needed — identically, in both a
local shell and CI's `terraform apply`/`plan` steps, since both run from
that same working directory. `teardown.sh` was rewritten to write that
file per layer instead of passing `-var`. Bringing a CI-wired layer back
up now means committing `true` in that file via a normal PR; CI's own
`terraform-apply.yml` performs the actual apply on merge.
## Consequences
Toggling a layer off/on now requires a PR (branch protection enforces
this even for the repo owner — `enforce_admins: true`) instead of a
single local command; `teardown.sh` still does the actual local applies
immediately, so a session still ends with real infrastructure down right
away, but syncing that state to git so CI agrees is now a separate,
deliberate step (commit/push/merge) rather than automatic. This adds
friction to the fastest "just tear it down for the night" path, in
exchange for CI and local state never being able to silently disagree
again — judged worth it once CI applies run unattended on every merge.
Also means the nightly toggle is now itself a real, demoable exercise of
the CI/CD pipeline, not a workaround around it.
