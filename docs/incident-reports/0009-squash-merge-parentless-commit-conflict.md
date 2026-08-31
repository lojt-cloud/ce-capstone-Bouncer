# Incident 0009: Squash-merge produces a parentless commit; a new branch cut from a stale local tip conflicts with main

**Date:** 2026-08-31
**Module:** Data tier (git/PR workflow, not infrastructure)
**Severity:** Low — caught immediately by GitHub's own conflict detection, no bad state merged.

## Summary
PR #23 (a follow-up fix branched after PR #22 was already merged)
showed "This branch has conflicts that must be resolved" on exactly
the two files (`app/src/config.py`, `app/src/requirements.txt`) that
PR #22 had already touched — even though PR #23's branch was a strict
superset of PR #22's changes to those files.

## Root cause
GitHub's squash merge creates a brand-new commit on `main` with no
parent relationship to the original feature branch's commits. PR #23's
local branch had been cut from a checkout still sitting at PR #22's
pre-merge tip — Git can't tell the two versions of those files are
related, even where the content is a strict superset.

## How it was caught
`git push` and `gh pr create` succeeded, but the PR's own mergeability
status flagged the conflict automatically before any merge attempt.

## Resolution
`git fetch origin && git merge origin/main` on the PR branch, confirmed
conflicts were isolated to exactly those two expected files, resolved
with `git checkout --ours app/src/config.py app/src/requirements.txt`
(safe since the branch's content was a confirmed superset), committed
the merge, pushed. PR became mergeable and merged clean.

## Prevention / lesson
Run `git checkout main && git pull` before cutting *any* new branch,
including a quick follow-up fix on work that was just merged — not
just before starting unrelated work. A squash-merged branch's local
copy is stale the instant the PR merges, even if nothing else has
touched `main` since.