# Incident Report 0017: Data-tier RDS/ElastiCache write-path IAM gaps on first real create

**Date:** 2026-09-01
**Severity:** Blocking (data-tier layer bring-up), no production/data impact
**Status:** Resolved

## Summary

Bringing data-tier's RDS instance and ElastiCache replication group up for
the first real time through the CI deploy role (`ce-capstone-bouncer-deploy`)
— via `terraform-apply.yml`, not a local admin apply — took two follow-up
PRs (#57, #58) after the initial toggle-flip PR (#55) before a
`terraform apply` of `terraform/environments/dev/data-tier` actually
succeeded end to end. `enable_billable_resources` had only ever been tested
at `false` (a 0-change no-op) for this layer before this session, so nothing
about creating RDS/ElastiCache through the deploy role — as opposed to
through local admin credentials — had ever been proven. This was the third
and final layer to go through this exact class of first-real-write-path
exercise, after foundation's NAT Gateway and compute's ASG (Incident Report
0015).

No data loss, no security exposure, no cost impact beyond normal CI minutes.

## Impact

Data-tier bring-up blocked across three apply attempts spanning roughly
45 minutes of active debugging, two of which failed near-instantly (~20-25s,
an IAM AccessDenied surfacing before any resource work began) and one of
which failed after RDS had already spent ~7 minutes creating successfully —
meaning the ElastiCache failure on that attempt cost a real ~7-minute wait
before the error was visible.

## Timeline (all times 2026-09-01, UTC)

- **~15:18** — PR #55 merged (`enable_billable_resources = true` for
  data-tier). First real apply fails within 26s, two errors in the same
  run:
  `AccessDenied: ... elasticache:CreateReplicationGroup ... on resource:
  arn:...:elasticache:...:parametergroup:*`, and
  `AccessDenied: ... rds:CreateDBInstance ... on resource:
  arn:...:rds:...:subgrp:ce-capstone-bouncer-dev-db`.
- **~15:20** — Root cause found: both actions are multi-resource-type IAM
  actions. `rds:CreateDBInstance` checks authorization against both the
  `db:` ARN (already granted) and the `subgrp:` ARN of the subnet group it
  attaches to (not granted — `RDSInstanceManage` only covered `db:`).
  `elasticache:CreateReplicationGroup` checks against both `replicationgroup:`
  (already granted) and `parametergroup:` (not granted) — and since no
  custom parameter group is configured, AWS's own AccessDenied message
  names a literal `parametergroup:*` wildcard rather than a specific
  default-group ARN, because the default group's name is chosen by the
  service, not known to the caller ahead of time.
