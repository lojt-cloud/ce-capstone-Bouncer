# Bouncer Architecture

## 1. Overview

Bouncer is a small event-ticketing application deployed on AWS.

The application is intentionally simple. The infrastructure is the main part of the capstone.

The system demonstrates:

- multi-AZ networking
- private application and data tiers
- Infrastructure as Code with Terraform
- GitHub Actions with AWS OIDC
- policy-as-code with Checkov
- TLS and WAF protection
- centralized session and rate-limit state in Redis
- encrypted PostgreSQL data
- CloudWatch monitoring and alerting
- Terraform drift detection
- explicit cost controls

The live application is:

`https://app.projectbouncer.org`

The normal application path is:

```text
Internet
   |
Route53
   |
WAF
   |
Application Load Balancer
   |
Auto Scaling Group
   |
EC2 application instances
   |
   +---- RDS PostgreSQL
   |
   +---- ElastiCache Redis

## 2. AWS Region and Availability Zones

The deployment runs in:

eu-central-1

The VPC spans three Availability Zones:

eu-central-1a
eu-central-1b
eu-central-1c

The application Auto Scaling Group runs one instance per AZ at its normal desired capacity of three.

## 3. Network Architecture
VPC

The application uses a dedicated VPC:

10.0.0.0/16

The VPC is divided into six subnets.

Each AZ has:

one public subnet
one private subnet

The layout is:
eu-central-1a
  public:  10.0.0.0/24
  private: 10.0.10.0/24

eu-central-1b
  public:  10.0.1.0/24
  private: 10.0.11.0/24

eu-central-1c
  public:  10.0.2.0/24
  private: 10.0.12.0/24

The public/private distinction is routing-based.

The public subnets have a default route to the Internet Gateway.

The private subnets have a default route through the NAT Gateway.

The subnets do not automatically assign public IPv4 addresses to instances.

Public tier

The public subnets are used by:

the Application Load Balancer
the NAT Gateway

The ALB is internet-facing.

Private tier

The private subnets contain:

EC2 application instances
RDS PostgreSQL
ElastiCache Redis

The application instances, database, and cache are not directly exposed to the Internet.

## 4. NAT Gateway

The deployment uses one shared NAT Gateway.

It is placed in the first public subnet and provides outbound Internet access for all three private subnets.

This is a deliberate cost trade-off.

A production design would normally use one NAT Gateway per AZ for better fault isolation. Bouncer uses one because this is a capstone and the extra fixed cost is significant.

The consequence is clear:

inbound application traffic remains multi-AZ
outbound Internet access depends on one NAT Gateway

The NAT Gateway is also controlled by the enable_billable_resources toggle so it can be removed between work sessions.

## 5. Security Group Model

Security groups enforce the main traffic boundaries.
Internet
   |
   v
ALB
   |
   v
App instances
   |
   +----> PostgreSQL
   |
   +----> Redis

The intended rules are:

ALB security group

Allows:

TCP 80 from the Internet
TCP 443 from the Internet

Allows application traffic to the app security group.

Application security group

Allows:

TCP 8000 only from the ALB security group

Allows outbound:

HTTPS
PostgreSQL to the database security group
Redis to the cache security group
Database security group

Allows:

TCP 5432 only from the application security group
Cache security group

Allows:

TCP 6379 only from the application security group

This prevents direct Internet access to the application port, PostgreSQL, or Redis.


##6. DNS, TLS, and Request Routing

The public application hostname is:

app.projectbouncer.org

The apex domain remains managed outside Route53.

A dedicated Route53 hosted zone is used for the application subdomain.

The application hostname is delegated to Route53 from the parent DNS configuration.

TLS

ACM provides a certificate for:

app.projectbouncer.org

The Application Load Balancer terminates TLS.

The HTTPS listener uses: ELBSecurityPolicy-TLS13-1-2-2021-06

HTTP on port 80 does not forward to the application.

It redirects to HTTPS.

The resulting request path is:

http://app.projectbouncer.org
        |
        v
301 redirect
        |
        v
https://app.projectbouncer.org

The ALB forwards HTTPS traffic to the application target group on port 8000.

The target group health endpoint is: /health

## 7. WAF

AWS WAF is attached to the regional ALB.

The web ACL contains:

AWSManagedRulesKnownBadInputsRuleSet
a rate-based rule for /login
a rate-based rule for /buy

The login and buy rate limits are scoped to the exact application paths.

The configured limit is:
10 requests
per 300 seconds
per source IP

The WAF is an edge-level control.

The application has additional controls behind it, so the WAF is not the only defense.

The live /buy test demonstrated the WAF rate limit:
Requests 1-5  -> HTTP 409
Request 6+    -> HTTP 429
The 409 responses came from the application because the test user already owned the ticket.

The later 429 responses showed that the WAF rate rule was active.

##8. Compute Layer

The compute layer uses:

EC2
Auto Scaling Group
Application Load Balancer
Launch Template
target tracking scaling
S3 application artifact storage
Auto Scaling Group

The normal capacity is:
minimum:  3
desired:  3
maximum:  6

Instances are distributed across the three AZs.

The ASG uses ELB health checks.

This matters because an instance can be running at the EC2 level while the application itself is unhealthy.

The target group checks: GET /health

Only healthy application instances remain in service.

AMI

The launch template uses a pinned Amazon Linux 2023 AMI.

The AMI is not selected through a "latest" lookup.

This keeps rebuilds reproducible.

Application process

The application runs:

Python
Flask
Gunicorn

The application listens on: 8000

## 9. Application Deployment

Application code is separated from Terraform infrastructure deployment.

app/deploy.sh:

packages the application
uploads the artifact to S3
triggers an Auto Scaling instance refresh

The application is therefore not embedded directly into Terraform user_data.

The S3 artifact bucket is versioned and has lifecycle rules for old versions and incomplete multipart uploads.

This gives two separate deployment paths:

Infrastructure change
    |
    v
Terraform apply

Application code change
    |
    v
S3 artifact
    |
    v
ASG instance refresh

This avoids requiring a Terraform infrastructure change for every application release.

## 10. Data Tier

The data tier contains:

Amazon RDS PostgreSQL
Amazon ElastiCache Redis

Both are private.

Both are controlled by enable_billable_resources.

Because both resources are deliberately destroyable in this capstone, a full teardown removes their data.

## 11. PostgreSQL

RDS runs:
PostgreSQL 17
db.t4g.micro

The current deployment is Single-AZ.

Storage encryption is enabled.

Public access is disabled.

Credentials are generated by Terraform and stored in AWS Secrets Manager.

The application retrieves the database credentials through its EC2 instance role.

Credentials are not stored as plaintext in .tf or .tfvars.

Application-owned schema

The database schema is not Terraform-managed.

The application owns:
users
events
tickets

The schema lives in:
app/src/schema.sql

The application applies this schema when it starts and has access to the database.

The table order is important:
users
   |
   +---- tickets.user_id
   |
events
   |
   +---- tickets.event_id

The tickets table contains: UNIQUE (event_id, user_id)

This is the database-level enforcement for one ticket per user per event.

Schema recovery

A full RDS destroy/recreate removes the row data.

The intended recovery flow is:
RDS recreated
    |
    v
application starts
    |
    v
schema.sql creates tables
    |
    v
reseed test user

This behavior was tested during the final teardown/bring-up cycle.

A schema regression was found during that test because the users table had been accidentally removed from schema.sql.

The original definition was restored and redeployed.

The fresh RDS instance then accepted the schema and the reseed script completed successfully.

This test was important because a normal redeploy against an existing RDS instance would not have exposed the missing table.

##12. Redis

ElastiCache runs:

Redis OSS 7.1
cache.t4g.micro

The current deployment uses one node.

Automatic failover is disabled.

Encryption is enabled:

at rest
in transit

TLS is required for client connections.

A generated authentication token protects the Redis service.

Redis stores shared application state that must be consistent across multiple EC2 instances.

The current uses are:

session state
login lockout counters
/buy rate limiting

This state is not stored in a local Python dictionary because the application runs on multiple instances behind the ALB.

Any instance must be able to read the same session and rate-limit state.

## 13. Authentication and Session Flow

The login flow is:
Client
  |
  v
Route53
  |
  v
WAF
  |
  v
ALB
  |
  v
Flask application
  |
  +----> PostgreSQL: verify user
  |
  +----> Redis: lockout/session state
  |
  v
Secure session cookie

Passwords are checked using bcrypt.

Session state is stored in Redis.

The application sends a cookie with:
Secure
HttpOnly
SameSite=Lax

A live login test returned: HTTP/2 200

and the follow-up /me request returned:

{"authenticated":true,"username":"testuser"}

## 14. Ticket Purchase Flow

The purchase flow is:
Client
  |
  v
HTTPS
  |
  v
WAF
  |
  v
ALB
  |
  v
EC2 application
  |
  +----> Redis rate limit
  |
  +----> PostgreSQL ticket insert
  |
  v
Response

The application and database provide different controls.

Redis rate limiting

Redis limits repeated /buy requests.

This protects against request bursts and abuse.

Database uniqueness

PostgreSQL enforces: UNIQUE (event_id, user_id)

This prevents the same user from successfully owning multiple tickets for the same event even if requests bypass or outlive the application-level logic.

The defense is therefore layered:
WAF
  |
  v
Redis rate limit
  |
  v
Application logic
  |
  v
PostgreSQL unique constraint

The live test produced:
First purchase  -> HTTP 201
Second purchase -> HTTP 409
This verifies the one-ticket-per-user behavior on the real stack.

## 15. Terraform State Architecture

Terraform is split into four independent roots:

terraform/environments/dev/
  foundation/
  data-tier/
  compute/
  observability/

Shared resource definitions live under:
terraform/modules/

Each root has its own Terraform state.

The layers are applied in dependency order:
foundation
    |
    v
data-tier
    |
    v
compute
    |
    v
observability

Later layers can read outputs from earlier layers through terraform_remote_state.

The dependency direction is one-way.

For example:
compute
   |
   +---- reads foundation outputs
   |
   +---- reads data-tier outputs

Foundation does not depend on compute.

This reduces state-level blast radius and makes each layer independently plan-able and apply-able.

## 16. CI/CD Architecture

GitHub Actions provides the infrastructure deployment pipeline.

Pull requests

terraform-plan.yml runs on every PR.

The workflow has two main stages.

Stage 1: formatting and policy

The workflow runs:
terraform fmt -check -recursive terraform/

and then:

checkov -d terraform --config-file .checkov.yaml --compact

Checkov is pinned in CI to:

3.3.16

Stage 2: Terraform plans

Terraform plans run independently for:
foundation
compute
data-tier

The plan jobs use the AWS deployment role through GitHub OIDC.

The deployment role is:

ce-capstone-bouncer-deploy

No long-lived AWS access keys are stored in GitHub Actions.

A final fan-in job reports whether all required checks passed.

This is the status check used by branch protection.

## 17. Terraform Apply

terraform-apply.yml runs after changes are merged to main.

It uses the same layer matrix:

foundation
compute
data-tier

and the same OIDC deployment role.

The apply command is:

terraform apply -auto-approve

The workflow runs only for Terraform-related changes and workflow changes.

## 18. Drift Detection

drift-detection.yml runs nightly and can also be triggered manually.

It uses:

terraform plan -detailed-exitcode

The exit codes distinguish:

0 = no changes
1 = plan error
2 = drift detected

Real drift and plan errors are sent to the SNS notification path.

## 19. Branch Protection

The main branch requires pull requests.

Force-push is disabled.

Branch deletion is disabled.

The branch must be current with main before merge.

The required CI status is the fan-in:

All checks passed

This means infrastructure changes must pass the same repository checks before reaching main.

## 20. Observability

The observability layer contains:

CloudWatch dashboard
CloudWatch alarms
VPC Flow Logs
SNS notifications
customer-managed KMS encryption for the SNS topic
AWS Budget alerts

The current application alarms cover:

elevated 5xx responses
unhealthy targets
high RDS CPU

SNS forwards notifications to email.

VPC Flow Logs are stored in CloudWatch Logs.

The flow logs are independent of the application dashboard.

## 21. Observability CI Limitation

The observability Terraform root exists and is managed with Terraform.

However, it is not currently included in the CI workflow matrices used by:

terraform-plan.yml
terraform-apply.yml
drift-detection.yml

Therefore its changes do not yet pass through the same real OIDC plan/apply/drift pipeline as the other three layers.

This is a known limitation of the current project.

It should not be described as fully CI-validated.

## 22. Cost Control Architecture

The main cost-control mechanism is:

enable_billable_resources

The variable is set in the committed per-layer:

dev.auto.tfvars

This is intentionally part of the repository state.

It keeps the desired billable state visible to both local Terraform and CI.

The lifecycle scripts change this value and then apply the individual layers.

Bring-up

foundation
    |
    v
data-tier
    |
    v
compute

Teardown

compute
    |
    v
data-tier
    |
    v
foundation

The scripts now live under:

scripts/

and were validated with a full teardown → bring-up cycle.

The lifecycle design is deliberately local:

local AWS credentials are used for the scripts
GitHub Actions continues to use OIDC for CI/CD

The two workflows are separate by design.

## 23. Destructive Teardown

A full teardown removes:

EC2 instances and ASG
ALB
WAF
RDS
Redis
NAT Gateway
associated foundation networking resources

RDS is configured without deletion protection and without a final snapshot.

Therefore a full teardown is destructive to database row data.

After the next bring-up, the database must be reseeded before the demo purchase flow can be used.

The application schema is restored from schema.sql, but test users and purchased tickets are not preserved.

## 24. Verified End-to-End Lifecycle

The current lifecycle was tested as a real AWS operation.

Teardown

The stack was destroyed layer by layer.

The NAT Gateway took time to disappear.

AWS then returned an eventual-consistency error while Terraform tried to release the NAT EIP.

The EIP was released after the NAT Gateway disappeared.

Terraform state was reconciled with:

terraform apply -refresh-only

The final foundation plan returned:

No changes. Your infrastructure matches the configuration.
Bring-up

The stack was recreated in dependency order.

The compute layer reported:

Healthy InService instances: 3 / 3

The ALB reported:

Healthy ALB targets: 3 / 3
Application recovery

RDS was empty after recreation.

The application initially exposed a schema regression caused by a missing users table in schema.sql.

The schema was corrected and redeployed.

The reseed script then completed successfully:

INSERT 0 1
SEEDED_OK

The login verification returned:

HTTP/2 200

The session endpoint returned:

HTTP/2 200

The first purchase returned:

HTTP/2 201

The duplicate purchase returned:

HTTP/2 409

The WAF rate limit returned:

HTTP 429

This is the strongest current evidence that the deployed architecture works from infrastructure creation through application behavior.

## 25. Main Trade-offs
One NAT Gateway

Chosen to reduce fixed cost.

Trade-off:

lower cost
lower outbound fault isolation
Single-AZ RDS

Chosen to keep the capstone affordable.

Trade-off:

lower cost
no multi-AZ database failover

A production deployment should use Multi-AZ RDS.

Single-node Redis

Redis stores application state that can be recreated.

Chosen to keep the design small and affordable.

Trade-off:

lower cost
no Redis node failover
EC2 instead of containers

EC2 keeps the deployment model visible and simple for the capstone.

The application is still stateless at the EC2 layer because shared session and rate-limit state lives in Redis.

A production system could move the application tier to ECS/Fargate.

Shared deploy role

One GitHub OIDC role is used by the Terraform layers.

Each layer has its own policy attached to that role.

This is simpler than maintaining one IAM role per layer, but it gives the shared role a larger credential blast radius than a fully separated design.

## 26. Production Changes

A production version should improve several areas:

one NAT Gateway per AZ
Multi-AZ RDS
replicated Redis with automatic failover
tighter separation of CI deploy roles
CI coverage for observability
stronger application deployment isolation
more complete disaster recovery
application-level secret rotation
central log aggregation and longer-term retention where required

Those changes are deliberately outside the scope of the current capstone.

## 27. Repository Map

terraform/
  environments/dev/
    foundation/
    data-tier/
    compute/
    observability/
  modules/
    cache/
    compute/
    database/
    iam/
    networking/
    observability/
    security/
backend.tf
main.tf
outputs.tf
vairables.tf

app/
  src/
    deploy.sh
    config.py
    requirements.txt
    schema.sql
    server.py
    deploy.sh
  templates/
    status.html

scripts/
  bringup.sh
  teardown.sh
  reseed-test-user.sh
  demo-lockout.sh

.github/
  workflows/
    drift-detection.yml
    terraform-apply.yml
    terraform-plan.yml

docs/
  architecture/
  decisions/
  incident-reports/

The architecture diagrams are stored under:

docs/architecture/

The main diagrams are:

architecture-overview.png
network-diagram.png
ci-cd-flow.png
data-flow.png

Architectural trade-offs are documented in:
docs/decisions/

Real implementation problems and their fixes are documented in:

docs/incident-reports/

## 28. Summary

Bouncer is built as a layered AWS system:

Route53
   |
WAF
   |
ALB
   |
EC2 ASG across 3 AZs
   |
   +---- PostgreSQL RDS
   |
   +---- Redis

Terraform manages the infrastructure.

GitHub Actions manages the Terraform pipeline.

OIDC removes long-lived AWS credentials from CI.

Security groups restrict east-west traffic.

WAF protects the public edge.

Redis provides shared application state.

PostgreSQL provides durable data and the final one-ticket-per-user constraint.

CloudWatch, SNS, Flow Logs, drift detection, and AWS Budgets provide the operational controls.

The current deployment is deliberately smaller and cheaper than a production design. The main trade-offs are documented rather than hidden.