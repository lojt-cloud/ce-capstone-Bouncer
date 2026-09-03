## Security groups

Four tiers, each only accepting traffic from the tier directly in front of
it:

- **alb-sg**: inbound 80/443 from `0.0.0.0/0` (the public entry point, by
  design). Outbound restricted to the app tier's port only, not "allow
  all" — the ALB has no other reason to originate traffic.

- **app-sg**: inbound on the app port (8000) from `alb-sg` only. No direct
  internet ingress, no SSH (SSM Session Manager only, no key pairs, no
  bastion). Outbound: 443 to the internet via NAT (SSM, packages,
  external APIs), plus the DB and cache ports scoped to `db-sg`/`cache-sg`.

- **db-sg**: inbound on port 5432 (PostgreSQL) from `app-sg` only. No
  egress rules. RDS never initiates outbound connections this SG would
  need to permit.

- **cache-sg**: inbound on port 6379 (Redis) from `app-sg` only. Same
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

Public subnets do not auto-assign public IPs (`map_public_ip_on_launch =
false`). Nothing launched there needs it: the NAT Gateway has its own
explicit EIP, and an internet-facing ALB gets public IPs on its nodes
regardless of subnet-level settings.

## TLS / HTTPS

The ALB terminates TLS on a 443 listener
(`ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"`) using a
DNS-validated ACM certificate for `app.projectbouncer.org`. The 80
listener 301-redirects to 443 rather than forwarding directly — there is
no path to the app that stays on cleartext HTTP, and Checkov's
`CKV2_AWS_20` (ALB HTTP→HTTPS redirect) genuinely passes rather than
needing a suppression. Session cookies are `Secure` (HTTPS-only,
flipped from `false` once the real listener existed), `HttpOnly`
(inaccessible to JavaScript, mitigates XSS-based cookie theft), and
`SameSite=Lax` (mitigates CSRF). See `ARCHITECTURE.md`'s "Domain, TLS,
and routing" section for how the certificate and DNS delegation fit
together.

## IAM

**App instance role** (`*-app-role`, instance profile `*-app-profile`):
`AmazonSSMManagedInstanceCore` (ties to the no-SSH/SSM-only management
decision above) and `CloudWatchAgentServerPolicy` (baseline metrics/log
shipping), plus narrowly scoped policies added as later modules needed
them: `s3:GetObject` on the app-artifact bucket only, and
`secretsmanager:GetSecretValue` on exactly the DB and cache credential
secrets — each its own policy, each scoped to one resource ARN, none
broader than what that specific module actually reads.

