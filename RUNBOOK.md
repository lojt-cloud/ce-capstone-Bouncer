# Runbook

## 1. Scope

This runbook covers the normal operating procedures for the Bouncer dev environment:

- bring-up
- teardown
- database recovery after RDS recreation
- test-user reseeding
- login and ticket-purchase verification
- CI/CD checks
- drift detection
- common AWS failures

The environment runs in `eu-central-1`.

The Terraform roots are:

```text
terraform/environments/dev/
  foundation/
  data-tier/
  compute/
  observability/
```

The lifecycle scripts are:

```text
scripts/bringup.sh
scripts/teardown.sh
scripts/reseed-test-user.sh
```

---

## 2. Important warning

A full teardown is destructive.

RDS and ElastiCache are destroyed when the billable-resource toggle is disabled.

RDS is configured without deletion protection and without a final snapshot.

A full teardown therefore removes:

- database row data
- Redis state
- application instances
- load balancer
- WAF
- NAT Gateway
- related billable networking resources

The database schema is recreated automatically by the application after the next bring-up, but test users and purchased tickets must be reseeded.

Do not run teardown against an environment containing data that must be preserved.

---

## 3. Billable-resource toggle

Billable resources are controlled through:

```text
enable_billable_resources
```

The value is stored in each layer's committed:

```text
terraform/environments/dev/<layer>/dev.auto.tfvars
```

The lifecycle scripts update these files before running Terraform.

This is intentional.

The desired state is visible to both local Terraform and CI instead of being hidden in a temporary `-var` argument.

The main billable layers are:

- `foundation`
- `data-tier`
- `compute`

The `observability` layer is not part of the billable-resource lifecycle toggle.

---

## 4. Bring-up

Use:

```bash
cd ~/cloud-engineering/ce-capstone-Bouncer
./scripts/bringup.sh
```

The script brings the environment up in this order:

```text
foundation
    |
    v
data-tier
    |
    v
compute
```

This order matters.

The compute layer should only start after RDS and ElastiCache exist. This lets the application open its database connection against the newly created RDS instance during first boot.

The script:

1. sets each layer's `enable_billable_resources` value to `true`
2. applies `foundation`
3. applies `data-tier`
4. waits for RDS to become available
5. applies `compute`
6. waits for the ASG to have the expected healthy `InService` instances
7. checks ALB target health

A successful run ends with:

```text
=== Bring-up complete ===
```

and reports the number of healthy ASG instances and ALB targets.

### Verified bring-up

The current script has been tested after a complete teardown.

The tested result was:

```text
Healthy InService instances: 3 / 3
Healthy ALB targets: 3 / 3
```

The script did not commit or push the `dev.auto.tfvars` changes.

---

## 5. Teardown

Run:

```bash
cd ~/cloud-engineering/ce-capstone-Bouncer
./scripts/teardown.sh
```

The script asks for explicit confirmation before continuing.

Teardown runs in reverse dependency order:

```text
compute
    |
    v
data-tier
    |
    v
foundation
```

The script sets the three billable layers to:

```text
enable_billable_resources = false
```

and applies each layer.

### NAT Gateway / EIP race

AWS can briefly return:

```text
InvalidNetworkInterfaceID.NotFound
```

when Terraform releases the EIP immediately after deleting the NAT Gateway.

This is an AWS-side timing issue around the deleted NAT Gateway network interface.

The teardown script has a retry path for the EIP release.

During the latest full teardown test, the NAT Gateway finished deleting, but the EIP release still failed after the script's retries. The EIP was then released manually once the NAT Gateway's ENI no longer existed.

The resulting Terraform state was reconciled with:

```bash
terraform apply -refresh-only
```

The final foundation plan returned:

```text
No changes. Your infrastructure matches the configuration.
```

If the race happens again outside the script, check whether the EIP still exists:

```bash
aws ec2 describe-addresses \
  --allocation-ids <allocation-id> \
  --region eu-central-1
```

If the allocation still exists and the NAT Gateway is already deleted, retry the release:

```bash
aws ec2 release-address \
  --allocation-id <allocation-id> \
  --region eu-central-1
```

Then refresh the foundation state:

```bash
cd ~/cloud-engineering/ce-capstone-Bouncer/environments/dev/foundation
terraform apply -refresh-only
terraform plan
```

The expected final plan is:

```text
No changes. Your infrastructure matches the configuration.
```

