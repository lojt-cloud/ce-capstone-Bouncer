## NAT Gateway

`eu-central-1`: ~$0.052/hour (~$38/month if left running continuously)
plus ~$0.052/GB processed. Gated behind `enable_billable_resources`.
Set to `false` and re-apply to tear it down when not actively working; 
set back to `true` and re-apply to bring it up for a demo.

## Compute layer

New always-on cost from this module: the ALB (`$0.027/hour` +
`$0.008/LCU-hour`, confirmed via AWS's Price List API for `eu-central-1`
— ~$19.71/mo hourly alone; LCU charges are negligible at this project's
traffic volume) and 3x t3.micro EC2 instances (`$0.012/hour` each,
confirmed the same way — $26.28/mo for all 3 combined). Both are gated
behind `enable_billable_resources` — set it false and re-apply the
compute layer to tear them down between work sessions; the launch
template, S3 artifact bucket, IAM policy, and CloudWatch log group all
stay (no meaningful cost), so re-enabling rebuilds fast. The
app-artifact S3 bucket and its CloudWatch log group (365-day retention)
are negligible at this data volume.

One of the 3 EC2 instances is likely covered by the standard AWS Free
Tier (750 hrs/month of t3.micro, active on this account through
November 25, 2026) — not line-item-verified via
`aws freetier get-free-tier-usage` (that check returned no data this
pass), so treat as a probable partial offset, not a confirmed one. See
"Total Monthly Cost Projection" below for why the Free Tier doesn't
change how the Budget threshold is sized.

## Data Tier

New always-on cost from this module (while `enable_billable_resources = true`):
one `db.t4g.micro` RDS PostgreSQL instance, Single-AZ, `$0.019/hour`
confirmed via AWS's Price List API for `eu-central-1` (~$13.87/mo) plus
20GB gp2 storage at `$0.137/GB-month` confirmed the same way (~$2.74/mo;
$16.61/mo total for the instance). This account is in its standard
12-month Free Tier through November 25, 2026, which typically covers
exactly this instance type/size (750 hrs/month + 20GB gp2) — likely a
full offset for now, not line-item-verified. Gated behind
`enable_billable_resources`, same convention as the NAT Gateway
(Foundation) and ASG/ALB (Compute).

