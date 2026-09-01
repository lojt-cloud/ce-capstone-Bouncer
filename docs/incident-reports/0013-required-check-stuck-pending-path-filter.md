# 0013 — Required status check stuck "Pending" forever on path-filtered workflow

**Date:** 2026-09-01
**Severity:** Low (caught proactively during branch-protection setup, never actually blocked a real PR)
**Status:** Resolved

## Summary

While wiring `All checks passed` (the fan-in gate job in
`terraform-plan.yml`) as the repo's one required status check, reasoning
through the interaction with `terraform-plan.yml`'s existing `paths:`
filter (`terraform/**`, the workflow file itself) surfaced a GitHub
limitation: a required status check tied to a `paths`-filtered workflow
never reports back for a PR that doesn't touch those paths. GitHub does
not mark a skipped, path-filtered required check as passed — it stays
"Pending" indefinitely, and branch protection blocks the merge forever
regardless of every other check being green.

## Impact

None realized. This was found by reasoning about the config before a real
PR hit it, not from a stuck PR. Had it shipped as-is, any doc-only or
non-Terraform PR (README edit, a workflow-only change elsewhere, a
`docs/` addition) would have been permanently unmergeable without an
admin override, since `terraform-plan.yml` — and therefore `All checks
passed` — would never trigger.

## Root Cause

GitHub Actions' `paths:` filter prevents the workflow run from being
created at all for a non-matching PR. A required status check has no
concept of "not applicable" — it only has "never reported" (Pending) or
an actual conclusion. Skipping a workflow via path filtering produces the
former, not a synthetic pass. This is documented behavior on GitHub's
side, not a bug in this repo's config: their own troubleshooting docs
recommend job-level `if:`/`always()` conditionals over workflow-level
`paths:` filters for any workflow that backs a required check.

## Resolution

Removed the `paths:` filter from `terraform-plan.yml` entirely — it now
triggers unconditionally on every PR (`on: pull_request:` with no
`paths:` key). `terraform-apply.yml` keeps its `paths:` filter, since it
only runs on push to `main` and is not a required check — an unnecessary
apply there just wastes a few seconds of CI and an AWS API round trip,
not a stuck PR.

Verified with a live test PR (`test/verify-required-check-fires`, a
single blank-line change to `README.md` — no `terraform/` paths touched).
All four checks fired and passed: `lint-and-scan`, `plan (foundation)`,
`plan (compute)`, `All checks passed`. Test PR closed without merging;
branch deleted both locally and remotely.

## Prevention / Lessons Learned

Any workflow that backs a required status check must trigger
unconditionally on `pull_request` — no `paths:` filter. If a workflow
genuinely needs to skip work for certain PRs, gate the *steps* with
`if:` conditions instead, so the job (and therefore the check) still
reports a real pass/fail. This matters again the moment `data-tier` is
added to the plan matrix and again for any future workflow proposed as a
required check.
