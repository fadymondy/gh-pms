---
name: gh-reopen
description: Re-enter a `done` issue at `status:in-progress` with a clean audit trail. Auto-creates a fresh feature branch off the protected base. Auto-invoke when the user says "reopen #N", "this regressed", "we need to redo #N".
---

# gh-reopen

Bring a closed issue back into the lifecycle when its work regresses or needs additional follow-up. Closes the gh-pms loop's missing reverse arrow.

## When to use

- User says "reopen #N", "X regressed since release", "we need to fix #N again"
- A `done` feature surfaced a bug that's actually a regression of the original work, not a new defect
- Post-release rework that should re-use the original issue's history rather than spawn a duplicate

## Inputs

```
gh-reopen <issue-number> --reason "<text>" [--force] [--no-branch]
```

| Flag | Required | Effect |
|---|---|---|
| `<issue>` | yes | Closed issue number to reopen. |
| `--reason` | yes | Short why-text. Becomes part of the reopen comment + audit trail. |
| `--force` | no | Bypass the WIP-limit guardrail (assignee already has an in-progress issue). |
| `--no-branch` | no | Skip auto-creating a fresh feature branch. Use only when continuing work in an existing branch. |

## What it does

### Step 1 — Pre-flight

1. Verify the issue is currently closed:
   ```bash
   STATE=$(gh issue view {N} --json state -q .state)
   ```
   If `OPEN`, refuse: "Issue #${N} is already open. Use `/gh-pms:gh-current` to start work on it."

2. Verify WIP guardrail unless `--force`:
   ```bash
   ME=$(gh api user --jq .login)
   gh issue list --assignee "$ME" --label status:in-progress --state open --json number
   ```
   Refuse if non-empty: "You already have an in-progress issue (#${other}). Finish it or pass --force."

### Step 2 — Reopen on GitHub

```bash
gh issue reopen {N}
```

### Step 3 — Reset status

Use the unified setter so label + Project v2 field stay atomic:

```bash
${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh set-status {N} "In Progress"
```

This swaps `status:done` for `status:in-progress` AND updates the Project board's Status field.

### Step 4 — Audit comment

Pull the previous close timestamp and the closing PR (if any) for context:

```bash
PREV_CLOSED=$(gh issue view {N} --json closedAt -q .closedAt)
CLOSING_PR=$(gh issue view {N} --json closedByPullRequestsReferences -q '.closedByPullRequestsReferences | first.number // empty')
```

Post:

```markdown
🔁 Reopened — {reason}

- Previously closed: {PREV_CLOSED}
- Closing PR: {#CLOSING_PR or "—"}
- Reopened by: @{me}
```

### Step 5 — Create a fresh feature branch (unless `--no-branch`)

Same template as `gh-current`, with `kind_short` derived from the issue's `type:*` label:

```bash
SLUG=$(echo "{title}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')
BRANCH="${KIND_SHORT}/${N}-${SLUG}"
git checkout {protected_base}
git pull --ff-only
git checkout -b "$BRANCH"
```

Append the branch name to the audit comment so future visitors see where the rework happened.

### Step 6 — Update local state file

```json
{
  "{N}": {
    "current_status": "in-progress",
    "last_transition_at": "{ISO now}",
    "branch": "{BRANCH}",
    "base": "{protected_base}",
    "reopened_at": "{ISO now}",
    "reopen_count": <prev + 1>
  }
}
```

### Step 7 — Report

```
🔁 Reopened #{N}: {title}
  Reason:        {reason}
  Branch:        {BRANCH}
  Previous PR:   #{closing_pr or "—"}
  Status:        In Progress
  Reopen count:  {n}    ({n}/3 before staleness flag)
Next: do the work, then /gh-pms:gh-advance #{N} or /gh-pms:gh-push #{N}
```

If `reopen_count >= 3`, also surface a warning: this issue has reopened ≥3 times — consider splitting it or filing a follow-up `chore` to address the underlying instability.

## Cross-skill contract

- A reopened issue starts fresh from `in-progress` — it does NOT skip Gates 1-5 just because they passed pre-close. The gates are the source of truth for "is the new work also done".
- `gh-status` and `gh-context` should both surface reopened issues distinctly (e.g. `🔁 #N`) so the team sees recurrence at a glance.
- If the regression is severe (production impact), prefer filing a fresh `gh-bug` linked to the original via `/gh-pms:gh-relate related_to`. Reopen is for "this issue's work needs more iteration", not "this issue caused a critical incident".

## Notes

- Out of scope: reopening a `closed-as-not-planned` (rejected) issue — for those, file a fresh issue if the user changed their mind. Reject means reject.
- Out of scope: re-running gates already passed pre-close. The lifecycle restarts cleanly.
