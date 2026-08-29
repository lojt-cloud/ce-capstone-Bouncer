## Network design

**VPC and subnet layout.** A dedicated VPC (`10.0.0.0/16`) spans 3 AZs in
`eu-central-1` (`eu-central-1a/b/c`), chosen to match the ASG's minimum of
3 instances. One AZ per instance at minimum scale. Each AZ gets one
public subnet (`/24`, ALB and NAT Gateway) and one private subnet (`/24`,
app instances, RDS, ElastiCache). The CIDR avoids overlapping the
account's default VPC (`172.31.0.0/16`) in `eu-central-1`, in case of
future peering or VPC endpoints.