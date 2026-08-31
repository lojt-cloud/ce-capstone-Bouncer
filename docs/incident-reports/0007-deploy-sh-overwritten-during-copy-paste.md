# Incident 0007: app/deploy.sh overwritten with Terraform draft content

**Date:** 2026-08-31
**Module:** Compute (deploy-role IAM policy)
**Severity:** Low — caught before commit, no data lost.

## Summary
While iterating on `deploy-policy.tf`, `app/deploy.sh` — the compute
module's out-of-band S3 sync/instance-refresh script, unrelated to this
session's work — showed up modified in `git status`. Its content had been
replaced entirely with an early draft of the deploy-policy Terraform HCL.

## Root cause
A copy/paste of the Terraform policy draft landed in the wrong local file.

## How it was caught
Routine `git status` before committing flagged `app/deploy.sh` as modified
when nothing in this session's task should have touched it. `git diff`
confirmed the content was Terraform, not bash, before anything was staged.

## Resolution
`git restore app/deploy.sh` before staging anything, restoring the
original script. Confirmed via `head -5 app/deploy.sh`. Only
`deploy-policy.tf` was staged and committed.

## Prevention / lesson
Same lesson as incident 0005: check `git status`/`git diff` for unexpected
files immediately before staging, even on a routine commit — a scoped,
single-purpose commit is a cheap safety net against exactly this kind of
cross-file paste mistake.