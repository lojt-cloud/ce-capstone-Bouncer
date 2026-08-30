## Security groups

Four tiers, each only accepting traffic from the tier directly in front of
it:

- **alb-sg**: inbound 80/443 from `0.0.0.0/0` (the public entry point, by
  design). Outbound restricted to the app tier's port only, not "allow
  all" — the ALB has no other reason to originate traffic.

- **app-sg**: inbound on the app port from `alb-sg` only. No direct
  internet ingress, no SSH (SSM Session Manager only, no key pairs, no
  bastion). Outbound: 443 to the internet via NAT (SSM, packages,
  external APIs), plus the DB and cache ports scoped to `db-sg`/`cache-sg`.

- **db-sg**: inbound on the DB port from `app-sg` only. No egress rules.
  RDS never initiates outbound connections this SG would need to permit.

- **cache-sg**: inbound on the Redis port from `app-sg` only. Same
  reasoning as db-sg, no egress rules.

- **Default VPC security group**: locked down to zero ingress/zero
  egress via a dedicated `aws_default_security_group` resource — nothing
  should ever rely on the implicit default SG, so it's explicitly emptied
  rather than left with its permissive out-of-the-box rules. Confirmed
  empty via `aws ec2 describe-security-groups` (`In: []`, `Out: []`).
  Checkov's `CKV2_AWS_12` still flags this as failing — its static graph
  can't trace the resource across the networking/security module
  boundary — permanently skipped in `.checkov.yaml` with that reasoning,
  not a real gap.

`alb-sg` and `app-sg` reference each other, which would create a
dependency cycle with inline security group rules. They are declared as
standalone `aws_vpc_security_group_ingress_rule`/`_egress_rule` resources
instead, so the security groups themselves have no dependency on each
other.

DB port defaults to 5432 (PostgreSQL) pending the data-tier module's actual engine choice
once decided later.

Public subnets do not auto-assign public IPs (`map_public_ip_on_launch =
false`). Nothing launched there needs it: the NAT Gateway has its own
explicit EIP, and an internet-facing ALB gets public IPs on its nodes
regardless of subnet-level settings.

## IAM

**App instance role** (`*-app-role`, instance profile `*-app-profile`):
`AmazonSSMManagedInstanceCore` (ties to the no-SSH/SSM-only management
decision above) and `CloudWatchAgentServerPolicy` (baseline metrics/log
shipping). No S3, Secrets Manager, or RDS access yet. Those get added by
the modules that actually create those resources, scoped to the specific
ARNs they own.

**Deploy role permissions.** `ce-capstone-bouncer-deploy` started with
zero permissions. Each layer attaches its own scoped policy covering only
what it creates, to the *same* shared role — see ADR 0002, and the
blast-radius note below. Foundation's current slice:

- VPC/subnet/IGW/NAT/route-table/security-group management, mostly
  ARN-scoped to `ce-capstone-bouncer-*` and tag-conditioned
  (`aws:RequestTag`/`aws:ResourceTag`) on create/manage actions.
- A documented, individually-reviewed set of actions that stay
  `Resource: "*"` because AWS has no resource-level or tag-condition
  support for them at all: `DeleteVpc`, `ModifyVpcAttribute`,
  `ModifySubnetAttribute`, `ReleaseAddress`, `DetachInternetGateway`,
  `DisassociateRouteTable`, `ReplaceRoute`,
  `ReplaceRouteTableAssociation`, and all `Describe*` actions. Confirmed
  action-by-action against the AWS IAM reference, not assumed.
- IAM role/instance-profile/policy management scoped to
  `ce-capstone-bouncer-*` ARNs, including `iam:GetPolicy`/
  `iam:GetPolicyVersion` — easy to omit these plain-read actions when
  scoping a policy around "what can this role change," but Terraform
  needs them just to refresh state on every plan.
- CloudWatch Logs group management for the VPC flow log, plus a
  standalone `logs:DescribeLogGroups` statement at `Resource: "*"` —
  another listing action with no resource-level scoping support.
- `iam:PassRole` scoped to the `ce-capstone-bouncer-*` prefix, conditioned
  on `iam:PassedToService` being `ec2.amazonaws.com` or
  `vpc-flow-logs.amazonaws.com`.
- S3 read/write/list scoped to the `dev/foundation/` prefix of the state
  bucket only.

