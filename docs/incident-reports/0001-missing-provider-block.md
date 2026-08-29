# Incident 0001: Missing Provider Block (No default_tags, No Explicit Region)

**Date:** 2026-08-29
**Module:** Foundation (networking/security/iam)
**Severity:** Low — caught in a pre-close sanity audit, no production impact, nothing public-facing or in use yet.
**Status:** Resolved

## Summary
The root `provider "aws" {}` block (region + `default_tags`) was never
added to `terraform/environments/dev/foundation/main.tf`, despite being
specified early in the build. All three networking/security/iam applies
succeeded anyway, which masked the gap.

## Impact
- **Tags:** 
 every resource in the layer had only its explicit `Name` tag —
  `default_tags` (`Project`, `Environment`, `Layer`, `ManagedBy`) never applied. 
  Tag-based cost allocation and resource discovery for this layer would have been incomplete.

- **Region:**
 with no explicit `region` argument, Terraform fell back to the local AWS CLI's default region. 
 It happened to match (`eu-central-1`), so applies succeeded, but a CI runner (GitHub Actions, OIDC) has no equivalent default. 
 This would very likely have broken, or misdirected, the first CI-driven apply once the CI/CD module wires up the workflow.

## Detection
Found during a post-module sanity audit (least-privilege + defense-in-depth check across the whole layer)
Not by a test or CI check, since none existed yet. Spotted by comparing a resource's actual tags against what `default_tags` should have produced.

## Root cause
The provider block was specified once, early, as part of the initial
layer skeleton. Every module after that (networking, security, iam) was
delivered as an incremental addition to `main.tf` across separate
messages, on the assumption the original provider block was still there.
It wasn't. Most likely dropped when the file was first populated, before
any module blocks existed to make its absence visible. 
Nothing enforced that assumption, no policy check (Checkov/tfsec) was in place yet to
catch a config-level gap like this.

## Resolution
Added the provider block back (region + `default_tags`) and re-applied.
Clean in-place tag update — no resources destroyed or recreated.

## Action items / prevention
- Checkov's custom-policy pass (the priority Excellence requirement)
  should include a check that a `provider "aws"` block with
  `default_tags` exists in every layer's root — catches this class of bug
  automatically instead of relying on a manual audit.
- When a root `main.tf` is built incrementally across sessions,
  sanity-check the whole file (not just the new diff) before the first
  apply of each new chunk.
- Run the tag/region check from this audit as a standard step at the end
  of every future module, not just Foundation.