**Deploy role permissions.** `ce-capstone-bouncer-deploy` started with
zero permissions. Each of the four layers — foundation, compute,
data-tier, observability — attaches its own scoped policy covering only
what it creates, to the *same* shared role (see ADR 0002 and the
blast-radius note below), rather than each layer getting a separate
role. Two layers (compute, foundation-observability's KMS statements)
needed a second managed policy per layer after hitting IAM's
6,144-character customer-managed-policy size quota — a real, repeatedly
hit limit on this project, not a one-off; AWS's 2026 increase of the
managed-policies-per-role default quota to 20 means a second policy per
layer is now the standing pattern here rather than
continuing to hunt for statements to merge.

A documented, individually-reviewed set of actions stays `Resource: "*"`
across these policies because AWS has no resource-level or tag-condition
support for them at all — confirmed action-by-action against each
service's own IAM reference, not assumed. Examples: `DeleteVpc`,
`ModifyVpcAttribute`, `ReleaseAddress`, all `Describe*` actions,
`logs:DescribeLogGroups`, and several SNS subscription-level actions
(SNS defines no subscription IAM resource type at all).

**Open item, not yet resolved:** `RevokeSecurityGroupIngress`/
`RevokeSecurityGroupEgress` may or may not support `aws:ResourceTag`
conditions — AWS's own documentation is ambiguous versus `Authorize*`. If
a future apply throws `AccessDenied` on a security-group-rule revoke
specifically, that condition is the first thing to strip.

**Known limitation — credential blast radius.** State is layered per
module (ADR 0001), which contains blast radius at the *state* level: a
mistake applying compute cannot touch resources tracked in foundation's
state, full stop. It does **not** contain blast radius at the
*credential* level — every layer attaches its policy to the same shared
`ce-capstone-bouncer-deploy` role, so any workflow run assuming that role
gets the union of every layer's currently-granted permissions, not just
the slice relevant to whichever layer triggered it. A production
environment with more than one contributor should split this into one
role per layer instead, trading one OIDC trust relationship for N in
exchange for real credential-level isolation. Not built here — solo
capstone, one contributor, the operational overhead didn't pay for
itself — but a deliberate scope cut, not an oversight.

### Verifying least privilege: every policy proven by a real write, not just a plan

A policy that "plans clean" under `terraform plan` (a read-only
operation) is not proof it's correctly scoped — only a real `apply`
through the actual least-privilege role proves a write path works. This
project tested every layer's deploy-role policy that way: assumed the
real OIDC role (locally during development, then for real through GitHub
Actions), not personal admin credentials, for every plan *and* every
apply.

That process found 17 separate, confirmed cases where an IAM action
looked correctly scoped in the policy but wasn't — a missing plain-read
action Terraform's provider needs on every refresh
(`iam:GetPolicyVersion`, `logs:DescribeLogGroups`, a full set of S3
bucket `Get*` calls), an action with no resource-level permission support
at all despite reading as scopeable (several SNS subscription actions,
several `Describe*` actions), a create action silently requiring a
second, unrelated action alongside it
(`autoscaling:CreateAutoScalingGroup` needing `ec2:RunInstances`;
`RunInstances` with `tag_specifications` also needing `ec2:CreateTags`),
and a single action checking permission against two or three different
resource-type ARNs at once (`rds:CreateDBInstance` against both the `db:`
and `subgrp:` ARNs; `elasticache:CreateReplicationGroup` against
`replicationgroup:`, `parametergroup:`, *and* `subnetgroup:`). Every one
of these was invisible under `plan` and only surfaced the first time the
real role tried to create something it had never created before.

Each case is written up individually, in the order found, in
`docs/incident-reports/` (19 reports total — 17 of these plus 2 unrelated
process incidents). `RETROSPECTIVE.md` has the higher-level pattern this
points at.

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
  365 days. This is the retained security/audit window for VPC flow logs.
- **KMS encryption** (`CKV_AWS_158`, wants a customer-managed key):
  skipped. Default AWS-managed encryption already covers data at rest. A
  customer-managed key would add more explicit key-rotation and access
  controls, but there is no compliance requirement in this capstone that
  justifies adding that operational complexity. Documented as a production
  consideration in `.checkov.yaml`, not built now.

**WAF logs**: a separate dedicated CloudWatch log group
(`aws-waf-logs-<project>-<environment>`), `cookie` and `authorization`
headers redacted — see the WAF section below.

**Alerting**: a CloudWatch dashboard + 3 alarms (5xx rate, unhealthy
targets, RDS CPU) and an AWS Budget guardrail both publish to SNS topics
with real email delivery, confirmed by manually forcing each alarm and
lowering the budget threshold rather than trusting a "configured, not
tested" state. Full detail in `ARCHITECTURE.md`'s Observability section
and `COSTS.md`.

Dashboards, Insights queries, and alerting beyond the flow-log source
itself are `06-observability-cost`'s scope, not rebuilt in Foundation.

## Checkov

Policy as code. Every PR scans the full `terraform/` tree with Checkov's
built-in AWS ruleset via `terraform-plan.yml` — **273/273 checks
passing**. No baseline file — every known finding is either genuinely
fixed or a permanent, justified entry in `.checkov.yaml`'s `skip-check`
list, each with an inline comment explaining why. Three categories of
skip, no bare suppressions:

- **Intentional design** — e.g. the ALB accepting port 80 from
  `0.0.0.0/0` (redirected to 443, not forwarded — see TLS section above);
  it's a public entry point, that's the point.
- **Checkov limitations / false positives** — e.g. cross-module resource
  tracing (the default-SG lockdown across the networking/security module
  boundary, and the WAF web ACL association's `count`-conditioned
  resources on both sides — both confirmed live-correct via AWS CLI, not
  just assumed; the WAF case is a documented upstream Checkov limitation,
  bridgecrewio/checkov#1230).
- **Reviewed, confirmed-unavoidable AWS constraints** — the IAM wildcard
  actions listed under IAM above, plus a set of data-tier findings where
  the underlying feature is simply unsupported at this instance size
  (e.g. Performance Insights on `db.t4g.micro`/`cache.t4g.micro`).

Any *new* finding a future PR introduces fails the build and blocks
merge — not because a baseline says so, since there isn't one, but
because it genuinely isn't accepted yet.

**Custom Checkov policies were dropped from scope entirely** — see ADR 0014
(`docs/decisions/0014-drop-custom-checkov-policies.md`). The built-in
AWS ruleset above is this project's only Checkov layer.

## Compute layer

- **No SSH, no bastion.** App instances have no key pair and no public
  IP; management is exclusively via SSM Session Manager, through the
  existing `AmazonSSMManagedInstanceCore` permission on the app role.
- **IMDSv2 enforced** (`http_tokens = "required"` on the launch
  template) — the app itself only uses the token-based flow, and the
  instance metadata endpoint rejects the older no-token IMDSv1 calls
  entirely. Closes the classic SSRF-to-credential-theft path.
- **App tier has no direct internet exposure.** Instances sit in private
  subnets with no public IP, reachable only from `alb-sg` on port 8000
  (`app-sg`) — never from `0.0.0.0/0` directly.
- **Least-privilege IAM for the app-artifact bucket.** The EC2 app role
  has exactly one artifact-related permission — `s3:GetObject` on the
  compute app-artifact bucket, nothing broader — via a policy scoped to
  that bucket's ARN specifically.
- **App-artifact S3 bucket** (`ce-capstone-bouncer-dev-app-artifacts-*`):
  versioned, SSE-S3 encrypted, all public access blocked, lifecycle rule
  expiring noncurrent versions and aborting incomplete multipart uploads.
  Holds only redeployable app code, not secrets or user data.
- **HTTPS is live end to end** (see the TLS section above) — this closes
  what was originally a tracked gap; the ALB no longer serves plaintext
  application traffic at all.
- **ALB deletion protection is deliberately off** — an operational
  trade-off because the ALB is part of the intentionally disposable compute
  environment. This is not treated as a security gap.

## Data tier

RDS master credentials are generated by Terraform (`random_password`,
never a literal in `.tf`/`.tfvars`) and written to Secrets Manager as
JSON (username/password/host/port/dbname) — the app reads this secret at
boot, credentials never appear as plain environment variables. Read
access is a single scoped IAM policy (`secretsmanager:GetSecretValue` on
this one secret's ARN) attached to the shared app role, same pattern
Compute used for its S3 artifact bucket. RDS itself sits in the private
subnets with `db-sg` allowing inbound only from `app-sg` on 5432 —
confirmed via live `psql` connectivity from an app instance, TLS
(`sslmode=require`) enforced.

Redis is encrypted at rest and in transit (`transit_encryption_mode =
required`, TLS-only, no plaintext fallback) plus a generated AUTH token
in its own Secrets Manager secret — three independent layers (network via
`cache-sg`, transport via TLS, application via AUTH) even though the
security group alone already restricts access to the app tier. `cache-sg`
allows inbound only from `app-sg` on 6379, same pattern as `db-sg`.
Read/write/delete proven from a live app instance via `valkey-cli` over
TLS with AUTH.

**Authentication.** Passwords are bcrypt-hashed (`bcrypt.hashpw`/
`checkpw`), never stored or logged in plaintext. A login for a
*nonexistent* username still runs a fixed dummy bcrypt check before
returning `401`, so a failed login takes roughly the same time whether
the username exists or not — a deliberate timing-based defense against
username enumeration, not present in the original ported source.

**Account lockout.** Failed logins increment a per-username Redis
counter (`login:fail:{username}`); the 5th consecutive failure sets a
5-minute lock (`login:lock:{username}`, `SETEX`) that blocks *all*
further attempts for that username — including a correct password
submitted while locked, confirmed live (`423 LOCKED` with
`retry_after_seconds`). Because this state lives in Redis rather than
each Flask worker's memory, the lockout is consistent across every app
instance behind the ALB, not bypassable by hitting a different instance.

**Ticket-purchase defense in depth.** `/buy` is protected by three
independent layers, each with a different failure mode, verified
separately rather than assumed to overlap: the WAF's rate-based rule
(10 requests/300s per source IP, blocks before the request reaches the
app — see the WAF section below), an application-level Redis rate limiter
(`buy:attempts:{username}`, fixed window, fails *closed* on a Redis
outage so unlimited purchases are never silently allowed), and a
database-level `UNIQUE (event_id, user_id)` constraint on `tickets`
(precise, per-account, the actual mechanism preventing a duplicate
purchase from succeeding even for traffic that stays under both rate
limits). All three verified live end to end: repeat purchases return
`409`, requests over the app-level limit return `429`, and a
high-volume burst against the endpoint is blocked by the WAF at `403`.

## WAF: Log4j protection and rate limiting

An AWS WAFv2 web ACL sits in front of the ALB (`terraform/modules/compute/waf.tf`),
gated behind `enable_billable_resources` like the rest of the compute layer.

- **Log4j / JNDI protection**: the AWS-managed `AWSManagedRulesKnownBadInputsRuleSet`
  rule group blocks Log4Shell-style payloads (CVE-2021-44228) before they
  reach the app.
- **Rate limiting**: two rate-based rules, one scoped to `/login` and one to
  `/buy`, block a source IP for the remainder of AWS's evaluation window once
  it exceeds 10 requests in 5 minutes against that path. Verified live: a
  15-request burst against `/buy` returned `401` (unauthenticated, app-level)
  for the first requests, then `403` (WAF block, request never reaches the
  ALB target) once the limit was crossed. Note AWS WAF's own documented
  caveat — rate-based rules can take up to several minutes to start
  enforcing after creation or a rule change, since detection isn't
  per-request but based on a periodically-reassessed rolling window.
- **Logging**: WAF request logs go to a dedicated CloudWatch log group
  (`aws-waf-logs-<project>-<environment>`), with the `cookie` and
  `authorization` headers redacted.

**Defense in depth on `/buy`**: the rate-based WAF rule, the application-level
Redis rate limiter, and the database's unique constraint are three
independent layers protecting the same endpoint — see the Data tier
section above for the full breakdown and verification results. None
depends on the other two holding.

AWS Config was dropped from this project's scope to manage build time — see
[ADR 0012](docs/decisions/0012-drop-aws-config-from-scope.md). Checkov's
static IaC scanning (already run on every PR, see `RUNBOOK.md`'s CI/CD
section) is the compensating control for configuration drift and policy
compliance in its place; it doesn't cover runtime/drift detection the way
Config would, which is the accepted trade-off. Nightly Terraform drift
detection (see `RUNBOOK.md`) covers the infrastructure-drift half of what
Config would otherwise catch.
