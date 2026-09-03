## Cost model

This document separates two numbers:

1. **Steady-state projection** — what the environment costs when all billable resources run continuously for a full month, before Free Tier or account credits.
2. **Actual project spend** — what this account may pay after Free Tier, credits, and the project's on/off lifecycle are applied.

The steady-state number is the useful safety baseline. The project should not size its budget around a temporary Free Tier or credit balance.

All figures below are for `eu-central-1` and are approximate. AWS bills by actual usage, and several services have usage-based components beyond the fixed hourly or monthly charge.

## What costs money

### Foundation

**NAT Gateway**

- Approximately `$0.052/hour`.
- Approximately `$38.22/month` if left running continuously.
- Additional processing charge: approximately `$0.052/GB`.
- Controlled by `enable_billable_resources`.

The NAT Gateway is one of the most expensive single resources in this capstone. Turning it off between work sessions is therefore important.

### Compute

**Application Load Balancer**

- Approximately `$0.027/hour` in this project.
- Approximately `$19.71/month` for the hourly component alone.
- LCU usage is billed separately at approximately `$0.008/LCU-hour`.
- The project traffic is low, so the LCU component is expected to stay small.
- Controlled by `enable_billable_resources`.

AWS documents ALB pricing as an hourly load-balancer charge plus LCU usage. citeturn131504search2turn131504search5

**EC2**

- 3 × `t3.micro` application instances at approximately `$0.012/hour` each.
- Approximately `$26.28/month` for three instances running continuously.
- Controlled by `enable_billable_resources`.

The launch template, IAM configuration, artifact bucket, and related configuration remain when the compute instances are destroyed. The running EC2 instances are the main compute-hour charge.

### Data tier

**Amazon RDS for PostgreSQL**

- `db.t4g.micro`, Single-AZ.
- Approximately `$0.019/hour` for the instance.
- 20 GB gp2 storage at approximately `$0.137/GB-month`.
- Projected total: approximately `$16.61/month`.
- Controlled by `enable_billable_resources`.

The RDS instance is intentionally Single-AZ to keep this capstone within budget. Destroying the data tier also destroys the database because `skip_final_snapshot = true` and deletion protection is disabled. AWS documents Single-AZ and Multi-AZ as separate deployment and pricing choices. citeturn131504search6

**ElastiCache Redis**

- `cache.t4g.micro`, single node.
- Approximately `$0.018/hour`.
- Approximately `$13.14/month` when running continuously.
- No replica or automatic failover.
- Controlled by `enable_billable_resources`.

Redis is used for ephemeral application state: login lockout counters, sessions, and the application purchase rate limiter. Losing the node during teardown is therefore acceptable for this capstone.

## Always-on or low-cost resources

These are not the main cost drivers, but they still belong in the model.

| Resource        | Approximate monthly cost | Notes |

| AWS WAF         | `$8` + request charges | `$5` web ACL + `$1` for each of the 3 rules/rule groups; request charges are usage based |
| CloudWatch      | `~$6`                  | Mixed estimate for alarms, logs, and custom metrics; this is the least precise estimate |
| KMS             | `$1`                   | One customer-managed key for the encrypted alerts topic |
| Secrets Manager | `$0.80`                | Two secrets at `$0.40` each, plus API-call charges |
| Route 53        | `~$0.50`               | One hosted zone; query charges are usage based |
| S3              | `<$0.10`               | Terraform state and application artifact storage; low volume |
| ACM             | `$0`                   | Public ACM certificate |
| AWS Budgets     | `$0`                   | Cost-budget monitoring and notifications are free |

AWS currently lists WAF at `$5/month` per Web ACL, `$1/month` per rule or managed rule group, and `$0.60` per million requests. citeturn873590search1

Route 53 lists the first 25 hosted zones at `$0.50` per hosted zone per month. citeturn873590search3

Secrets Manager is priced at `$0.40` per secret per month, plus API-call charges. citeturn873590search4

A customer-managed KMS key costs `$1/month`, prorated hourly. citeturn873590search0

AWS Budgets provides cost-budget monitoring and notifications free of charge. Action-enabled budgets have separate pricing after the first two, but this project does not use budget actions. citeturn131504search1

## Steady-state monthly projection

