---
name: gh-validate
description: Dry-run gate validation — check if evidence would pass without actually transitioning. Mirrors Orchestra MCP's `validate_gates`. Use to preview before `gh-advance`.
---

# gh-validate

Test evidence against a gate without performing the transition.

## What it does

Same evidence-validation pipeline as `gh-advance`, but stops after the validation step:

1. Read issue → determine current status + `type:*` label (kind)
2. Determine target status (from user input or natural next)
3. Look up gate. **Per-kind sections**: if the gate has a `required_sections_per_kind[<kind>]` block (e.g. `bug` requires `## Summary`, `## Reproduction`, `## Root cause`, `## Fix`, `## Regression test` instead of the generic `Changes / Verification`), use that list. Per-repo overrides via `.github/gh-pms.yaml` are layered on top.
4. Build evidence from user input (or read it from a draft comment if user says "the comment I just wrote")
5. Run `lib/validate-evidence.sh`
6. Report:
   ```
   Gate {gate_id} dry-run for #{N}:
     ✓ ## Summary (47 chars)
     ✓ ## Changes (3 file paths verified)
     ✗ ## Verification missing
   Result: WOULD FAIL.
   ```

## When to use

- User asks "would this evidence pass?"
- Before posting a long evidence comment, validate it locally
- During PR review when you want to check the original evidence still holds

## Notes

- Does NOT post the evidence comment, does NOT change labels, does NOT touch state file
- Cooldown is NOT enforced on dry-run
- File-path checks DO run (so the file existence check is real)
