# Incident 0008: psycopg version pin incompatible across Python runtimes, ~40-minute ASG instance-refresh failure loop

**Date:** 2026-08-31
**Module:** Data tier (app dependencies, deployed via compute's launch template)
**Severity:** Medium — no data loss, but a real ~40-minute outage-shaped failure loop in a live ASG before being caught.

## Summary
After switching from `psycopg2-binary` to `psycopg[binary]` (psycopg3)
to fix a build failure on a Python 3.14 dev laptop, `requirements.txt`
pinned an exact version, `psycopg[binary]==3.3.4`. That installed fine
locally. Deployed to the ASG, every replacement instance failed to
boot: `user_data.sh.tpl`'s `pip install -r requirements.txt` errored,
`set -euo pipefail` aborted the script before `systemctl start
bouncer-app` ever ran, and the instance never passed its ALB health
check. The ASG's rolling instance refresh cycled through 5+ replacement
instances over roughly 40 minutes, stuck around 33% complete.

## Root cause
AL2023's bundled Python ships an old enough `pip` (21.3.1) that its
resolver only sees `psycopg[binary]` wheels up to `3.2.13` — it cannot
resolve `3.3.4` at all. The dev laptop's newer Python resolved a
`3.3.4` wheel without issue, so local testing had no way to catch this:
the two environments resolve different releases for the identical
exact pin.

## How it was caught
The EC2 console's "status check" column showed instances passing
(3/3) — a different signal from the ALB target-group health the ASG
actually uses for refresh decisions. `aws ssm start-session` failed
with `TargetNotConnected` (the SSM agent never got that far in boot),
so `aws ec2 get-console-output --instance-id <id>` was used instead —
reads the serial console directly, no SSM agent required — and showed
the exact `pip` resolver error.

## Resolution
Changed `requirements.txt` to version ranges: `psycopg[binary]>=3.2,<4.0`
and `psycopg-pool>=3.2,<4.0`, letting each environment resolve its own
compatible release. Cancelled the stuck refresh
(`aws autoscaling cancel-instance-refresh`), redeployed via
`app/deploy.sh`; new refresh succeeded cleanly.

## Prevention / lesson
Don't exact-pin a dependency that has to install cleanly on both a dev
machine and a specific, possibly-older AMI runtime — use a version
range. When an ASG instance refresh churns without obvious cause, check
`get-console-output` before assuming it's just slow; EC2 status checks
passing is not evidence the app itself booted.