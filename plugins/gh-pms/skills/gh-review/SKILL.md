---
name: gh-review
description: Open the PR for an issue, run Gate 4 (self-review), and orchestrate user approval (Gate 5). Mirrors Orchestra MCP's `request_review` + `submit_review`. Auto-invoke when the user says "review #N", "open PR for #N", "ready for review".
---

# gh-review

Drive an issue from `documented` through `in-review` to `done`.

## Two-phase operation

### Phase 1: request_review (Gate 4)

1. Read issue → confirm current status is `documented`
2. Verify a branch exists with the work — if not, ask user for branch name
3. Verify a PR exists for that branch with `Closes #{N}` in the body. If not:
   - Open it via `mcp__github__create_pull_request` with body containing `Closes #{N}` and the PR template
   - Push commits if not pushed (`git push origin {branch}`)
4. Build self-review comment with required sections:
   ```markdown
   ## Summary
   {what was done at a high level}

   ## Quality
   {code quality notes — tests pass, no lint warnings, no console.error, etc.}

   ## Checklist
   - {file path 1} — {what changed}
   - {file path 2} — {what changed}
   ```
5. Validate via `lib/validate-evidence.sh` — must pass
6. Post comment, swap labels `documented → in-review`
7. Use `AskUserQuestion`:
   - Question: "PR #{X} is open closing #{N}. Approve?"
   - Options: `Approve`, `Needs Edits`, `Cancel`
8. Wait for user choice → proceed to Phase 2

### Phase 2: submit_review (Gate 5)

Based on user choice:

- **Approve**:
  - `gh pr review {X} --approve`
  - `gh pr merge {X} --squash --delete-branch` (or merge style per repo convention; ask once and remember)
  - GitHub auto-closes issue #{N} via `Closes` keyword
  - Add `status:done` label, remove `status:in-review`
  - Comment: `✅ Approved by @{me}, merged via #{X}.`
  - Report: `#{N} done. PR #{X} merged.`

- **Needs Edits**:
  - Comment on issue: `🔄 Needs edits: {reason from user}`
  - Swap labels: `in-review → in-progress`
  - Reset cooldown timestamp
  - Report: `#{N} back to in-progress for edits.`

- **Cancel**:
  - Close PR (`gh pr close {X}`)
  - Close issue with comment: `❌ Cancelled: {reason}`
  - Apply label `wontfix` if it exists
  - Report: `#{N} cancelled.`

## Important

The agent **must not** call `gh-advance` for the `in-review → done` transition. Only `gh-review`'s Phase 2 can move to done, and only after explicit user approval via `AskUserQuestion`. This mirrors Orchestra MCP's "review requires user approval" guardrail.

## Cross-skill contract

After Phase 2 completes successfully (Approve), the agent should:
1. Pick the next ready sub-issue from the same parent plan (if any) and run `/gh-pms:gh-current` on it
2. Otherwise, report "all sub-issues done" and run `/gh-pms:gh-status` for a summary
