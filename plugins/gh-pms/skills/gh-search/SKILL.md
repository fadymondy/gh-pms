---
name: gh-search
description: Ad-hoc issue queries beyond the fixed `gh-status` dashboard. Translates natural-language asks into GitHub search syntax (or accepts raw syntax) and renders results as a compact severity-sorted table. Auto-invoke when the user says "show me all X", "find issues that Y", "list bugs with severity high".
---

# gh-search

When `gh-status` is too coarse and the user has a specific question, `gh-search` runs the targeted query.

## When to use

- "Show me all open features in `svc:bridge` with severity:high"
- "Which issues are blocked by something that's still open"
- "List bugs filed by @alice in the last 30 days"
- Anything that needs a one-shot ad-hoc filter, not a recurring view

## Inputs

```
gh-search "<natural language or raw github-search-syntax>" [--json] [--limit <n>]
```

| Flag | Default | Effect |
|---|---|---|
| `<query>` | required | Either natural language ("high-severity bridge bugs") or raw syntax (`is:open type:bug svc:bridge severity:high`). The skill detects which by checking for syntax markers (`is:`, `label:`, `:`). |
| `--json` | off | Emit one line of JSON per issue for piping. |
| `--limit` | 50 | Max results. |

## What it does

### Step 1 — Translate natural language to GH search syntax

Heuristics (deterministic):

| Phrase | Adds |
|---|---|
| "open" / "still open" | `is:open` |
| "closed" / "completed" / "done" | `is:closed` |
| "high-severity" / "severity high" / "p1" | `severity:high` |
| "bug" / "bugs" / "broken" | `type:bug` |
| "feature" / "features" | `type:feature` |
| "request" / "requests" / "deferred" | `type:request` |
| "in <service>" / "<service> issues" | `svc:<service>` (where `<service>` matches a known svc label) |
| "by @<user>" | `author:<user>` |
| "assigned to @<user>" | `assignee:<user>` |
| "last <n> days" | `created:>YYYY-MM-DD` (computed) |
| "blocked" | `label:status:blocked` |
| "in milestone <X>" | `milestone:"<X>"` |

If the query starts with `is:` / `label:` / `author:` / a quoted phrase, treat as raw syntax — no translation.

If the translation drops every word (nothing matched), echo the input verbatim to GitHub and let it handle.

### Step 2 — Run the query

```bash
gh issue list --search "$RESOLVED_QUERY" --state all --limit "$LIMIT" \
  --json number,title,state,labels,assignees,milestone,createdAt,updatedAt
```

### Step 3 — Render

Group by status (open + closed sections), sort within group by severity (Critical → Low). Compact table:

```
gh-search · 12 results for "high-severity bridge bugs"

Open (8)
  #142 [Bug] Bridge token refresh fails on Safari    🔴  3d ago
  #138 [Bug] Bridge OAuth callback drops state param 🟠  5d ago
  #131 [Bug] Bridge timeout in EU region              🟠  9d ago
  ...

Closed (4)
  #125 [Bug] Bridge SSL handshake on cold start      🟠  closed 12d ago
  ...
```

With `--json`: one issue per line, no formatting.

### Step 4 — Suggest follow-up

After rendering, surface a one-line action hint based on the result:

- All matches `type:request` → `→ /gh-pms:gh-triage to drain the queue`
- All matches `status:blocked` → `→ /gh-pms:gh-relate to inspect the blockers`
- Bugs with severity:critical and >1 day old → `→ assign someone now or escalate`
- Otherwise → `→ /gh-pms:gh-bulk for batch ops on this set`

## Cross-skill contract

- `gh-status` is the dashboard; `gh-search` is the ad-hoc query. They don't conflict — one is canned, the other is dynamic.
- The query string can be passed to `gh-bulk --query "<same string>"` to operate on the result set. Make sure the user confirms before bulk acts.

## Notes

- Out of scope: full-text content search beyond what GitHub Search supports
- Out of scope: cross-repo search (covered by GitHub's native multi-repo search; just pass a `repo:` qualifier in the raw query)
