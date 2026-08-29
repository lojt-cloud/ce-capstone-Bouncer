# ADR 0002: Deploy-Role Permissions Built Incrementally, Per Layer

Date: 2026-08-29
Status: Accepted

## Context
`ce-capstone-bouncer-deploy` was created with zero permissions, on purpose . 
Working out its real least-privilege policy was left for each layer's own iam work,
once that layer's actual resource plan exists, rather than guessing a broad policy upfront before compute/data-tier/etc. exist.

## Decision
Each layer attaches its own scoped IAM policy to the deploy role, covering
only the resource types that layer's Terraform creates. 
Foundation attaches `<name_prefix>-deploy-foundation` (VPC/subnet/IGW/NAT/route-table/
security-group management, IAM role/instance-profile/policy management
scoped to the project's naming prefix, tag-conditioned `iam:PassRole`, and
S3 access scoped to its own state-file prefix). Compute, data-tier, and
later layers attach their own additional policy the same way.

## Consequences
- By the time the CI/CD module wires up GitHub Actions, the deploy role
already has exactly the permissions accumulated from every layer built
so far. No separate broad policy to write or audit later.

- Many EC2 networking actions don't support resource-level ARN scoping in
IAM (an AWS API limitation) for those statements use `Resource: "*"`; IAM
and S3 statements are ARN-scoped since those services support it.

- Each layer's policy is named `<name_prefix>-deploy-<layer>`, so it's
independently identifiable and removable if a layer is ever torn down for good.