**Open item, not yet resolved:** `RevokeSecurityGroupIngress`/
`RevokeSecurityGroupEgress` may or may not support `aws:ResourceTag`
conditions — AWS's own documentation is ambiguous versus `Authorize*`. If
a future apply throws `AccessDenied` on a security-group-rule revoke
specifically, that condition is the first thing to strip.

**Known limitation — credential blast radius.** State is layered per
module (ADR 0001), which contains blast radius at the *state* level: a
mistake applying compute cannot touch resources tracked in Foundation's
state, full stop. It does **not** currently contain blast radius at the
*credential* level — every layer attaches its policy to the same shared
`ce-capstone-bouncer-deploy` role, so any workflow run assuming that role
gets the union of every layer's currently-granted permissions, not just
the slice relevant to whichever layer triggered it. A production
environment with more than one contributor should split this into one
role per layer instead, trading one OIDC trust relationship for N in
exchange for real credential-level isolation. Not built here — solo
capstone, one contributor, the operational overhead didn't pay for itself
— but worth being explicit this is a deliberate scope cut, not an
oversight.

## CI/CD authentication (OIDC)

GitHub Actions authenticates to AWS via OIDC federation — no long-lived
AWS access keys stored as GitHub secrets. Each workflow run gets a
short-lived, per-run token from GitHub, which AWS exchanges for temporary
credentials only if the token's claims satisfy the deploy role's trust
policy conditions.

The trust policy uses GitHub's **immutable subject claim** format —
`repo:lojt-cloud@<owner-id>/ce-capstone-Bouncer@<repo-id>:...` — the
default for any repository created after July 15, 2026 (this one
qualifies). It embeds the org's and repo's permanent numeric IDs in the
token instead of their plain names, closing a real vulnerability: without
it, an attacker could rename or recycle a repository name to match an old
trust policy and impersonate a previously-trusted identity. If this
role's trust policy — or a new one — ever needs rebuilding, use the
immutable format; the plain-name format will silently never match and
produces a generic `Not authorized to perform sts:AssumeRoleWithWebIdentity`
with no indication why it failed.

## Logging & audit

**VPC Flow Logs**: enabled on the VPC, `ALL` traffic, delivered to a
dedicated CloudWatch Logs group via its own IAM delivery role — nothing
else uses that role. Two Checkov findings came up when this was added,
decided independently rather than by blanket rule:

- **Retention** (`CKV_AWS_338`, wants ≥1 year): fixed, bumped from 14 to
  365 days. CloudWatch Logs storage cost scales with data volume, and
  this VPC's traffic is low enough that the cost difference is
  negligible — no real trade-off here, just fix it.
- **KMS encryption** (`CKV_AWS_158`, wants a customer-managed key):
  skipped. Default AWS-managed encryption already covers data at rest; a
  CMK adds key rotation/access control but costs ~$1/month forever for
  one log group with no compliance mandate driving the need — not worth
  it at this scale. Documented as a production consideration in
  `.checkov.yaml`, not built now.

Dashboards, Insights queries, and alerting on top of this log data are
`06-observability-cost`'s scope, not built here — Foundation owns the log
source only.

## Checkov

Policy as code (Checkov). Every PR scans the full `terraform/` tree with
Checkov's built-in AWS ruleset via `terraform-plan.yml`. This module wires
the tool only; custom policies are the separate Excellence-requirement
scope owned by the observability/cost module.

No baseline file — every known finding is either genuinely fixed or a
permanent, justified entry in `.checkov.yaml`'s `skip-check` list, each
with an inline comment explaining why. Three categories of skip, no bare
suppressions:

- **Intentional design** — e.g. the ALB accepting port 80 from
  `0.0.0.0/0`; it's a public entry point, that's the point.
- **Checkov limitations / false positives** — e.g. NAT Gateway EIPs
  (checkov only recognizes EC2-attached EIPs) and cross-module resource
  tracing (security-group attachment across layered state, and the
  default-SG lockdown across the networking/security module boundary —
  both confirmed live-correct via AWS CLI, not just assumed).
- **Reviewed, confirmed-unavoidable AWS constraints** — the IAM wildcard
  actions listed under Deploy role permissions above.

Any *new* finding a future PR introduces fails the build and blocks
merge — not because a baseline says so, since there isn't one, but
because it genuinely isn't accepted yet.