# Runbook

## RDS recreation / schema recovery

The `users` table is not managed by Terraform and has no separate
migration step. The app itself runs `app/src/schema.sql`
(`CREATE TABLE IF NOT EXISTS`) on every boot, right after it opens its
DB connection pool -- so if RDS is ever destroyed and recreated, the
schema is restored automatically on the next instance boot or deploy,
with no manual `psql` step required. This only creates the table
structure; any data (e.g. test users) is gone if RDS was actually
destroyed and needs to be reseeded manually.

Verified 2026-08-31: dropped `users` on the live dev RDS instance,
triggered an ASG instance refresh, confirmed the app recreated the
table with the same schema on the fresh instance, reseeded a test
user, and confirmed login worked end to end via the ALB.

## Reseeding test users after RDS recreate

Whenever RDS is destroyed and recreated (the `enable_billable_resources`
toggle off/on in `terraform/environments/dev/data-tier`, or any other
reason the instance gets replaced), the `users` table schema recreates
itself automatically (see above) but any rows are gone. Steps to get
back to a working test login, start to finish:

### 1. Confirm the app tier is healthy first

Don't reseed until the schema actually exists -- the self-heal only runs
once the app successfully opens a DB connection.

    cd ~/cloud-engineering/ce-capstone-Bouncer/terraform/environments/dev/compute
    terraform output asg_name

    aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names <asg_name> \
      --region eu-central-1 \
      --query "AutoScalingGroups[0].Instances[].{Id:InstanceId,Health:HealthStatus,State:LifecycleState}" \
      --output table

All instances should show `Healthy` / `InService`.

### 2. Get a running instance ID and connect via SSM

    aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names <asg_name> \
      --region eu-central-1 \
      --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService'].InstanceId" \
      --output text

    aws ssm start-session --target <instance-id> --region eu-central-1

Everything below runs inside that session.

### 3. Install psql (fresh instance, not baked into the AMI)

    which psql || sudo dnf install -y postgresql15

### 4. Pull DB credentials fresh from Secrets Manager

Don't hardcode the host or password anywhere -- fetch live every time,
since a real RDS recreate can produce a new endpoint hostname.

    sudo systemctl show bouncer-app -p Environment
    # copy the DB_SECRET_NAME value from the output, then:

    aws secretsmanager get-secret-value \
      --secret-id ce-capstone-bouncer-dev-db-credentials \
      --region eu-central-1 \
      --query SecretString --output text

That prints JSON with `host`, `port`, `dbname`, `username`, `password`.

### 5. Connect and confirm the schema is there

    PGPASSWORD='<password from step 4>' psql -h <host from step 4> -p 5432 -U bouncer_admin -d bouncer -c "\dt" -c "\d users"

Expect the `users` table with 4 columns -- no manual `CREATE TABLE`
needed; the app already did it.

### 6. Generate a bcrypt hash for the new password

Use the app's own venv already on the instance -- no laptop dependency
needed.

    /opt/bouncer-app/venv/bin/python3 -c "import bcrypt; print(bcrypt.hashpw(b'YOUR_PASSWORD_HERE', bcrypt.gensalt()).decode())"

Pick a password with no `!`, `$`, backtick, or other shell-special
characters -- bash history expansion mangles `!` even inside single
quotes.

### 7. Insert the test user

Reconnect to psql if you exited it in step 5:

    PGPASSWORD='<password from step 4>' psql -h <host from step 4> -p 5432 -U bouncer_admin -d bouncer

    INSERT INTO users (username, password_hash) VALUES ('testuser', '<hash from step 6>');

Expect `INSERT 0 1`. Then `\q` and `exit` to leave psql and the SSM
session.

### 8. Verify login end to end

Back on your laptop:

    cd ~/cloud-engineering/ce-capstone-Bouncer/terraform/environments/dev/compute
    terraform output alb_dns_name

    curl -i -X POST http://<alb_dns_name>/login \
      -H "Content-Type: application/json" \
      -d '{"username":"testuser","password":"YOUR_PASSWORD_HERE"}'

Expect `200 OK` with a `Set-Cookie: session_id=...` header. That
confirms the full path: RDS reachable, schema present, row inserted,
bcrypt verified, session written to Redis, cookie issued.

Note: this procedure is only needed after an actual RDS destroy/recreate.
Redeploying the app alone (`./app/deploy.sh`) or an ASG instance refresh
with RDS untouched leaves existing rows intact -- no reseed needed.

