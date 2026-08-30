## Security groups

Four tiers, each only accepting traffic from the tier directly in front of
it:

- **alb-sg**: 
inbound 80/443 from `0.0.0.0/0` (the public entry point, by
design). Outbound restricted to the app tier's port only, not "allow
all" — the ALB has no other reason to originate traffic.

- **app-sg**: 
inbound on the app port from `alb-sg` only. No direct
internet ingress, no SSH (SSM Session Manager only, no key pairs, no
bastion). Outbound: 443 to the internet via NAT (SSM, packages,
external APIs), plus the DB and cache ports scoped to `db-sg`/`cache-sg`.

- **db-sg**:
inbound on the DB port from `app-sg` only. No egress rules.
RDS never initiates outbound connections this SG would need to permit.

- **cache-sg**: 
inbound on the Redis port from `app-sg` only. 
Same reasoning as db-sg, no egress rules.

`alb-sg` and `app-sg` reference each other, which would create a
dependency cycle with inline security group rules. They are declared as
standalone `aws_vpc_security_group_ingress_rule`/`_egress_rule` resources
instead, so the security groups themselves have no dependency on each
other.

DB port defaults to 5432 (PostgreSQL) pending the data-tier module's actual engine choice
once decided later.

## IAM

**App instance role** 
(`*-app-role`, instance profile `*-app-profile`):
`AmazonSSMManagedInstanceCore` (ties to the no-SSH/SSM-only management
decision above) and `CloudWatchAgentServerPolicy` (baseline metrics/log
shipping). No S3, Secrets Manager, or RDS access yet. Those get added by
the modules that actually create those resources, scoped to the specific
ARNs they own.

**Deploy role permissions.** 
`ce-capstone-bouncer-deploy` started with zero permissions. 
Each layer attaches its own scoped policy covering only what it creates. 
See ADR 0002. Foundation's slice:
VPC/subnet/IGW/NAT/route-table/security-group management (unavoidably
`Resource: "*"` — EC2 doesn't support ARN scoping on these actions),
IAM role/instance-profile/policy management scoped to
`ce-capstone-bouncer-*` ARNs, `iam:PassRole` scoped to the same prefix and
conditioned on `iam:PassedToService = ec2.amazonaws.com`, and S3
read/write/list scoped to the `dev/foundation/` prefix of the state
bucket only.

## Checkov

Policy as code (Checkov). Every PR scans the full terraform/ tree with Checkov's built-in AWS ruleset. This module wires the tool only; custom policies are the separate Excellence-requirement scope owned by the observability/cost module. 
A .checkov.baseline snapshot grandfathers findings that predate this gate (e.g. the documented single-AZ RDS and single shared NAT Gateway cost trade-offs); any new finding fails the build and blocks merge. 
Suppressions beyond the baseline go in .checkov.yaml's skip-check list, each with a comment pointing to the ADR or COSTS.md section that justifies i. No bare skips.