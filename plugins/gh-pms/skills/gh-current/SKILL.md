---
name: gh-current
description: Set the active issue — moves it from `status:todo` to `status:in-progress` and verifies the WIP guardrail (one in-progress issue per assignee). Mirrors Orchestra MCP's `set_current_feature`. Auto-invoke after a feature/bug is created and the user wants to start work, or when the user says "let's work on #N", "start #N", "begin #N".
---

# gh-current

Mark an issue as the active piece of work.

## What it does

1. **Pre-flight: WIP check** — Calls `mcp__github__list_issues` filtered by:
   - `assignee`: current user (`mcp__github__get_me` if unknown)
   - `labels`: `status:in-progress`
   - `state`: open
2. If results > 0 and `wip_limit=1` (default per workflow), STOP:
   ```
   WIP limit reached. You have #X already in progress.
   Finish it (run /gh-pms:gh-advance #X) or set it back to todo before starting #N.
   ```
3. If clean: assign current user to the target issue:
   ```bash
   gh issue edit {N} --add-assignee @me
   ```
4. Update status. Use the unified setter — it updates BOTH the `status:*` label AND the Project v2 Status field (if a project is attached), atomically:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh set-status {N} "In Progress"
   ```
5. Record start timestamp in `~/.cache/gh-pms/state.json` (for cooldown tracking).
6. Comment on the issue: `🚧 Work started by @{me} at {ISO timestamp}.`
7. Report:
   ```
   Active: #{N} {title}
     status:todo → status:in-progress
     Assignee: @{me}
   Next: do the work, then /gh-pms:gh-advance #{N} with Gate 1 evidence
   ```

## State file

`~/.cache/gh-pms/state.json`:
```json
{
  "{owner}/{repo}/issues/{N}": {
    "started_at": "2026-04-29T10:15:00Z",
    "last_transition_at": "2026-04-29T10:15:00Z",
    "current_status": "in-progress"
  }
}
```

## Cross-skill contract

The agent must call this BEFORE writing any code for the issue. If the user says "fix #42 now" without running `gh-current`, the skill is auto-invoked first.
