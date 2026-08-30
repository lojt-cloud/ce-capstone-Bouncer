# Incident 0002: OIDC AssumeRoleWithWebIdentity silently failing on subject claim format

**Date:** 2026-08-30
**Severity:** Medium — blocked all CI runs against AWS until resolved.
**Status:** Resolved

## Summary

The deploy role's trust policy could not be assumed via GitHub Actions
OIDC. `AssumeRoleWithWebIdentity` failed with a generic "not authorized"
error that gave no indication of what was actually wrong.

## Impact

Every workflow run that needed to assume the deploy role failed at the
authentication step — no plan or apply could reach AWS until fixed.

## Root cause

The trust policy's `sub` claim condition used the standard
`repo:owner/repo:ref:refs/heads/main` format shown in most GitHub Actions
OIDC documentation and examples. GitHub changed the *default* subject
claim format for repositories created after July 15, 2026, to an
immutable, numeric-ID-based format:
`repo:owner@ownerId/repo@repoId:ref:refs/heads/main` (and
`...:pull_request` for PR-triggered runs). `ce-capstone-Bouncer` was
created after that date, so its real tokens were issued in the new
format — the trust policy's plain-name condition never matched, and
`AssumeRoleWithWebIdentity` denied the request without explaining why.

## Resolution

Rebuilt the trust policy's `sub` conditions using the correct immutable
format, with the actual owner ID (`264168469`) and repo ID
(`1350568928`):
- `repo:lojt-cloud@264168469/ce-capstone-Bouncer@1350568928:ref:refs/heads/main`
- `repo:lojt-cloud@264168469/ce-capstone-Bouncer@1350568928:pull_request`

Confirmed working via a successful OIDC-authenticated plan run.

## Prevention

When OIDC federation fails with a vague "not authorized" error, check the
actual token claims against the trust policy condition rather than
assuming the trust policy syntax itself is wrong — documentation examples
may not reflect a recent provider-side format change. The exact working
`sub` patterns are recorded in `00-shared-context.md` so any future
rebuild of this role's trust policy (or a new role) uses the correct
format immediately instead of rediscovering this.