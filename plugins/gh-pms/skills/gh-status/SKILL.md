---
name: gh-status
description: Show the gh-pms dashboard for the current repo — open issues grouped by status, WIP for current user, next-actionable items. Auto-invoke when the user says "status", "where are we", "what's next", "show issues".
---

# gh-status

Project-management dashboard for the current repo.

## What it does

1. Determine repo from `git remote get-url origin`
2. Detect features via `${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh detect-features`
3. **If a `gh-pms` Projects v2 board exists**, prefer reading it (single canonical view of Status, Severity, Effort, Service across the whole project):
   ```bash
   gh project item-list <project_number> --owner <owner> --format json
   ```
   Group by Project's `Status` field.
4. **Otherwise** (no project), fall back to label-based grouping:
   - `mcp__github__list_issues` — all open issues, grouped by `status:*` label
   - Issues assigned to current user with `status:in-progress`
   - Open `type:request` issues
5. **Always** include milestone progress via `gh api repos/{owner}/{repo}/milestones?state=open` — show plans (= milestones) with their progress bars
6. Render a grouped table:

```
gh-pms · {owner}/{repo}                    [Project: gh-pms (#3)] [Issue Types: ✓]

Active (assigned to @{me})
  #43 [Feature] Bridge endpoint        Status: In Progress    Effort: M  started 2h ago

Pipeline (from Project Status field)
  Todo                : 5  (#44 #45 #46 #47 #48)
  In Progress         : 1  (#43)
  Ready for Testing   : 0
  In Testing          : 0
  Ready for Docs      : 0
  In Docs             : 0
  Documented          : 0
  In Review           : 2  (#41 #42)
  Blocked             : 1  (#39 — blocked by #38)

Milestones (= Plans)
  #M1 Migrate auth flow            ████░░░░░ 60%   3/5 closed   due 2026-06-01
  #M2 Real-time dashboards         ░░░░░░░░░  0%   0/4 closed   no due date

Requests (deferred)
  #50 [Request] Add MCP for Vercel    waiting triage
  #51 [Request] Bilingual error pages waiting triage

Next actionable
  → #44 (next feature in milestone #M1, no unmet deps)
```

## Notes

- "Started Xh ago" comes from the local state file
- "N/M sub-issues done" comes from counting closed children of the plan via `mcp__github__list_issues` filtered by parent
- "Blocked by #X" reads from issue body's `**Depends on**: #X` line
