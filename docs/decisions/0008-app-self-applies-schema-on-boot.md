# ADR 0008: App self-applies the users table schema on boot

## Status
Accepted

## Context
The `users` table was originally created by hand via `psql` during the
login/lockout build — application schema, not Terraform-managed. RDS's
`enable_billable_resources` toggle is destructive (`skip_final_snapshot
= true`, no `deletion_protection`), so scaling RDS down between work
sessions deletes the database outright. Every toggle-back-on would
otherwise require reconnecting via SSM and re-running `CREATE TABLE`
by hand before the app is usable — easy to forget, and a manual step
standing between "infrastructure is up" and "app actually works."

## Decision
Ship `schema.sql` inside the app's own deploy artifact
(`app/src/schema.sql`, packaged into `app.zip` alongside `server.py`)
and have the app apply it itself — `CREATE TABLE IF NOT EXISTS`,
executed once at boot right after the DB connection pool opens
successfully, wrapped in try/except so a failure here can't crash app
startup. Deliberately not a dedicated migration tool (Alembic, Flyway)
or a Terraform-managed schema resource — both are more machinery than
one idempotent DDL statement justifies at this scale, and a
Terraform-side `local-exec` would need network access to a
private-subnet RDS instance that the machine running `terraform apply`
doesn't have.

## Consequences
Schema changes now live in application code, versioned through the
same PR flow as `server.py`, but with no migration history or rollback
mechanism — fine for one additive table, would not scale to a real
multi-table schema with evolving columns. Every gunicorn worker (`-w
2`) runs this block independently on each boot; `CREATE TABLE IF NOT
EXISTS` makes that safe in practice. Verified live: dropped `users` on
the real RDS instance, triggered an ASG instance refresh, confirmed the
app recreated the identical schema unattended (see RUNBOOK.md).