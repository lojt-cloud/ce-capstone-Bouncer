## NAT Gateway

`eu-central-1`: ~$0.052/hour (~$38/month if left running continuously)
plus ~$0.052/GB processed. Gated behind `enable_billable_resources`.
Set to `false` and re-apply to tear it down when not actively working; 
set back to `true` and re-apply to bring it up for a demo.

## Compute layer

New always-on cost from this module: the ALB (~€16-20/mo while running,
plus per-LCU charges under load) and 3x t3.micro EC2 instances
(on-demand, minute-billed). Both are gated behind
`enable_billable_resources` — set it false and re-apply the compute
layer to tear them down between work sessions; the launch template, S3
artifact bucket, IAM policy, and CloudWatch log group all stay (no
meaningful cost), so re-enabling rebuilds fast. The app-artifact S3
bucket and its CloudWatch log group (365-day retention) are negligible
at this data volume.

## Data Tier

New always-on cost from this module (while `enable_billable_resources = true`):
one `db.t4g.micro` RDS PostgreSQL instance, Single-AZ, roughly $0.016-0.02/hr
(~€12-15/mo -- Frankfurt pricing runs a bit above the us-east-1 baseline most
calculators quote) plus 20GB gp2 storage (~€2/mo, or free if this account
still has classic RDS Free Tier hours -- check the Billing console's Free
Tier page rather than assume). Gated behind `enable_billable_resources`,
same convention as the NAT Gateway (Foundation) and ASG/ALB (Compute).

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
`automatic_failover_enabled = false`), roughly the same per-hour rate as the
RDS instance (~$0.016-0.02/hr, ~€12-15/mo). Gated behind the same
`enable_billable_resources` flag as the RDS instance -- one toggle covers
this whole layer. Losing this node on toggle-off has zero consequence: it
holds only login-lockout counters and session tokens, both ephemeral by
design, no data of record to protect.