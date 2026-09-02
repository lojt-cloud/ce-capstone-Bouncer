# Incident Report 0019: Reused a branch after its PR was squash-merged, producing real merge conflicts and a bad manual resolution

**Date:** 2026-09-02
**Severity:** Blocking (CI/PR flow only), no infrastructure or data impact
**Status:** Resolved

## Summary

While iterating on the deploy-compute IAM fixes in Incident Report 0018,
new commits kept being pushed to the branch backing PR #69 after that PR
had already been squash-merged into `main` (confirmed
`mergedAt: 2026-09-02T11:46:24Z`). Because a squash-merged branch is
"dead" — its PR is closed and further pushes to it don't reopen or attach
to any PR — those commits were invisible to CI in the way expected, which
first looked like a stale/non-firing run and only later revealed itself as
real merge conflicts once a fresh PR (#70) was opened for the same branch.
A first attempt to resolve those conflicts by hand left literal
`<<<<<<< HEAD` conflict markers committed and pushed, breaking
`terraform init` outright.

## Impact

Roughly three extra iterations of confusion before the actual fix (from
Incident Report 0018) could land: one round mistaking "no new run fired"
for a CI problem, one round discovering the real merge-conflict state via
the GitHub UI, and one round recovering from a broken `terraform init`
caused by committed conflict markers. No infrastructure changes were ever
applied from the broken state — CI failed at `terraform init`, before any
plan or apply could run.

## Timeline

- PR #69 (deploy-compute IAM fixes for Incident Report 0018) is merged via
  squash-merge at `2026-09-02T11:46:24Z`.
- Further fix commits (the `route53:GetHostedZone` correction, then the
  `s3:PutObjectTagging` addition) are pushed to the same local branch,
  believing PR #69 to still be open and iterating on it.
- A CI failure is reported (`Terraform Apply` failed), and the pasted log
  turns out to be byte-for-byte identical — same millisecond timestamps —
  to a previously-seen failure. `git log --oneline -3` and
  `gh run list --branch main --limit 3` are used to check push state per
  this project's standing "verify a new run actually fired" lesson; the
  output shows PR #69 still marked failed and no new PR/run reflecting the
  latest pushes at all.
- A screenshot of the GitHub UI for PR #70 (opened once it became clear
  #69 wasn't accepting the new commits) shows "Checks awaiting conflict
  resolution" and "This branch has conflicts that must be resolved" on
  `terraform/environments/dev/compute/deploy-policy.tf`.
- `gh pr view 69 --json state,mergedAt,url` confirms `state: MERGED`,
  `mergedAt: 2026-09-02T11:46:24Z` — establishing that every commit pushed
  after that point had been landing on an orphaned branch with no PR
  attached, and that branch's history had diverged from `main` (which had
  moved on via the squash commit), producing a genuine three-way conflict
  once a new PR tried to merge it back.
- A first attempt to resolve the conflict by hand in
  `deploy-policy.tf` goes wrong: the pushed result contains literal
  `<<<<<<< HEAD` / `=======` / `>>>>>>> origin/main` markers left in the
  file, plus duplicated and partially reverted ACM/Route53/`ReadOnly`
  content. CI fails immediately at `terraform init` with
  `Argument or block definition required` on the line containing the
  marker.
- Recovered by discarding the manual resolution entirely and overwriting
  the whole file with the known-good complete content (the fully corrected
  `deploy-policy.tf` from Incident Report 0018's fixes), rather than
  hand-editing the conflicted region further.
- PR #70 checks pass clean (`gh pr checks 70`), merges, apply succeeds
  (after one propagation-lag rerun, see Incident Report 0018).

## Root Cause

A squash-merged PR closes and its branch stops being "live" from GitHub's
perspective — pushing more commits to it does not reopen the merged PR or
attach the new commits to any PR. Continuing to develop on that branch
after the merge, without noticing the merge had already happened, meant:

1. New work had no PR to report status against, which looked at first like
   a CI/caching problem rather than a process problem.
2. The branch's commit history had diverged from `main` (which had already
   incorporated the squash commit of the *pre-merge* version of the same
   file), so opening a fresh PR against it produced a real, non-cosmetic
   merge conflict — not just a stale PR title.
3. Manually resolving that conflict by hand-editing conflict markers is
   error-prone under time pressure — it's easy to leave markers in place,
   or to accidentally keep the wrong side of the conflict, especially when
   the same statements (ACM, Route53, `ReadOnly`) had been added, reverted,
   and re-added across multiple commits on both sides of the divergence.

## Resolution

- Confirmed the branch's PR was actually merged via
  `gh pr view <n> --json state,mergedAt` before assuming any branch state.
- Opened a fresh PR (#70) for the continuing work instead of trying to
  reattach to the dead PR #69.
- When the fresh PR showed conflicts, discarded the failed manual
  resolution and had the complete, known-good file content pasted in
  wholesale, rather than resolving conflict markers by hand.

## Prevention / Follow-up

- Before pushing new commits to a branch whose PR might already be
  merged, run `gh pr view <n> --json state,mergedAt` first — this project
  already had a documented "verify a new run actually fired" lesson from
  the merge-status angle; this incident adds the branch-reuse angle
  specifically: a squash-merged branch is dead for further development,
  full stop, even if it still exists on the remote.
- Once a PR is confirmed merged, branch from `main` again for the next
  round of changes rather than continuing on the old branch, even if the
  old branch's diff looks like it should still be "mostly there."
- If a merge conflict does appear on a real (non-stale) PR, prefer
  discarding a partial/attempted manual resolution and pasting the
  complete known-good file over reconciling conflict markers by hand —
  established as a standing preference this session after the marker
  mishap above. This is especially true for Terraform files, where a
  leftover marker breaks `terraform init` for the whole run before any
  plan/apply logic even runs, giving a confusing low-level parse error
  rather than an obviously conflict-shaped one.