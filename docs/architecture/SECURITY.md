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