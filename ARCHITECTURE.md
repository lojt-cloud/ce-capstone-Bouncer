## Network design

**VPC and subnet layout.**
A dedicated VPC (`10.0.0.0/16`) spans 3 AZs in
`eu-central-1` (`eu-central-1a/b/c`), chosen to match the ASG's minimum of
3 instances. One AZ per instance at minimum scale. Each AZ gets one
public subnet (`/24`, ALB and NAT Gateway) and one private subnet (`/24`,
app instances, RDS, ElastiCache). The CIDR avoids overlapping the
account's default VPC (`172.31.0.0/16`) in `eu-central-1`, in case of
future peering or VPC endpoints.

**NAT Gateway.** 
A single shared NAT Gateway (in the first public subnet)
serves egress for all 3 private subnets, rather than one per AZ. 
Deliberate cost trade-off: 3 NAT Gateways would triple the ~$0.052/hour charge for
redundancy this capstone doesn't need. It's a single point of failure for
outbound internet access only. Inbound availability (ALB, app instances)
stays multi-AZ. Acceptable for a non-production workload. Gated behind
`enable_billable_resources` in `terraform/environments/dev/foundation` so
it can be torn down between work sessions and recreated for demos.