- **~15:24** — Fixed (PR #57): added the `subgrp:` ARN to
  `RDSInstanceManage`'s `resources` array, and the `parametergroup:*`
  wildcard to `ElastiCacheReplicationGroupManage`'s `resources` array — no
  action or condition changes, both statements' actions were already
  correct.
- **~15:28** — Merged, apply reruns. `aws iam simulate-principal-policy`
  confirmed both actions/resources `allowed` immediately after the policy
  update landed, but the real apply still failed with the *identical*
  errors 0.5-1s after `CreatePolicyVersion` itself reported complete.
  Suspected propagation lag rather than a logic error, given the tight
  timing and the simulate confirmation.
- **~15:30-15:39** — `gh run rerun --failed` with no code change. This
  attempt ran 7m42s: RDS created successfully (`db-SLCB3MTNGOXNQ2NO4TB725SJNM`),
  confirming the propagation-lag theory. ElastiCache then failed with a
  *new* error: `AccessDenied: ... elasticache:CreateReplicationGroup ...
  on resource: arn:...:elasticache:...:subnetgroup:ce-capstone-bouncer-dev-cache`
  — a *third* resource type for the same action, only reachable once the
  first two were already fixed.
- **~15:41** — Fixed (PR #58): added the `subnetgroup:` ARN to the same
  `ElastiCacheReplicationGroupManage` statement.
- **~15:44** — Merged, apply reruns. Fails again within 23s — identical
  `subnetgroup:` error despite the fix being confirmed correct via a
  second `simulate-principal-policy` check. Same propagation-lag pattern
  as before.
- **~15:44-15:51** — `gh run rerun --failed`, no code change. Succeeds:
  RDS already existed from the prior partial apply (no-op this run),
  ElastiCache replication group created successfully. Full apply green.
- **~16:05-17:29** — Live verification: SSM into an app instance, `psql`
  over TLS to RDS (schema empty — pre-existing instances predated RDS,
  never ran self-heal); triggered an ASG instance refresh; reconnected,
  confirmed `users` table self-healed on the fresh boot; confirmed
  ElastiCache reachable via `valkey-cli` (`PING` → `PONG`, TLS+AUTH);
  built and ran `scripts/reseed-test-user.sh` to seed a test row and
  confirm `/login` end to end (`200` + `Set-Cookie`); ran the 5-attempt
  lockout proof against the real ALB (`401`×5, `423 LOCKED` on the
  correct-password retry).

## Root Cause

Two independent, previously-unexercised write-path permission gaps, plus a
timing artifact that doubled the number of apply attempts needed:

1. `rds:CreateDBInstance` is a multi-resource-type action requiring
   authorization on both the `db:` and `subgrp:` ARNs it references — only
   `db:` was granted.
2. `elasticache:CreateReplicationGroup` is a multi-resource-type action
   requiring authorization on `replicationgroup:`, `parametergroup:` (as a
   wildcard, since the default parameter group's name isn't known to the
   caller), and `subnetgroup:` — only `replicationgroup:` was granted
   initially; `parametergroup:*` and `subnetgroup:` each surfaced only once
   the previous gap was fixed and the create call progressed further.
3. **Timing artifact, not a coverage gap:** on both fixes, the very first
   apply attempt after the policy update failed with the exact same error
   the fix was meant to resolve, despite `simulate-principal-policy`
   confirming the live policy already allowed it. Both times, a plain rerun
   ~1 minute later succeeded with zero code changes. IAM policy changes are
   not always instantly visible to every evaluation path, even after the
   `CreatePolicyVersion` API call itself returns success.

All three gaps are instances of this project's recurring "looks scopeable,
isn't" IAM pattern (see `00-shared-context.md`'s "CI/CD auth facts," cases
13-15) — consistent with foundation's and compute's own first-real-write
experiences (Incident Report 0015): a gap that's invisible on `plan`
(read-only) and invisible on a `0 changes` apply, and only surfaces the
first time the deploy role is actually asked to create the resource for
real.

## Resolution

Both permission gaps fixed and verified against the real OIDC-assumed
deploy role. Final state of `ce-capstone-bouncer-dev-deploy-data-tier`:
`RDSInstanceManage`'s `resources` array covers `db:` and `subgrp:`;
`ElastiCacheReplicationGroupManage`'s `resources` array covers
`replicationgroup:`, `parametergroup:*`, and `subnetgroup:`. All three
grants are scoped ARNs (or a service-mandated wildcard for the one resource
type whose name isn't caller-controlled), not a broad `Resource: "*"` —
unlike compute's ADR-0010 precedent, no least-privilege trade-off was
needed here since every resource type involved does support resource-level
scoping.

## Prevention / Follow-up

- When an RDS or ElastiCache action 403s on a resource type that wasn't
  the obvious target of the call (a subnet group, a parameter group), check
  AWS's own service-authorization reference for that action's full list of
  resource types *before* assuming the fix is complete after adding the
  first one — both `CreateDBInstance` and `CreateReplicationGroup` in this
  incident needed more than one resource type, and the second/third ones
  only became visible after the first was already fixed.
- When a policy fix that `simulate-principal-policy` confirms as `allowed`
  still fails identically on the very next real apply, don't immediately
  assume the fix is wrong — check the elapsed time since the policy update
  landed. A plain rerun a minute or so later is the fastest way to
  distinguish genuine propagation lag from a real remaining gap, and costs
  far less than another round of policy edits chasing a problem that isn't
  there.
- This closes out the last of the three flagged "open risk, first real
  write-path exercise" items (foundation's NAT Gateway, compute's ASG/ALB,
  data-tier's RDS/ElastiCache) — all three layers have now been created for
  real through the deploy role at least once, so this specific class of gap
  (a write path that `plan` alone can never surface) is no longer an open
  risk for any existing layer. It remains a standing risk for any *new*
  resource type a future module adds.