This is the project's planning number: all main resources running continuously for a full month, with no Free Tier or account credits applied.

| Resource | Projected monthly cost |

| NAT Gateway                     | `~$38.22` |
| EC2 (3 × `t3.micro`)            | `$26.28` |
| ALB                             | `~$20.21` |
| RDS (`db.t4g.micro` + 20 GB gp2)| `$16.61` |
| ElastiCache (`cache.t4g.micro`) | `$13.14` |
| AWS WAF                         | `~$8.00` |
| CloudWatch                      | `~$6.00` |
| KMS                             | `$1.00` |
| Secrets Manager                 | `$0.80` |
| Route 53                        | `~$0.55` |
| S3                              | `~$0.05` |
| ACM / AWS Budgets               | `$0` |
| **Estimated total**             | **`~$130.86/month`** |

The ALB figure includes the projected hourly component plus a small allowance for the project's low LCU usage. Actual ALB cost varies with traffic because AWS bills hourly usage and LCUs separately. citeturn131504search2turn131504search5

## Free Tier and account credits

The project has used AWS Free Tier benefits and account credits during development. Those reduce near-term charges but are not part of the `$130.86` planning number.

The account's current project notes record:

- standard 12-month Free Tier availability through **November 25, 2026** for eligible services;
- approximately **$113 of AWS credit** at the time this cost model was written.

The EC2/RDS Free Tier impact was not line-item verified during the last check, so it should be treated as a likely temporary reduction rather than a guaranteed saving.

AWS documents Free Tier coverage for eligible RDS Single-AZ usage and notes that Free Tier eligibility depends on the account and service terms. citeturn131504search6turn131504search3

## Cost control: the billable-resource toggle

The Terraform variable `enable_billable_resources` is used to turn the main billable infrastructure on and off.

The lifecycle is:

```text
true  -> resources created and the demo environment runs
false -> billable resources destroyed between work sessions
```

The toggle covers the main running costs in Foundation, Compute, and Data Tier. Observability resources are intentionally outside this toggle so alerts and drift-related infrastructure can remain available.

The most important cost-saving action is therefore simple: **do not leave the demo environment running when it is not being used.**

The teardown is destructive for RDS and Redis. RDS data is deleted when the data tier is torn down; the application schema is recreated automatically on the next app boot, while test data must be reseeded.

## Budget guardrail

A real Terraform-managed AWS Budget is live:

- Budget name: `ce-capstone-bouncer-dev-monthly`
- Limit: **`$150/month`**
- Scope: project tag `Project=ce-capstone-bouncer`
- Notifications: **50% / 80% / 100% ACTUAL spend**
- Notification delivery: existing observability SNS topic

The `$150` limit is intentionally above the `$130.86` steady-state projection. That gives the project some headroom if resources are accidentally left running or usage is higher than expected.

The budget was live-fire tested on **2026-09-03**. The threshold was temporarily reduced to `$1`; the notification thresholds entered `ALARM` and the alert emails arrived. The budget was then restored to `$150`.

AWS Budgets updates budget status several times per day, so it should be treated as a guardrail rather than a second-by-second spend monitor. citeturn131504search10

## What is not included in the projection

The `$130.86` figure is a practical project estimate, not an AWS bill guarantee. It does not attempt to predict every usage-based charge.

Examples include:

- NAT Gateway data processing above the small test volume assumed here.
- ALB LCU usage above the low-traffic assumption.
- WAF request volume above the low-traffic assumption.
- Route 53 query volume above the small project workload.
- CloudWatch log ingestion and custom-metric volume above the current estimate.
- Data transfer patterns that exceed the assumptions in the table.
- Taxes or other account-specific billing adjustments.

Where the exact usage is not measured, this document labels the value as an estimate rather than presenting it as an exact bill.

## Production cost changes

A production deployment would cost more because this capstone deliberately chooses small, inexpensive configurations.

The biggest likely changes are:

- Multi-AZ RDS instead of Single-AZ.
- Redis replication and automatic failover instead of a single node.
- More than three application instances when demand requires it.
- Higher observability volume and retention.
- Potentially higher WAF, ALB, NAT, and data-transfer usage.

Those are availability and scale decisions, not savings opportunities.
