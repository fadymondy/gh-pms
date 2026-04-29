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
- `repos` — comma-separated `owner/repo` list to span the plan across multiple repos. The first repo is the **primary** (where the tracker issue lives); each named repo gets its own copy of the milestone. Children filed via `gh-breakdown` route into the right repo based on their `svc:*` label, mapped per-repo in `.github/gh-pms.yaml` under `cross_repo.svc_to_repo`.

If missing, ask via plain text.

### Step 2 — Create the milestone

For a single-repo plan, this is straightforward. For a cross-repo plan (`repos` provided):

1. Create the milestone in **each** named repo with the same title + due date — milestones are repo-scoped, so coordination relies on the shared title.
2. Record each `(repo, milestone-number)` pair on the tracker issue body under a new `## Cross-repo milestones` section so future skills can resolve them.
3. The primary repo's milestone is the canonical anchor for the tracker issue.

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
