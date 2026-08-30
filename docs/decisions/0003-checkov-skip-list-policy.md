# ADR 0003: Checkov skip-list policy

**Status:** Accepted — 2026-08-30

## Context

`terraform-plan.yml` now runs Checkov's built-in AWS ruleset against the
full `terraform/` tree on every PR (`.checkov.yaml`, repo root, no
baseline file). Some findings are legitimate false positives — Checkov's
static analysis can't trace a resource across the module boundary between
the networking and security-group modules, which hits `CKV2_AWS_5` and
`CKV2_AWS_12` even though the real resources are correctly configured.
Others are deliberate, already-documented cost/trade-off calls (e.g. no
customer-managed KMS key on the VPC Flow Logs log group — not worth the
ongoing ~$1/mo at this scale). Without a rule for how skips are recorded,
it's easy for a skip list to quietly become a way to wave through real
findings instead of a record of considered trade-offs.

## Decision

Every skipped check is skip-checked in `.checkov.yaml` with a required
inline comment explaining why — false positive (name the specific
cross-module tracing limitation) or deliberate trade-off (name the
trade-off and where it's documented, e.g. `COSTS.md`). Raw CLI suppression
flags (`--skip-check` passed directly in the workflow, not recorded in the
file) are not used — CI only reads `.checkov.yaml`, so anything not
recorded there doesn't propagate and isn't a real, auditable skip.

When a new module's Terraform trips a *new* finding: fix it if practical.
If it's a genuine trade-off or confirmed false positive, add it to
`skip-check` in `.checkov.yaml` with the same inline-comment convention —
don't suppress it any other way.

## Consequences

- The skip list is self-documenting and auditable directly in the repo —
  anyone reviewing a PR can see exactly what's skipped and why, without
  digging through workflow YAML or chat history.
- Slightly more overhead per skip (writing the justification), which is
  the point: it forces a deliberate, recorded call each time rather than a
  rubber-stamp suppression.
- `CKV2_AWS_5` and `CKV2_AWS_12` are permanently skipped for the same
  underlying reason (cross-module resource tracing) — if a future module
  hits the same pattern, that's expected, not a regression.