## NAT Gateway EIP release failure on toggle-off

`terraform apply -var="enable_billable_resources=false"` in the
foundation layer can fail releasing the NAT Gateway's EIP with
`InvalidNetworkInterfaceID.NotFound`, referencing an ENI that no longer
exists -- a stale reference in AWS's EIP-release path, not a real
association (confirmed via `aws ec2 describe-addresses`, which showed
no `AssociationId`/`NetworkInterfaceId`). Retrying `terraform apply`
does not resolve it. Fix: release the EIP directly, then re-apply to
reconcile state:

    aws ec2 release-address --allocation-id <id> --region eu-central-1
    terraform apply -var="enable_billable_resources=false"

## CI/CD Pipeline

**Plan** (`.github/workflows/terraform-plan.yml`) — triggers on every PR,
unconditionally (no path filter — see why in the required-status-check
note below). Two jobs:
1. `fmt + checkov` — `terraform fmt -check`, then a full Checkov scan of
   `terraform/` against `.checkov.yaml`. No AWS credentials needed; fails
   fast before spending time on a real plan.
2. `plan` — matrixed per layer (`foundation`, `compute` currently;
   `data-tier` not yet wired, see below). Assumes the OIDC deploy role,
   runs `terraform plan`, posts the output as a PR comment even on
   failure (so the reviewer sees the real error, not just a red X).

**Apply** (`.github/workflows/terraform-apply.yml`) — triggers on push to
`main` (i.e. on PR merge) that touches `terraform/**` or the workflow file
itself. Same matrix scope as plan currently (`foundation`, `compute`),
same OIDC role. Runs `terraform apply -auto-approve`, writes the output to
the run's job summary.

**Branch protection** enforces the PR flow: `main` requires a PR for every
change (`enforce_admins: true` — applies even to the repo owner, no direct
push), 0 required approvals, force-push and deletion disabled. **One
required status check, `All checks passed`** — a fan-in job in
`terraform-plan.yml` that depends on the whole `fmt+checkov`/`plan`
matrix and reports a single pass/fail, so branch protection never needs
reconfiguring as the matrix grows (e.g. when `data-tier` is added).
`strict: true` also means a PR's branch must be up to date with `main`
before it can merge. This is also why `plan` has no path filter: a
required check tied to a path-filtered workflow gets stuck "Pending"
forever on any PR that doesn't touch those paths — a known,
still-unresolved GitHub limitation (confirmed via GitHub's own
troubleshooting docs), not a bug in this setup.

**Billable-resource on/off toggle**: each layer's `enable_billable_resources`
lives in a committed `dev.auto.tfvars` (`terraform/environments/dev/<layer>/`),
not a runtime flag — both local Terraform and CI load it automatically.
To bring a CI-wired layer (foundation, compute) back up: flip that file to
`true`, open a PR, merge — the apply workflow does the real `terraform
apply`. `data-tier` isn't CI-wired yet, so still requires a local apply.
`./teardown.sh` writes `false` into all three layers' files and applies
foundation/compute/data-tier locally in dependency order — run it, then
commit the resulting `dev.auto.tfvars` changes so CI doesn't try to undo
them on the next merge.

**Drift detection** (`.github/workflows/drift-detection.yml`) — scheduled
nightly at `0 3 * * *` UTC (roughly 4-5am Central Europe, depending on
DST), plus `workflow_dispatch` for manual runs. Same matrix scope as plan
and apply (`foundation`, `compute`; `data-tier` not yet wired). Runs
`terraform plan -detailed-exitcode` per layer: exit 0 means clean (no
alert, job passes), exit 2 means real drift was detected (out-of-band
change, or the environment doesn't match its `dev.auto.tfvars` toggle),
exit 1 means the plan itself errored. Exit 2 and exit 1 both publish to
the SNS topic below with distinct subject lines and both fail the job, so
drift and a broken check are never confused with each other — check the
Actions tab if the nightly run shows red.

**Alerting** — SNS topic `ce-capstone-bouncer-dev-drift-alerts`
(`arn:aws:sns:eu-central-1:743631836010:ce-capstone-bouncer-dev-drift-alerts`),
KMS-encrypted at rest, one email subscription. Defined in
`terraform/environments/dev/foundation/drift-alerts.tf` alongside a
supplemental IAM policy on the deploy role scoped to just this topic. Not
gated by the billable-resources toggle — negligible cost, stays alive
through a full teardown so the nightly check can still confirm "nothing
drifted" even when the environment is intentionally off.