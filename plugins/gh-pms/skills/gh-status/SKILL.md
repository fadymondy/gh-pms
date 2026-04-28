---
name: gh-status
description: Show the gh-pms dashboard for the current repo — open issues grouped by status, WIP for current user, next-actionable items. Auto-invoke when the user says "status", "where are we", "what's next", "show issues".
---

# gh-status

Project-management dashboard for the current repo.

## What it does

1. Determine repo from `git remote get-url origin`
2. Run parallel `mcp__github__list_issues` calls:
   - All open issues, grouped by `status:*` label
   - Issues assigned to current user (`mcp__github__get_me`) with `status:in-progress`
   - Open `type:request` issues (the deferred queue)
3. Render a grouped table:

```
gh-pms · {owner}/{repo}

Active (assigned to @{me})
  #43 [Feature] Bridge endpoint        status:in-progress    started 2h ago
  
Pipeline
  todo                : 5 issues  (#44 #45 #46 #47 #48)
  in-progress         : 1 issue   (#43)
  ready-for-testing   : 0
  in-testing          : 0
  ready-for-docs      : 0
  in-docs             : 0
  documented          : 0
  in-review           : 2 issues  (#41 #42)
  blocked             : 1 issue   (#39 — blocked by #38)
  
Plans
  #20 [Plan] Migrate auth flow         3/5 sub-issues done
  #30 [Plan] Real-time dashboards     0/4 sub-issues done

Requests (deferred)
  #50 [Request] Add MCP for Vercel    waiting triage
  #51 [Request] Bilingual error pages waiting triage

Next actionable
  → #44 (next feature in plan #20, no unmet deps)
```

## Notes

- "Started Xh ago" comes from the local state file
- "N/M sub-issues done" comes from counting closed children of the plan via `mcp__github__list_issues` filtered by parent
- "Blocked by #X" reads from issue body's `**Depends on**: #X` line
