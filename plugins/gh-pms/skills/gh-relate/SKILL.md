---
name: gh-relate
description: Manage relationships between issues — depends-on, blocks, related-to, duplicate-of. Encodes the link in the issue body's structured sections AND uses GitHub's native cross-references so the relationship appears in both timelines. Auto-invoke when the user says "X depends on Y", "Y blocks X", "X is related to Y", "X is a duplicate of Y".
---

# gh-relate

Encode a relationship between two issues so both ends see it.

## Supported relationship kinds

| Kind | Body section on source | Reverse section on target | Special behavior |
|---|---|---|---|
| `depends_on` | `## Depends on` | `## Blocks` | source can't go to in-progress until all deps closed |
| `blocks` | `## Blocks` | `## Depends on` | inverse of depends_on |
| `related_to` | `## Related to` | `## Related to` | bidirectional, no semantic constraint |
| `duplicate_of` | `## Duplicate of` | `## Has duplicates` | source is auto-closed with reason "not planned" |

## Usage

User says: `#42 depends on #38 #39` → run:
```bash
${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh issue-relate 42 "Depends on" "#38"
${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh issue-relate 42 "Depends on" "#39"
${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh issue-relate 38 "Blocks" "#42"
${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh issue-relate 39 "Blocks" "#42"
```

User says: `#100 is a duplicate of #87` → run:
```bash
${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh duplicate-of 100 "#87"
```
(This appends `## Duplicate of` on #100, comments on #87, and closes #100 with `not planned` reason.)

## What it does

1. For each `(source, kind, target)` triple:
   - Append the link to source's body under the right section (creates the section if absent)
   - Append the inverse link on target's body
   - Post a one-line comment on each side: `🔗 {kind} {target}` so the timeline shows it natively
2. For `duplicate_of`, additionally close the source via `gh issue close --reason "not planned"`
3. Report:
   ```
   Linked:
     #42 depends on #38, #39
     #38 blocks #42
     #39 blocks #42
   ```

## Native cross-references

GitHub auto-renders `#N` in issue bodies as a clickable cross-reference and posts the timeline event automatically. So the body edits alone create the visible link — no extra API call needed for the cross-reference itself.

## Notes

- `depends_on` is enforced lightly: `gh-current` will warn if you try to start an issue with unclosed dependencies, but won't block (some teams parallelize anyway).
- `duplicate_of` is the only kind that mutates issue state (closes the source).
- For PRs that close issues, use `Closes #N` in the PR body — that's a separate native keyword handled by the `pre-pr-create` hook.
