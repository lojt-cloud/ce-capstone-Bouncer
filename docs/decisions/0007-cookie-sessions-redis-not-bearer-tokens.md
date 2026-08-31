# ADR 0007: Session and lockout state in Redis via cookies, not proj2's bearer tokens

## Status
Accepted

## Context
The login/lockout port for `/login`, `/logout`, `/me` was built from
`ce-project-2-instrumented-monitored-service`, which authenticates with
bearer tokens (`Authorization: Bearer <token>`) backed by an in-memory
`sessions` dict, and deliberately runs a single Gunicorn worker so that
in-memory state stays consistent. Bouncer's compute module runs the app
across 3+ EC2 instances in an ASG behind an ALB with no session
affinity — an in-memory dict on one instance is invisible to the other
two, and a request can land on any instance on any call. The module
brief also specifies secure/httpOnly/sameSite cookies, not bearer
tokens.

## Decision
Switch to Flask cookie-based sessions (opaque `session_id` in an
`HttpOnly`, `SameSite=Lax` cookie) and move both the login-lockout
counters and the session data itself into ElastiCache Redis — not just
the lockout counters, despite the brief's literal wording. A
multi-instance app behind a load balancer is exactly the scenario
proj2's own single-worker design doesn't cover; porting only the
lockout half would silently reintroduce the same shared-state bug the
brief exists to fix, just for sessions instead of lockout attempts.

## Consequences
Every authenticated request now costs a Redis round trip (`/me` does a
`GET` plus a sliding-TTL `EXPIRE`), instead of an in-process dict
lookup — an acceptable trade for correctness across 3+ instances.
`SESSION_COOKIE_SECURE` currently defaults `false` since the ALB is
HTTP-only; this needs to flip to `true` once the Route53+ACM HTTPS
listener ships. If ElastiCache is ever destroyed (tied to RDS's
`enable_billable_resources` toggle), all active sessions and lockout
counters are wiped along with it — acceptable since neither holds data
of record.