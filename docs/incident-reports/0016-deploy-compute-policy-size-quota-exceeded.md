# Incident Report 0016: deploy-compute IAM policy exceeded 6,144-char size quota

**Date:** 2026-09-01
**Severity:** Blocking (compute layer bring-up), no production/data impact
**Status:** Resolved

## Summary

While fixing the missing `ec2:RunInstances` permission documented in
Incident Report 0015, adding the new statement(s) pushed
`ce-capstone-bouncer-dev-deploy-compute` over IAM's hard 6,144-character
managed-policy size quota. This is the third time this project has hit this
exact quota (twice during compute's original build, per
`claude/cicd-checkov-interview-qa.md`; this is the first time since).

## Impact

One failed apply (`LimitExceeded: Cannot exceed quota for PolicySize: 6144`
on `iam:CreatePolicyVersion`) and one extra PR/merge/apply cycle
(~10 minutes) before the underlying `ec2:RunInstances` fix from Incident
Report 0015 could actually land.

## Timeline

- **~14:04** — PR #49 adds two new statements for `ec2:RunInstances`
  (one scoped to everything except the launch-template resource, a second
  covering the launch-template resource itself). Plan and PR checks pass —
  Checkov and `terraform fmt` don't check policy-document byte size.
- **~14:13** — Real apply fails: `operation error IAM: CreatePolicyVersion
  ... LimitExceeded: Cannot exceed quota for PolicySize: 6144`. Because the
  policy update never lands, the *same* run's ASG-create step still shows
  the old "not authorized to use launch template" error — initially
  ambiguous whether the RunInstances fix itself was wrong, or just never
  applied.
- **~14:14** — Measured the actual compact-JSON size of the proposed policy
  (6,191 bytes, 47 over budget) and got a per-statement size breakdown to
  target the fix precisely, rather than guessing which statement to trim.
- **~14:15** — Identified `AppRoleAttach` and `DeployRoleAttach` as the best
  merge candidates: both statements granted the identical three
  `iam:*RolePolicy`/`iam:ListAttachedRolePolicies` actions, just to two
  different role/policy pairs. Merged into one `RoleAttach` statement using
  array `Resource` and array `iam:PolicyARN` condition values — saved 161
  bytes (new total 6,030/6,144, 114-byte margin) without cutting any real
  permission.
- **~14:23** — Consolidated policy applies cleanly. (The underlying
  `ec2:RunInstances` issue from Incident Report 0015 was still unresolved
  at this point and took several more fixes — this incident is scoped to
  the size-quota problem specifically.)

## Root Cause

IAM managed policies have a hard 6,144-character limit on the compact
(no-whitespace) JSON representation, not adjustable. This project's
`ce-capstone-bouncer-dev-deploy-compute` policy has grown incrementally
across the compute module's original build and this session's bring-up
work, and periodically needs active budget management as new statements are
added — it doesn't fail gracefully or warn in advance; it only surfaces as
a hard `LimitExceeded` on the next `CreatePolicyVersion` call that pushes it
over.

## Resolution

Merged two near-duplicate statements (`AppRoleAttach` + `DeployRoleAttach`
→ `RoleAttach`) to reclaim 161 bytes of budget, no permissions cut. See
`SECURITY.md` for the trade-off this consolidation accepts (either of
compute's two scoped policies can now attach to either of its two target
roles, not strictly the original one-policy-one-role pairing — assessed as
low real risk given both policies and both roles are fixed, known, and
narrowly scoped).

## Prevention / Follow-up

- Before adding new statements to `ce-capstone-bouncer-dev-deploy-compute`
  (or any deploy-role policy nearing this pattern), measure the actual
  compact-JSON size first:
  ```
  cd terraform/environments/dev/<layer>
  terraform console <<< 'data.aws_iam_policy_document.deploy_<layer>.json' \
    | python3 -c "import json,sys; print(len(json.dumps(json.load(sys.stdin), separators=(',',':'))))"
  ```
  A comfortable margin (a few hundred bytes) is worth maintaining
  proactively rather than discovering the quota reactively via a failed
  apply.
- When trimming is needed, prefer merging statements that already share the
  same actions across different resources/conditions (as done here) over
  dropping `Sid`s again (already done in the original build) or cutting
  real permissions.
- If this policy approaches the quota again, splitting compute's deploy
  permissions across two managed policies attached to the same role (both
  under `ce-capstone-bouncer-dev-deploy-compute-*`) is the next lever
  before any permission has to be cut — not attempted here since the
  161-byte merge was sufficient.