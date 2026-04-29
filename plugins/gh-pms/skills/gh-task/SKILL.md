---
name: gh-task
description: Add a task — either a sub-sub-issue under a feature, or (for trivial work) a checkbox in the parent feature's body. Use when a feature has internal steps that need tracking but don't warrant their own issue. The skill decides between sub-issue vs. checkbox based on estimated effort.
---

# gh-task

Add a task to an existing feature.

## When to use

- A feature has multiple discrete steps that should be tracked
- The user says "add a task to #N", "track sub-step X under #N"
- During breakdown, when a step is too small to warrant its own issue

## Decision: sub-issue vs. checkbox

| Effort | Mechanism |
|---|---|
| < 30 min, no separate verification needed | Checkbox in parent feature body |
| ≥ 30 min OR has its own evidence | Real sub-issue with `type:chore` or `type:feature` (kind decided by user) |

## Inputs

Required:
- `parent` — feature issue number the task hangs off
- `description` — what the task is

Optional:
- `severity` — `critical | high | medium | low`. Defaults to **the parent feature's severity** (read the parent's `severity:*` label, or its Project v2 `Severity` field if a project is attached). Override only when the task is meaningfully more or less urgent than its parent. Resolved against `workflows/default.yaml.severities.values[]`.
- `kind` — `chore` or `feature`, defaults to `chore` for sub-issue path.

## What it does — sub-issue path

1. Resolve severity: use the explicit `severity` if provided, else read the parent's `severity:*` label (or Project v2 `Severity` field), else fall back to `workflows/default.yaml.severities.default`.
2. Same flow as `/gh-pms:gh-feature` with kind=chore (or kind specified) — pass the resolved severity through.
3. Calls `mcp__github__sub_issue_write` to link as sub-issue of parent feature.
4. Reports child issue number and the resolved severity (note whether it was inherited or overridden).

## What it does — checkbox path

1. Reads parent feature body via `mcp__github__get_file_contents` (or `issue_read`)
2. Locates the `## Tasks` section (creates if missing)
3. Appends `- [ ] {task description}` (severity is implicit — checkboxes inherit the parent's severity, no annotation needed)
4. Updates issue via `mcp__github__issue_write` with `update_issue` action
5. Reports: `Added task to #N: {description}`

## Cross-skill contract

When the agent finishes a checkbox-task, it must `update_issue` to flip `- [ ]` → `- [x]`. This is a "free transition" (no gate). Don't wait until end of feature to batch — flip them as you go (mirrors Sentra Hub Rule 17 — Plan Progress Tracking).