---

## 6. Verify the environment after bring-up

Check the ASG:

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names ce-capstone-bouncer-dev-app-asg \
  --region eu-central-1 \
  --query "AutoScalingGroups[0].Instances[].{Id:InstanceId,Health:HealthStatus,State:LifecycleState}" \
  --output table
```

Expected:

```text
Health    State
Healthy   InService
```

At normal capacity there should be three healthy instances.

Check RDS:

```bash
aws rds describe-db-instances \
  --db-instance-identifier ce-capstone-bouncer-dev-db \
  --region eu-central-1 \
  --query 'DBInstances[0].DBInstanceStatus'
```

Expected:

```text
"available"
```

Check the public HTTPS endpoint:

```bash
curl -I https://app.projectbouncer.org/health
```

Expected:

```text
HTTP/2 200
```

Check the HTTP redirect:

```bash
curl -I http://app.projectbouncer.org/health
```

Expected:

```text
301
Location: https://app.projectbouncer.org/health
```

---

## 7. RDS recreation and schema recovery

The application owns the database schema.

The schema file is:

```text
app/src/schema.sql
```

It creates:

```text
users
events
tickets
```

in dependency order.

The application applies this SQL during startup.

The schema is not Terraform-managed.

A full RDS recreation removes table data, so the recovery sequence is:

```text
RDS recreated
    |
    v
application starts
    |
    v
schema.sql runs
    |
    v
reseed test user
    |
    v
verify login
```

Do not assume that a healthy EC2 instance means the schema is ready. Check the application logs if reseeding fails.

To inspect schema initialization logs on a running instance:

```bash
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names ce-capstone-bouncer-dev-app-asg \
  --region eu-central-1 \
  --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService']|[0].InstanceId" \
  --output text)

CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo journalctl -u bouncer-app --no-pager -n 200 | grep -i -E '\''schema init|schema.sql|postgres|database|error'\'' || true"]' \
  --region eu-central-1 \
  --query "Command.CommandId" \
  --output text)

aws ssm wait command-executed \
  --command-id "$CMD_ID" \
  --instance-id "$INSTANCE_ID" \
  --region eu-central-1

aws ssm get-command-invocation \
  --command-id "$CMD_ID" \
  --instance-id "$INSTANCE_ID" \
  --region eu-central-1 \
  --query '{Status:Status,StdOut:StandardOutputContent,StdErr:StandardErrorContent}' \
  --output json
```

A successful schema initialization should not report:

```text
[schema init] failed to apply schema.sql
```

---

## 8. Reseed a test user

After a real RDS destroy/recreate, use:

```bash
cd ~/cloud-engineering/ce-capstone-Bouncer
./scripts/reseed-test-user.sh <username> <password>
```

Example:

```bash
./scripts/reseed-test-user.sh demo-user 'TemporaryTestPassword123!'
```

The password is passed to the script and used to generate a bcrypt hash on the application instance.

The script:

1. checks the ASG for a healthy `InService` instance
2. sends the reseed command through SSM
3. retrieves the current database secret from Secrets Manager
4. hashes the password with bcrypt
5. inserts or updates the user
6. verifies login against the public HTTPS domain

A successful reseed includes:

```text
SEEDED_OK
```

followed by a successful login response.

### HTTPS verification

The reseed script verifies:

```text
https://app.projectbouncer.org/login
```

Do not change this back to the ALB's HTTP endpoint.

The ALB intentionally redirects HTTP to HTTPS.

---

## 9. Manual schema troubleshooting

When the automated reseed script fails, connect to an instance with SSM:

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names ce-capstone-bouncer-dev-app-asg \
  --region eu-central-1 \
  --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService'].InstanceId" \
  --output text
```

Then:

```bash
aws ssm start-session \
  --target <instance-id> \
  --region eu-central-1
```

Inside the instance, check whether `psql` exists:

```bash
which psql || sudo dnf install -y postgresql16
```

The server is PostgreSQL 17. The client package may report a version difference, which is acceptable for the commands used in this runbook.

Fetch the current database secret:

```bash
aws secretsmanager get-secret-value \
  --secret-id ce-capstone-bouncer-dev-db-credentials \
  --region eu-central-1 \
  --query SecretString \
  --output text
```

Use the returned values for:

- `host`
- `port`
- `dbname`
- `username`
- `password`

Check the schema:

