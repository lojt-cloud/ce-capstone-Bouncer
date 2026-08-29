# ADR 0001: Terraform State Layout — Layered per Module

Date: 2026-08-29
Status: Accepted

## Context
The rubric's required structure names `main.tf`, `variables.tf`, `outputs.tf`,
`backend.tf`, a `modules/` folder, and `environments/{dev,prod}` under
`terraform/`. The build is split across separate work sessions (Foundation,
Compute, Data-tier, CI/CD, ...), and the Foundation brief specifies that
later sessions "read [Foundation's outputs] via a remote state data source" 
Implying separate state per session rather than one shared state.

## Decision
Each module/session gets its own Terraform root and state file, under
`terraform/environments/<env>/<layer>/` (e.g. `terraform/environments/dev/foundation/`),
each with its own `main.tf`, `variables.tf`, `outputs.tf`, `backend.tf`.
Reusable resource definitions live once in `terraform/modules/<name>/`
(`modules/networking`, `modules/security`, `modules/iam`, ...) and are
called from each layer's root. A later layer reads an earlier layer's
outputs via a `terraform_remote_state` data source pointing at that
layer's state key in the shared S3 backend (bucket
`ce-capstone-bouncer-tfstate-f7fc4b65`, native S3 locking). State key
convention: `<env>/<layer>/terraform.tfstate`, e.g. `dev/foundation/terraform.tfstate`.

## Alternatives considered
A single unified root (one `main.tf` calling every module into one shared
state) is simpler to run day-to-day but means every later change re-plans
the entire stack, including networking and security groups that are
already stable. Unacceptable blast radius once compute, data-tier, and
cache layers stack on top. 

## Consequences
- Cross-layer values (VPC ID, subnet IDs, security group IDs, IAM ARNs)
  must be declared as real `output` blocks in the producing layer, since
  consuming layers read them via remote state.
- `environments/prod/` mirrors the same per-layer structure but is not
  expected to be applied for real during the capstone, given the
  free-tier budget. It exists to satisfy the rubric's environment-
  separation requirement.
- Every layer needs its own `backend.tf` pointing at a unique state key.