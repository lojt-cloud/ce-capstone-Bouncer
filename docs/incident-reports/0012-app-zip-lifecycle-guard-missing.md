# Incident 0012: app.zip deploy artifact had no drift protection — automated apply would have overwritten it
**Date:** 2026-09-01
**Module:** CI/CD (Compute layer)
**Severity:** Low — caught before `terraform-apply.yml` ever ran against compute for real; no actual overwrite occurred.

## Summary
Adding compute to `terraform-apply.yml`'s matrix surfaced that
`aws_s3_object.app_zip` (`terraform/modules/compute/app_artifact.tf`) had
no `lifecycle.ignore_changes` guard, despite ARCHITECTURE.md documenting
the app-artifact bucket as "deliberately decoupled from Terraform
applies." A plain `terraform plan` against compute showed the object's
`etag`/`version_id` drifting from state — expected, since
`app/deploy.sh` uploads new builds directly, outside Terraform — but
with no guard, `terraform apply` would have silently overwritten
whatever `deploy.sh` had most recently deployed with a fresh build from
the CI runner's own checkout of `app/src`.

## Root cause
The documented "decoupling" was never actually enforced in the resource
itself — only true in practice because applies had stayed manual and
infrequent so far. Once `terraform-apply.yml` runs automatically on
every merge touching `terraform/**` (regardless of which layer actually
changed), this resource would be re-applied on every such merge,
redeploying whatever that specific checkout happens to build.

## How it was caught
Routine `terraform plan` in compute while verifying the billable-toggle
tracking fix (see ADR 0009) — the `app_zip` diff appeared even though
nothing in that PR touched app code.

## Resolution
Added `lifecycle { ignore_changes = [source, etag] }` to
`aws_s3_object.app_zip`. Terraform still bootstraps the object if it's
ever missing (new bucket, disaster recovery); it never again fights
`deploy.sh`'s uploads.

## Prevention / lesson
A "deliberately decoupled" design note in prose isn't the same as an
enforced Terraform `lifecycle` block — the two can silently drift apart
as long as nothing actually re-applies that resource. Automating apply
is exactly the kind of change that turns a previously-harmless gap into
a real one; worth re-auditing every resource for implicit "we don't
really re-apply this" assumptions before wiring up automatic apply for
any layer.
