---
name: gh-plan
description: Create a multi-feature plan as a GitHub Milestone (preferred) plus a tracker issue. Use when the user request would result in 3+ features. Mirrors Orchestra MCP's `create_plan`. The milestone groups child issues; the tracker issue holds the high-level objective and breakdown checklist.
---

# gh-plan

Create a plan. v0.2 prefers GitHub **Milestones** as the plan primitive — they have native progress tracking (closed-issue %), due dates, and integrate with sub-issues, projects, and search.

## When to use

- User says "plan X", "design Y", "let's plan how to do Z"
- A user request decomposes into 3+ features
- Before any implementation in a multi-step effort

## What it does

### Step 1 — Collect inputs

Required:
- `title` — short, imperative ("Migrate auth flow to bridge")
- `objective` — 1–3 sentences

Optional:
- `due_date` — ISO-8601 (e.g. `2026-06-01`); empty = no due date
- `services` — list of `svc:*` labels
- `prd` — parent PRD issue number (if any)

If missing, ask via plain text.

### Step 2 — Create the milestone

```bash
${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh ensure-milestone "{title}" "{objective}" "{due_date_iso or empty}"
```

This returns the milestone number `M`. Idempotent — if a milestone with this exact title exists, returns its number.

### Step 3 — Create the tracker issue

Use `mcp__github__issue_write`:
- `title`: `[Plan] {title}`
- `body`: filled `templates/plan.md` (substitute `{{title}}`, `{{objective}}`, `{{services}}`)
- `labels`: `type:plan`, `status:todo`, plus `svc:*` if known
- `milestone`: M (set via `gh issue edit {N} --milestone "{title}"` after creation, since MCP issue_write may not support milestone field directly)

If the repo has Issue Types (gh-init detected this), DO NOT set issue type — plans aren't issue types in the GitHub model (they're milestones). The tracker issue gets `type:plan` label only.

If a project is attached, add the tracker issue to it via `${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh project-item-add` and set its `Status` field to `Todo`.

If `prd` was given, comment on the parent PRD issue: `Plan #{N} created — see milestone #{M}.`

### Step 4 — Report

```
Plan created:
  Milestone #{M}: "{title}"  (due: {due_date or "no due date"})
  Tracker:    #{N} (type:plan, status:todo)
  URL:        https://github.com/{owner}/{repo}/milestone/{M}
Next: /gh-pms:gh-breakdown #{N} to add features as sub-issues attached to milestone #{M}
```

## Cross-skill contract

After creating the plan, do NOT immediately start implementation. Always run `/gh-pms:gh-breakdown` next.

## Notes

- Plans = Milestones (the primary primitive). The tracker issue exists for narrative context, breakdown checklist, and conversation.
- Milestone progress = % of attached issues closed. GitHub renders it as a progress bar on the milestone page.
- When ALL sub-issues close, run `${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh close-milestone {M}` and close the tracker issue with a "completed" comment.
