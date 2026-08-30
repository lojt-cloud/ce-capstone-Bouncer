# Incident 0001: Deploy role permission gaps only surfaced under real CI

**Date:** 2026-08-30
**Severity:** Low — caught pre-merge in `dev`, no production/user impact.
**Status:** Resolved

## Summary

`terraform-plan.yml` failed when it assumed the real CI deploy role and
ran `terraform plan` against the Foundation layer, even though the same
plan had already been checked manually and looked clean.

## Impact

CI failed on PR #10, blocking merge until fixed. No infrastructure was
affected — this was caught in the plan stage, before any apply.

## Root cause

The Foundation deploy role's scoped IAM policy
(`ce-capstone-bouncer-dev-deploy-foundation`) had been verified by running
the plan manually with personal/admin AWS credentials. Admin credentials
already hold every permission the scoped role might be missing, so that
check couldn't reveal a gap in the scoped policy itself — it only proved
the *plan* was correct, not that the *role* could execute it.

The scoped policy was actually missing two actions:
- `iam:GetPolicyVersion` — a read action, easy to omit when the focus is
  scoping write/manage permissions.
- `logs:DescribeLogGroups` — a listing action that AWS does not support
  scoping to a single log group, so it has to stay `Resource: "*"`.

Both went unnoticed until the CI pipeline assumed the actual role via OIDC
and tried to run the same plan for real.

## Resolution

Added both actions to `ce-capstone-bouncer-dev-deploy-foundation` (now
policy version `v3`). Re-ran the PR check and confirmed a clean plan under
the actual assumed deploy role, not admin credentials.

## Prevention

Added a standing rule to `working-style.md`: verify any new scoped IAM
permission by assuming the actual deploy role and testing the real action
against it, not broader personal/admin credentials. Applies to every
future module (compute, data-tier, product-security, ...) that attaches
its own scoped policy to this role.