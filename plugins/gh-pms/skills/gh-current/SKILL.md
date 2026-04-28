---
name: gh-current
description: Set the active issue — moves it from `status:todo` to `status:in-progress` and verifies the WIP guardrail (one in-progress issue per assignee). Mirrors Orchestra MCP's `set_current_feature`. Auto-invoke after a feature/bug is created and the user wants to start work, or when the user says "let's work on #N", "start #N", "begin #N".
---

# gh-current

Mark an issue as the active piece of work AND create the feature branch the work will live on.

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
3. **Read issue** — `gh issue view {N} --json title,labels` to get title (for branch slug) and kind (for branch prefix). Kind comes from the `type:*` label or the GitHub native Issue Type.
4. **Branching policy** — per `workflows/default.yaml#branching`:
   a. If kind is in `pr_required_kinds` (default: feature / bug / hotfix / chore / testcase) AND the current branch is in `protected_base` (default: main / master):
      - Compute branch name from `branch_template`. Default: `{kind_short}/{number}-{slug}` where `slug` is the issue title lowercased with non-alphanum runs collapsed to `-`, capped at 40 chars.
      - Run `git fetch origin` then `git checkout -b {branch}` (or `git checkout {branch}` if it already exists locally) so all subsequent commits land on the feature branch.
      - Comment on the issue: `🌿 Branch \`{branch}\` created from \`{base}@{sha7}\`.`
   b. If the user is already on a non-protected branch, leave it alone — assume they intend to use that branch.
   c. If the kind is exempt from PR requirement (e.g. `plan`), skip branch creation.
5. Assign current user to the target issue:
   ```bash
   gh issue edit {N} --add-assignee @me
   ```
6. Update status via the unified setter (label + Project v2 Status field, atomically):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh set-status {N} "In Progress"
   ```
7. Record start timestamp + branch in `~/.cache/gh-pms/state.json` (for cooldown tracking and gh-push lookup).
8. Comment on the issue: `🚧 Work started by @{me} at {ISO timestamp} on branch \`{branch}\`.`
9. Report:
   ```
   Active: #{N} {title}
     status:todo → status:in-progress
     Assignee: @{me}
     Branch:   {branch}    (created from {base}@{sha7})
   Next: do the work, then /gh-pms:gh-push #{N} to ship via PR.
   ```

## State file

`~/.cache/gh-pms/state.json`:
```json
{
  "{owner}/{repo}/issues/{N}": {
    "started_at": "2026-04-29T10:15:00Z",
    "last_transition_at": "2026-04-29T10:15:00Z",
    "current_status": "in-progress",
    "branch": "feat/42-monaco-editor",
    "base": "main"
  }
}
```

The `branch` and `base` fields let `gh-push` find the right branch to push and the right base to PR against without re-asking.

## Cross-skill contract

The agent must call this BEFORE writing any code for the issue. If the user says "fix #42 now" without running `gh-current`, the skill is auto-invoked first.

After branching, the agent must NOT switch back to the protected base while the issue is in-progress. If a `git checkout main` (or equivalent) is attempted before `gh-push`, warn the user and pause.
