---
name: gh-bulk
description: Apply a single action to many issues at once — bulk-label, bulk-close-stale, bulk-reassign, bulk-set-severity. Always lists matches and asks for confirmation before applying. Auto-invoke when the user says "close all stale", "label everything in svc:X", "bulk update".
---

# gh-bulk

Run a controlled bulk operation across a query'd set of issues. The skill never applies anything until the user confirms the target list.

## When to use

- Backlog hygiene: "close all `type:request` issues from before Q1"
- Re-tagging after a service rename: "everything currently `svc:bridge` becomes `svc:api`"
- Reassigning after a team change: "all issues assigned to @alice → @bob"
- Severity recalibration: "all open `type:bug` without a severity → `severity:medium`"

## Inputs

```
gh-bulk --query "<github-search-query>" --action <action> [--value <value>] [--reason <text>] [--yes]
```

| Flag | Required | Effect |
|---|---|---|
| `--query` | yes | A GitHub search query (`gh issue list --search`). Examples: `is:open type:request created:<2026-01-01`, `is:open svc:bridge no:assignee`. |
| `--action` | yes | One of: `label`, `unlabel`, `close`, `reassign`, `set-severity`, `set-effort`, `comment`. |
| `--value` | depends | The argument for the action: label name (`label`/`unlabel`), assignee handle (`reassign`), severity name (`set-severity`), effort tier (`set-effort`), comment body (`comment`). Not used for `close`. |
| `--reason` | for `close` | Free-text close reason; appended to a `## Bulk close reason` section in the issue body and posted as a one-line comment for audit. |
| `--yes` | no | Skip the confirmation prompt. **Use only when scripting**; default flow always confirms. |

## What it does

### Step 1 — Resolve the target list

```bash
gh issue list --search "$QUERY" --state all --limit 200 --json number,title,labels,state,createdAt
```

If empty, report `No issues match the query. ✓` and exit.

### Step 2 — Confirm with the user

Always — unless `--yes`. Show the matches via `AskUserQuestion`:

```
Bulk action: <action> "<value>"
Target: 17 issues
Sample (first 5):
  #82  [Bug] Token refresh fails on Safari   created 2025-11-04
  #91  [Request] Add MCP for Vercel          created 2025-12-01
  #103 [Feature] Backfill historical data    created 2026-01-12
  ...
```

Options: `Apply`, `Show all`, `Refine query`, `Cancel`.

- **Apply** → Step 3
- **Show all** → list every match, then re-prompt
- **Refine query** → exit; user runs again with a tighter query
- **Cancel** → exit silently

### Step 3 — Apply

Iterate the matches. Per-action:

| Action | Operation |
|---|---|
| `label` | `gh issue edit {N} --add-label "{value}"` |
| `unlabel` | `gh issue edit {N} --remove-label "{value}"` |
| `close` | `gh issue close {N} --reason "completed"` (or `not planned` if `--reason` starts with "rejected:" or "wontfix:"). Append `## Bulk close reason` to the body via `update_issue`; post a one-line comment with `--reason`. |
| `reassign` | `gh issue edit {N} --add-assignee "{value}"`. If `--value` starts with `-`, that user is REMOVED instead. |
| `set-severity` | Remove any existing `severity:*` label, add `severity:{value}`. Update Project v2 `Severity` field if a board is attached. |
| `set-effort` | Same pattern with `effort:*` and the Project v2 `Effort` field. |
| `comment` | `gh issue comment {N} --body "{value}"`. |

Stop on first failure with the issue number that broke. Print remaining count so the user can re-run from there.

### Step 4 — Report

```
Bulk <action> applied:
  Succeeded: 16
  Failed:    1   (#103 — permission denied)
  Skipped:   0
Re-run with --query "<query that excludes already-applied>" to retry the failures.
```

## Programmatic guardrails

- **Cap at 200 matches** unless `--limit <n>` is passed (max 1000). Enforces a "look before you leap" mindset for accidental wide queries.
- **Never matches `--query 'is:open'`** alone — refuses with "query too broad; add at least one label or kind filter".
- **Refuses to act on closed issues** unless the action is `comment` (some teams comment on closed issues to surface stale follow-ups).
- **Never bulk-merges PRs** — bulk operations are for issues only. PR merges go through `gh-review`/`gh-push` per-issue with the human in the loop.

## Cross-skill contract

- Pairs with `gh-search` (which finds the query) and `gh-triage` (which is the per-item version of bulk-close on `type:request`)
- A bulk close should not move an issue to `status:done` — `done` is reserved for completed-via-PR work. Bulk close uses GitHub's native close-with-reason semantics; the `status:*` label is removed and `closed_at` set.

## Notes

- Out of scope: scheduled bulk operations (run via the `/schedule` skill instead — e.g. weekly stale-request-defer cron)
- Out of scope: cross-repo bulk (run per-repo; cross-repo plans are tracked separately by #14)
