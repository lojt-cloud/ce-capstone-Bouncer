# 0014 — SNS subscription actions have no resource-level IAM support

**Date:** 2026-09-01
**Severity:** Low (caught in CI before merge, no production impact)
**Status:** Resolved

## Summary

Building the deploy-role IAM policy for the new drift-alerts SNS topic
(`terraform/environments/dev/foundation/drift-alerts.tf`), two permission
gaps surfaced in sequence under CI's real OIDC-assumed role, even though
each fix looked complete and matched this project's established scoping
conventions.

## Impact

None realized — both gaps were caught by `terraform plan` failing in CI
before merge, never in a production apply.

## Root Cause

**Gap 1 — missing read permission.** Only `sns:Publish` had been granted
(the action the drift-detection workflow actually needed to *use*), but
`terraform plan`'s refresh step also needs to *read* the topic
(`sns:GetTopicAttributes`) on every plan. Same shape as this project's
earlier `HeadBucket`/`s3:ListBucket` and `CreateNatGateway`/EIP gaps:
write-only scoping without the read permission Terraform itself needs to
manage the resource.

**Gap 2 — no resource-level support at all.** After granting
`sns:GetSubscriptionAttributes`, `sns:SetSubscriptionAttributes`, and
`sns:Unsubscribe` scoped to `<topic-arn>:*` (the SNS subscription ARN
pattern), CI still 403'd on the exact same actions. Live-checked the
actual attached policy JSON via `aws iam get-policy-version` to rule out
a stale/unapplied version — it matched intent exactly. Root cause
confirmed via AWS's own SNS service-authorization reference
(https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonsns.html):
these three actions have **no resource type defined at all** for SNS —
Amazon SNS only defines a `topic` resource type for IAM purposes, no
`subscription` resource type exists. A scoped ARN, even a syntactically
valid wildcard under the topic, is silently never evaluated as a match;
these actions require `Resource: "*"`.

## Resolution

- Added a `DriftAlertsPublish`-style statement granting the topic's full
  lifecycle (`CreateTopic`, `DeleteTopic`, `GetTopicAttributes`,
  `SetTopicAttributes`, tag actions, `Publish`, `Subscribe`) scoped to
  the topic's exact ARN.
- Added a second statement for `Unsubscribe`, `GetSubscriptionAttributes`,
  `SetSubscriptionAttributes` with `Resource: "*"` — the only valid form
  for these three actions, not a scoping compromise.
- Both verified against the real OIDC-assumed deploy role via CI, not
  personal/admin credentials (local applies always work regardless of
  the deploy role's actual scope, so they never catch this class of gap).

## Prevention / Lessons Learned

This is the third confirmed case this project has hit of "an action
reads as scopeable in casual policy-writing but AWS never actually
implemented resource-level permission support for it" (after
`HeadBucket`/`s3:ListBucket` and `CreateNatGateway`/EIP). Before writing
a scoped-ARN statement for a new AWS action/resource-type combination —
especially one that "looks like" it should support scoping by analogy
with a sibling action — check AWS's service-authorization reference page
for that service first
(https://docs.aws.amazon.com/service-authorization/latest/reference/)
and confirm the specific action actually lists a resource type. A clean
local `terraform plan` under personal credentials proves nothing about
this — only a real run under the actual deploy role does.
