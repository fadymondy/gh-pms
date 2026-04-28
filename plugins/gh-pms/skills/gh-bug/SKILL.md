---
name: gh-bug
description: File a bug report as a GitHub issue with `type:bug`. Auto-invoke when the user says "fix bug", "report bug", "X is broken", "Y crashes", "Z returns wrong data". Mirrors Orchestra MCP's `create_bug_report`. Bugs auto-skip Gate 3 (docs).
---

# gh-bug

Create a bug-report issue. Bugs follow the same lifecycle as features but Gate 3 (docs) is auto-skipped per the workflow definition.

## When to use

- User reports a defect
- Regression discovered in testing
- A feature post-merge produces unexpected behavior

## What it does

1. Asks the user (only if not provided):
   - `title` — what's broken (e.g. "Login redirects to 404 after 2FA")
   - `steps_to_reproduce` — bullet list
   - `expected` — what should happen
   - `actual` — what actually happens
   - `services` — affected `svc:*` labels (optional)
   - `severity` — `critical | high | medium | low` (default `medium`)
   - `related_feature` — original feature issue number if this is a regression (optional)

2. Reads template from `${CLAUDE_PLUGIN_ROOT}/templates/bug.md`

3. Calls `mcp__github__issue_write`:
   - `title`: `[Bug] {title}`
   - `body`: filled template
   - `labels`: `type:bug`, `status:todo`, `severity:{severity}`, `svc:*`
   - `assignees`: omit unless user explicitly assigns

4. If `related_feature` provided, comments on the original feature: `Regression filed: #{N}`

5. Reports issue number + URL.

## Severity → label color mapping

The `gh-init` skill creates these severity labels (run init first if missing):
- `severity:critical` (#B60205)
- `severity:high` (#D93F0B)
- `severity:medium` (#FBCA04)
- `severity:low` (#0E8A16)

If they don't exist, create them on the fly via `gh label create`.

## Cross-skill contract

Bug → `gh-current` → fix → `gh-advance` (Gate 1: in-progress → ready-for-testing) → tests → `gh-advance` (Gate 2: in-testing → ready-for-docs). **Gate 3 is auto-skipped for bugs**, so the next transition is `ready-for-docs → documented` directly. Then `gh-review` (Gate 4) → user approves (Gate 5).
