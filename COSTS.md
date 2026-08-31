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