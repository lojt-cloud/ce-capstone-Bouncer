# Incident 0005: Uncommitted SECURITY.md edit lost across a branch switch

## Summary
A local SECURITY.md edit made during the compute module was believed to
be pushed and merged (PR #14), but the merge diffstat didn't include
SECURITY.md at all -- the edit didn't exist in any commit on any branch.

## Root cause
The edit was saved to disk but never staged (`git add`) before other git
operations ran on the same branch (further commits, push, PR merge with
`--delete-branch`). `git log --all -- SECURITY.md` showed no commit newer
than an unrelated PR from a previous session; `git status` showed a clean
working tree; VS Code's Timeline panel only retained saves from the
previous day. The edit was unrecoverable and had to be rewritten from
context.

## Fix
Rewrote the lost SECURITY.md section from the session's own record of
what the compute module actually built (IMDSv2, SSM-only access, ALB
HTTP-only pending Route53/ACM, least-privilege IAM, etc.), then committed
it through its own small PR (#15).

## Lesson
Before trusting a `git status` / merge diffstat as proof a change is
safely committed, confirm the specific file(s) actually appear in it --
"pushed" and "merged" don't guarantee "staged." Run `git add -A && git
status` immediately after editing a doc file, before doing anything else
on that branch, rather than assuming an edit is captured because it was
saved.