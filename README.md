# Bouncer

Bouncer is a Cloud Engineering capstone: a small event-ticketing application running on AWS with infrastructure, security, CI/CD, and cost controls built around it.

The application supports login, sessions, ticket purchase, rate limiting, and one-ticket-per-user enforcement. The main focus of the project is the AWS infrastructure and the engineering decisions around it.

**Live:** https://app.projectbouncer.org

## What is being demonstrated

| Area                  | Implementation |

| Architecture          | Route53 → WAF → ALB → EC2 Auto Scaling Group → RDS PostgreSQL + ElastiCache Redis |
| Network               | One VPC across 3 AZs, with public and private subnets |
| Infrastructure as Code| Terraform with separate `foundation`, `data-tier`, `compute`, and `observability` states |
| CI/CD                 | GitHub Actions with AWS OIDC, Terraform plan on PRs and apply on `main` |
| Policy as Code        | Checkov on every PR |
| Security              | Private app/data tiers, security groups, TLS, WAF, Secrets Manager, bcrypt, Redis-backed sessions and rate limiting |
| Observability         | CloudWatch dashboard, alarms, VPC Flow Logs, SNS email alerts, and nightly Terraform drift detection |
| Cost control          | Single NAT Gateway, small instance sizes, Single-AZ RDS, AWS Budget alerts, and a billable-resource toggle |
| Operations            | Tested teardown, bring-up, and database reseeding scripts |

## Architecture

```text
Internet
   |
Route53
   |
WAF
   |
ALB
   |
Auto Scaling Group
(EC2, private subnets, 3 AZs)
   |
   +---- RDS PostgreSQL
   |
   +---- ElastiCache Redis

The application runs on three EC2 instances at the normal desired capacity.

RDS is PostgreSQL 17 in a private subnet and is currently Single-AZ.

Redis is a single cache.t4g.micro node and is used for session state, login lockout counters, and the /buy rate limiter.

The full architecture and design trade-offs are documented in ARCHITECTURE.md.

## Application endpoints

POST /login — authenticate with bcrypt and create a secure session cookie.
GET /me — return the current authenticated user.
POST /buy — buy the seeded event ticket.
GET /health — application health check used by the ALB.

The purchase path has two layers of protection:

PostgreSQL enforces UNIQUE (event_id, user_id).
Redis-backed rate limiting protects the /buy endpoint.

## Current verification

The live environment has been tested through a complete infrastructure cycle.

Full teardown completed successfully after handling an AWS NAT Gateway/EIP deletion race.
Full bring-up recreated the environment and reached 3/3 healthy ALB targets.
RDS was recreated from scratch.
The application schema was restored after fixing a regression in app/src/schema.sql.
Test-user reseeding succeeded through SSM.
HTTPS login returned 200.
Session validation through /me returned 200.
First ticket purchase returned 201.
A duplicate purchase returned 409.
Excessive /buy requests were blocked with 429 by the WAF rate limit.
Terraform plans report no changes on the current environment.

## Repository structure

terraform/
  environments/dev/
    foundation/
    data-tier/
    compute/
    observability/
  modules/

app/
  src/
  deploy.sh

scripts/
  bringup.sh
  teardown.sh
  reseed-test-user.sh

docs/
  architecture/
  decisions/
  incident-reports/

.github/workflows/

## Documentation

ARCHITECTURE.md — system architecture and design decisions
SECURITY.md — security model and defense in depth
RUNBOOK.md — operations, recovery, and lifecycle procedures
COSTS.md — cost model and budget controls
RETROSPECTIVE.md — lessons learned and production trade-offs
docs/DEEP-DIVE.md — detailed technical walkthrough

The repository also contains ADRs in docs/decisions/ and incident reports in docs/incident-reports/.

## Cost control

Billable resources are controlled through:

enable_billable_resources

The value is stored in each environment's committed dev.auto.tfvars file.

scripts/teardown.sh disables the billable layers.

scripts/bringup.sh recreates them in dependency order.

RDS and Redis are destroyed during a full teardown, so database row data must be reseeded after the next bring-up.

See RUNBOOK.md and COSTS.md.

## Main technology

Terraform 1.16 · AWS · EC2 · ALB · RDS PostgreSQL 17 · ElastiCache Redis 7.1 · Route53 · ACM · WAF · Secrets Manager · CloudWatch · SNS · AWS Budgets · GitHub Actions · Checkov · Flask · Gunicorn