```bash
PGPASSWORD='<database password>' \
psql \
  -h <database host> \
  -p 5432 \
  -U bouncer_admin \
  -d bouncer \
  -c "\\dt"
```

Expected tables:

```text
users
events
tickets
```

Do not manually create the tables unless debugging has established that the application cannot initialize the schema.

---

## 10. Login verification

From the laptop:

```bash
curl -i -X POST https://app.projectbouncer.org/login \
  -H "Content-Type: application/json" \
  -d '{"username":"YOUR_USERNAME","password":"YOUR_PASSWORD"}'
```

Expected:

```text
HTTP/2 200
```

with a `Set-Cookie` header containing:

```text
Secure
HttpOnly
SameSite=Lax
```

To verify the session:

```bash
rm -f cookies.txt

curl -i -c cookies.txt \
  -X POST https://app.projectbouncer.org/login \
  -H "Content-Type: application/json" \
  -d '{"username":"YOUR_USERNAME","password":"YOUR_PASSWORD"}'

curl -i -b cookies.txt \
  https://app.projectbouncer.org/me
```

Expected `/me` response:

```json
{"authenticated":true,"username":"YOUR_USERNAME"}
```

Do not commit `cookies.txt`.

---

## 11. End-to-end purchase verification

Use a fresh test user when you need to prove that the first purchase succeeds.

### Login

```bash
rm -f buy-cookies.txt

curl -i -c buy-cookies.txt \
  -X POST https://app.projectbouncer.org/login \
  -H "Content-Type: application/json" \
  -d '{"username":"YOUR_USERNAME","password":"YOUR_PASSWORD"}'
```

Expected:

```text
HTTP/2 200
```

### First purchase

```bash
curl -i -b buy-cookies.txt \
  -X POST https://app.projectbouncer.org/buy
```

Expected for a user without a ticket:

```text
HTTP/2 201
```

Example response:

```json
{"event":"Bouncer Launch Night","status":"ok","ticket_id":1}
```

### Repeat purchase

Run the same request again:

```bash
curl -i -b buy-cookies.txt \
  -X POST https://app.projectbouncer.org/buy
```

Expected:

```text
HTTP/2 409
```

with an error such as:

```json
{"error":"already have a ticket for this event"}
```

This verifies the one-ticket-per-user behavior on the live application.

Remove local cookie files after the test:

```bash
rm -f cookies.txt buy-cookies.txt
```

---

## 12. WAF rate-limit verification

The WAF has rate-based rules on `/login` and `/buy`.

The configured limit is:

```text
10 requests per 300 seconds per source IP
```

To test the live `/buy` protection:

```bash
for i in $(seq 1 12); do
  echo "=== request $i ==="
  curl -s -o /dev/null -w "HTTP %{http_code}\\n" \
    -b buy-cookies.txt \
    -X POST https://app.projectbouncer.org/buy
done
```

In the latest live test, the sequence was:

```text
409
409
409
409
409
429
429
429
429
429
429
429
```

The `409` responses were generated by the application because the test user already had a ticket.

The later `429` responses demonstrated that the public `/buy` protection was active.

When interpreting rate-limit tests, distinguish:

- application `429` responses
- WAF blocking behavior
- normal application `409` duplicate-ticket responses

Do not claim that a specific layer fired unless the response and test conditions prove it.

---

## 13. Application deployment

Application changes are deployed separately from Terraform infrastructure changes.

Run:

```bash
cd ~/cloud-engineering/ce-capstone-Bouncer
./app/deploy.sh
```

The deployment script packages the application, uploads the artifact to the S3 artifact bucket, and triggers an ASG instance refresh.

A successful deployment should be followed by:

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names ce-capstone-bouncer-dev-app-asg \
  --region eu-central-1 \
  --query "AutoScalingGroups[0].Instances[].{Id:InstanceId,Health:HealthStatus,State:LifecycleState}" \
  --output table
```

Confirm that the expected instances are `Healthy` and `InService`.

---

## 14. Terraform checks

For a read-only infrastructure check:

```bash
terraform plan
```

Run it from the relevant layer directory.

The normal clean result is:

```text
No changes. Your infrastructure matches the configuration.
```

For all three CI-managed layers:

```bash
cd terraform/environments/dev/foundation
terraform plan

cd ../data-tier
terraform plan