Unlike those, tearing this layer down is destructive: `skip_final_snapshot`
and no `deletion_protection` mean toggling off deletes the database and its
data, not just stops billing for it. Deliberate trade-off -- there's no real
user data to protect, and a fresh empty DB on toggle-on is simpler than
snapshot restore. The Secrets Manager secret and DB subnet group stay
always-on regardless of the toggle (negligible cost, and re-creating a
just-deleted secret hits Secrets Manager's recovery-window restriction) --
only the RDS instance itself is gated.

Storage type is gp2, not gp3 -- AWS's Free Tier documentation still names
gp2 specifically for the free 20GB; gp3 eligibility isn't confirmed, and the
price gap at this volume is under $2/mo regardless.

Adds one `cache.t4g.micro` ElastiCache Redis node (single node, no replica --
`automatic_failover_enabled = false`), `$0.018/hour` confirmed via AWS's
Price List API for `eu-central-1` (~$13.14/mo). ElastiCache is not part
of the standard AWS Free Tier program, so this cost applies regardless
of the account's Free Tier status. Gated behind the same
`enable_billable_resources` flag as the RDS instance -- one toggle
covers this whole layer. Losing this node on toggle-off has zero
consequence: it holds only login-lockout counters and session tokens,
both ephemeral by design, no data of record to protect.

## SNS
- SNS alerts CMK (aws_kms_key.sns_alerts): $1/month flat. Required because
  CloudWatch Alarms can't publish to an SNS topic encrypted with the
  AWS-managed alias/aws/sns key — that key's policy isn't editable, so a
  customer-managed key was the only way to keep the topic encrypted.

## Other always-on resources (WAF, DNS, Secrets, Logs)

Several small always-on costs from earlier modules were never itemized
here. Confirmed via AWS's own pricing pages except where noted:

- **AWS WAF** (product-security module): 1 Web ACL ($5/month) + 3 rules —
  `AWSManagedRulesKnownBadInputsRuleSet`, `RateLimitLogin`,
  `RateLimitBuy` — at $1/month each = $8/month total, plus $0.60 per
  million requests inspected (negligible at this project's traffic
  volume).
- **Route 53** (foundation/domain setup): 1 hosted zone at $0.50/month,
  plus $0.40 per million standard queries (negligible at this volume).
- **Secrets Manager** (data tier): 2 secrets (`db-credentials`,
  `cache-credentials`) at $0.40/month each = $0.80/month, plus API-call
  costs (negligible — the app reads these once per instance boot).
- **CloudWatch**: 5 alarms (the 3 this project created plus 2 AWS
  auto-creates behind the ASG's target-tracking policy) at $0.10/month
  each = $0.50/month; 1 dashboard (free — first 3 dashboards have no
  charge); Logs ingestion/storage for 2 log groups (VPC flow logs +
  app logs, both 365-day retention) at $0.50/GB ingested and
  $0.03/GB-month stored — low volume, estimated under $1/month; CWAgent
  custom metrics (mem/disk per instance) at $0.30/metric/month — **not
  measured against actual metric count**, roughly estimated at
  $4-5/month for 3 instances. CloudWatch's total (~$6/month) is the
  least precisely confirmed line in this cost model — small dollar
  impact either way, worth a real check via
  `aws cloudwatch list-metrics --namespace CWAgent` if precision ever
  matters more than it does here.
- **ACM** (public certificate): free.
- **AWS Budgets** (once built): free for cost budgets/notifications.
- **S3** (2 buckets — Terraform state, app artifacts): negligible, well
  under $0.10/month at this project's storage volume.

## Total Monthly Cost Projection

Full steady-state total — everything running continuously for a full
month, no Free Tier applied. This is the number the Budget guardrail is
sized against: a Budget should protect against the real ongoing cost,
not a temporary subsidy that expires.

| Resource                                |    (eu-central-1)         | Monthly |

| NAT Gateway                             | $0.052/hr + $0.052/GB     | ~$38.22 |
| EC2 (3x t3.micro)                       | $0.012/hr each | $26.28   |
| ALB                                     | $0.027/hr + $0.008/LCU-hr | ~$20.21 |
| RDS (db.t4g.micro Single-AZ + 20GB gp2) | $0.019/hr + $0.137/GB-mo  | $16.61 |
| ElastiCache (cache.t4g.micro)           | $0.018/hr                 | $13.14 |
| WAF                                     |  $5/mo + $1/mo/rule x3    | ~$8.00 |
| CloudWatch                              | mixed, see above          | ~$6.00 |
| KMS (1 CMK, SNS alerts)                 | $1/mo                     | $1.00 |
| Secrets Manager (2 secrets)             | $0.40/mo each             | $0.80 |
| Route 53 (1 hosted zone)                | $0.50/mo                  | $0.55 |
| S3                                      | negligible                | ~$0.05 |
| ACM, AWS Budgets                        | free                      | $0 |
| Data transfer out                       | 100GB/mo free allowance   | $0 (assumed) |
| **Total**      | | **~$130.86/month (~€120-125)** |

**Near-term actual cost is lower than this**, for two independent,
temporary reasons: this account is in its standard 12-month AWS Free
Tier through November 25, 2026 (likely covering the EC2 and RDS
instance-hour lines above — not line-item-confirmed), and it currently
holds $113 of AWS credit. Neither is baked into the steady-state figure
above, since neither is permanent — this project's
`enable_billable_resources` toggle pattern is what actually keeps real
spend well under even the discounted number, by not running
continuously between work sessions.

**Budget guardrail — built and live-fire verified, 2026-09-03**: a real
Terraform-managed AWS Budget (`ce-capstone-bouncer-dev-monthly`,
`terraform/environments/dev/observability/budget.tf`), $150/mo,
tag-scoped to `Project=ce-capstone-bouncer`, with three ACTUAL-spend
notifications at 50%/80%/100%, reusing the existing
observability-alerts SNS topic rather than standing up a second one.
Threshold set against this $130.86 steady-state figure, with headroom
for a month where resources accidentally get left running — not the
discounted near-term number, and not the previously-assumed
"~€80-90" figure, which (per the tagging-pass investigation,
2026-09-02) was never a real figure to begin with. Live-fire tested per
the module brief's requirement: temporarily lowered to $1
(`terraform apply -var="budget_monthly_limit_usd=1"`), confirmed all
three notification thresholds tripped to `ALARM` and real alert emails
arrived, then restored to $150 with a plain `terraform apply`. See
`00-shared-context.md`'s Observability module output for the full build
writeup (KMS key policy grant, new SNS topic policy, IAM statements).
