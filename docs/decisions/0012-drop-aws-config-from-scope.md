# ADR 0012: Drop AWS Config from Scope

**Status:** Accepted
**Date:** 2026-09-02

## Context

`05-product-security.md`'s task checklist (item 6) originally scoped in
enabling AWS Config with 1-2 managed rules (e.g. no public S3 buckets,
restricted SSH) alongside the WAF web ACL and Route53/ACM work. With
build time short, a call had to be made on what to cut.

## Decision

AWS Config is dropped from this project's scope entirely, in favor of
spending the remaining time finishing and live-verifying the WAF web ACL
(Log4j managed rule + rate-based rules on `/login` and `/buy`).

This is not a rubric-impacting cut. AWS Config was never one of the 4
counted Advanced-requirement picks (Auto Scaling, RDS, ElastiCache,
Route53+ACM — all 4/4 done elsewhere in this project) or the Excellence
pick (Checkov custom policies, which is `06-observability-cost`'s job).
It was scoped into this module's own task checklist on top of the
graded picks, not because the rubric required it.

## Consequences

- No live AWS Config recorder or managed rules in this account. Runtime
  configuration drift (e.g. a security group rule loosened by hand after
  an apply) will not be flagged automatically — it would only surface on
  the next `terraform plan`/`apply` or a manual audit.
- Checkov's static IaC scanning (already running on every PR, see
  `04-cicd.md`) is the compensating control for configuration compliance
  going forward, but it is a different class of control: Checkov checks
  the Terraform source before it's applied, not the live resource state
  afterward. It does not replace Config's continuous drift detection —
  that gap is accepted, not papered over.
- If this project were carried into production, AWS Config (with the
  same "no public S3 buckets" / "restricted SSH" managed rules originally
  scoped here) would be the natural addition to close this gap.
