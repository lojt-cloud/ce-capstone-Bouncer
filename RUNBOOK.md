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
