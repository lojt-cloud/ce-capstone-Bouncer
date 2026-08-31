# Incident 0006: S3 bucket phantom recreation from a missing s3:ListBucket permission

**Date:** 2026-08-31
**Module:** Compute (deploy-role IAM policy)
**Severity:** High — would have destroyed and recreated the app-artifact S3
bucket and every dependent resource under CI, with no error explaining why.

## Summary
While scoping `ce-capstone-bouncer-dev-deploy-compute`, `terraform plan`
under the real assumed deploy role showed the app-artifact S3 bucket, and
every resource referencing it, planned as `+create` / `-/+ replace` — a
full recreation cascade. No `AccessDenied` appeared anywhere in the output.

## Root cause
The AWS provider's existence check for `aws_s3_bucket` calls `HeadBucket`
internally. `HeadBucket` is authorized by the `s3:ListBucket` IAM action —
not a `HeadBucket`-named permission. The policy granted
`s3:CreateBucket`/`s3:DeleteBucket` and various `Get*`/`Put*` sub-config
actions, but not `s3:ListBucket`. Without it, the refresh treated the
bucket as nonexistent and planned to create a new one, dragging every
dependent resource along.

## Why it wasn't caught earlier
The policy had already been "applied and verified" with personal/admin
credentials, which trivially have `s3:ListBucket`. The gap was invisible
until tested under the actual scoped role — confirms the standing lesson
from ADR 0002 / incident 0003.

## Resolution
Added `s3:ListBucket`. That surfaced a second wave of individual
`AccessDenied` errors for the bucket's other `Get*` sub-config reads
(versioning, encryption, public-access-block, lifecycle, tagging, ACL,
location, policy, CORS, logging, object-lock, replication, request-payer,
accelerate, website) — `aws_s3_bucket` calls all of these on every refresh
regardless of which sub-blocks are actually configured. Added the full
set; `terraform plan` under the assumed role came back clean.

## Prevention / lesson for future modules
Any module owning an `aws_s3_bucket` needs `s3:ListBucket` plus this full
`Get*` read surface in its deploy-role policy from the start. A
clean-looking `+create` plan under a scoped role is not proof the resource
is actually gone — check for missing `s3:ListBucket` first.