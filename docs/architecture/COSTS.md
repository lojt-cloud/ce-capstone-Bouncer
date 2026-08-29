## NAT Gateway

`eu-central-1`: ~$0.052/hour (~$38/month if left running continuously)
plus ~$0.052/GB processed. Gated behind `enable_billable_resources`.
Set to `false` and re-apply to tear it down when not actively working; 
set back to `true` and re-apply to bring it up for a demo.