cd ../compute
terraform plan
```

The `observability` layer exists separately and is not included in the current CI plan/apply/drift matrices.

---

## 15. CI/CD

### Pull request checks

Every pull request runs:

```text
terraform fmt -check
Checkov
Terraform plan
```

Terraform plans run for:

```text
foundation
compute
data-tier
```

The CI jobs assume AWS credentials through GitHub OIDC.

The deployment role is:

```text
ce-capstone-bouncer-deploy
```

No long-lived AWS access keys are stored in the workflow.

A final `All checks passed` job is the required branch-protection status.

### Apply

After a PR is merged into `main`, the apply workflow runs for Terraform-related changes.

### Drift detection

The drift workflow runs nightly and can also be started manually.

It uses:

```bash
terraform plan -detailed-exitcode
```

Exit codes:

```text
0 = no changes
1 = plan error
2 = drift detected
```

Exit 1 and exit 2 are treated differently in the alerting path.

---

## 16. Branch protection

Changes to `main` must go through a pull request.

The normal flow is:

```text
feature branch
    |
    v
push branch
    |
    v
pull request
    |
    v
CI checks
    |
    v
All checks passed
    |
    v
squash merge
    |
    v
main
```

Do not push directly to `main`.

---

## 17. HTTPS, WAF, and budget quick checks

### HTTPS

```bash
curl -I http://app.projectbouncer.org/health
curl -I https://app.projectbouncer.org/health
```

Expected:

```text
HTTP -> 301 redirect
HTTPS -> HTTP/2 200
```

### WAF attachment

```bash
aws wafv2 get-web-acl-for-resource \
  --resource-arn <alb-arn> \
  --region eu-central-1
```

WAF logging:

```bash
aws wafv2 get-logging-configuration \
  --resource-arn <web-acl-arn> \
  --region eu-central-1
```

### Budget

```bash
aws budgets describe-notifications-for-budget \
  --account-id <account-id> \
  --budget-name ce-capstone-bouncer-dev-monthly
```

The budget uses the same SNS notification path as the infrastructure alarms.

---

## 18. Alarm fires but no email arrives

Check alarm action history:

```bash
aws cloudwatch describe-alarm-history \
  --alarm-name <alarm-name> \
  --history-item-type Action \
  --max-records 3 \
  --output text
```

If the error mentions that CloudWatch Alarms cannot use the SNS topic encryption key, verify that the SNS topic still uses the project's customer-managed KMS key.

The alarm path depends on the SNS KMS key policy allowing CloudWatch to publish.

The AWS-managed `alias/aws/sns` key should not be substituted for the project CMK.

AWS Budgets uses the same topic but has its own authorization requirements in the SNS resource policy and KMS policy.

---

## 19. Observability limitation

The `observability` Terraform root is implemented.

It is not currently included in the three GitHub Actions matrices for:

- plan
- apply
- drift detection

Therefore do not describe observability as having the same CI validation level as `foundation`, `data-tier`, and `compute`.

---

## 20. Common mistakes

### Reseed fails with `relation "users" does not exist`

Check the application startup logs.

The current `schema.sql` must create `users` before `tickets`.

A previous regression removed the `users` definition from the schema. It was restored and verified during the full teardown/bring-up test.

### Reseed ends with HTTP 301

Check that the script uses:

```text
https://app.projectbouncer.org/login
```

The ALB intentionally redirects HTTP to HTTPS.

### ASG exists but application is not healthy

Check:

```bash
aws autoscaling describe-auto-scaling-groups ...
```

and the application logs through SSM.

Then verify:

```bash
curl -I https://app.projectbouncer.org/health
```

### Terraform says the EIP changed outside Terraform

This can happen after the NAT Gateway/EIP deletion race.

Run:

```bash
terraform apply -refresh-only
terraform plan
```

The goal is to reconcile Terraform state with the current AWS state.

---

## 21. Operational lessons from the latest full test

The complete teardown and bring-up test exposed two real issues that normal day-to-day operation had not exposed:

1. AWS can race while the NAT Gateway's network interface disappears before EIP release completes.
2. A regression in `app/src/schema.sql` removed the `users` table definition, which only became visible after RDS was recreated from scratch.

Both issues were fixed.

The lifecycle scripts were then revalidated.

The final live application verification showed:

```text
login       -> 200
/me         -> 200
first /buy  -> 201
repeat /buy -> 409
rate limit  -> 429
```

These checks were performed against the live AWS environment rather than only against local code.
