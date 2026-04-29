---
name: gh-push
description: Ship an in-progress issue — commit local changes on the feature branch, push, open the PR with `Closes #N`, and (optionally) merge. Composes Gate 4 + Gate 5 of the gh-pms lifecycle. Auto-invoke when the user says "push #N", "ship #N", "open PR for #N", "/push", or any "ready to merge" intent.
---

# gh-push

Ship completed work in one command: commit on the feature branch, push, PR, merge, advance the linked issue to `status:done`.

`gh-push` is the gh-pms counterpart to the popular `/push` skill — but PR-aware. It enforces the **"every feature must end with a linked PR"** rule from `workflows/default.yaml#branching` and refuses any path that would write feature work directly to the protected base branch.

## When to invoke

- User runs `/gh-pms:gh-push #N` (or shorthand `/push` if no other skill claims it)
- User says "ship #N", "push #N", "open PR for #N", "ready to merge #N"
- An issue is `status:documented` and the user signals they're ready to merge

## Pre-flight

1. **Resolve the target issue.**
   - If the user passed `#N`, use it.
   - Otherwise read `~/.cache/gh-pms/state.json` and pick the issue with `current_status` = `in-progress`, `ready-for-testing`, `in-testing`, `ready-for-docs`, or `documented`.
   - If still ambiguous, run `gh issue list --assignee @me --state open --label status:in-progress` and pick if exactly one matches; otherwise ASK the user via `AskUserQuestion`.

2. **Read issue + state.**
   - `gh issue view {N} --json number,title,labels,body,milestone`
   - Extract: kind (from `type:*` label or native Issue Type), current `status:*`, branch (from state file).

3. **Branch policy check.**
   - Get current branch: `git rev-parse --abbrev-ref HEAD`.
   - If it is in `branching.protected_base` (default: `main`, `master`):
     - If the kind is exempt (e.g. `plan`), proceed without branching.
     - Otherwise REFUSE:
       ```
       gh-push BLOCKED: feature work for #{N} cannot be shipped from `{base}`.
       Per workflows/default.yaml#branching, every feature requires a PR.
       Run /gh-pms:gh-current #{N} from a clean state to auto-branch, or:
         git switch -c {kind_short}/{N}-{slug}
         git push -u origin {branch}
       Then re-run /gh-pms:gh-push #{N}.
       ```
   - If the issue's recorded branch (from state file) does not match the current branch, WARN but allow — the user may have renamed.

4. **Working-tree check.**
   - `git status --porcelain` — if dirty, that's expected; we'll commit it.
   - If clean AND no commits ahead of the upstream, REFUSE: nothing to ship.

## Pipeline

### Step 1 — Stage & commit local changes (only if dirty)

If `git status --porcelain` shows changes:

1. Run `git diff --stat` and `git diff --cached --stat` to summarize.
2. Run `git log --oneline origin/{base}..HEAD` (or `git log --oneline -5`) to match the repo's commit style.
3. Generate a conventional-commit message (or use the `--message` flag value if provided):
   - Prefix: `feat:` for `feature` kind, `fix:` for `bug`/`hotfix`, `chore:` for `chore`, `test:` for `testcase`, `docs:` for doc-only diffs.
   - First line: short imperative summary, ≤72 chars, ending with `(#{N})` so the issue is referenced.
   - Body: 1–3 sentences on *why*, plus a `Refs #{N}` line if needed.
4. **Stage carefully.** Use specific paths from `git status` output. EXCLUDE:
   - `.env*`, `credentials*`, `*.key`, `*.pem`, `service-account*.json`, anything in `secrets/`
   - `node_modules/`, `.next/`, `dist/`, `out/`, `build/`, `*.tsbuildinfo`
   - Editor cruft: `.DS_Store`, `Thumbs.db`, `.idea/`, `.vscode/launch.json` unless explicitly needed
5. `git commit -m "$(cat <<'EOF' ... EOF)"` via HEREDOC. **No `Co-Authored-By` trailer** unless the user explicitly asks.

### Step 2 — Push the branch

```bash
git push -u origin {branch}
```

If the push is rejected because the remote has commits we don't:
- Run `git pull --rebase origin {branch}`.
- If rebase has conflicts, STOP and tell the user which files conflict.
- After successful rebase, retry the push.

**NEVER** force-push unless the user explicitly types `--force`.

### Step 3 — Find or open the PR

1. Look for an existing PR for this branch: `gh pr list --head {branch} --json number,url,title,body`.
2. If one exists:
   - Verify its body contains `Closes #{N}` (case-insensitive). If missing, append `Closes #{N}` via `gh pr edit {PR} --body-file ...`.
   - Skip to Step 4.
3. If none exists, create one:
   ```bash
   gh pr create \
     --base {base} \
     --head {branch} \
     --title "{commit-subject-without-issue-suffix}" \
     --body-file /tmp/gh-push-pr-body-{N}.md
   ```
   PR body template (HEREDOC into the temp file):
   ```markdown
   ## Summary
   {1–3 bullets — what changed and why, sourced from the issue body's Acceptance Criteria}

   ## Closes
   Closes #{N}

   ## Test plan
   - [ ] {pulled from issue's verification steps if present, else generic build/test}

   ## Linked issue
   #{N} — {issue title}

   ---
   _Opened via `/gh-pms:gh-push` on branch `{branch}`._
   ```

### Step 4 — Compose Gate 4 (documented → in-review)

If the issue's current status is `documented`:

1. Build the Gate 4 self-review evidence comment:
   ```markdown
   ## Summary
   {one paragraph — what shipped, who tested, what's left for the human reviewer}

   ## Quality
   - Build: {green / red — paste the result of `npm run build` / `cargo build` / etc. if quick}
   - Type-check: {tsc --noEmit, mypy, etc. result}
   - Lint: {result}
   - Tests: {result, or "no automated suite — manual coverage in Gate 2 evidence"}
   - Manual smoke: {what the agent verified in the dev host / local run}

   ## Checklist
   - {file path 1} — {what changed}
   - {file path 2} — {what changed}
   - {…}
   ```
2. Validate via `lib/validate-evidence.sh` (or a manual section-length + file-existence check on macOS bash 3 — see `gh-advance` notes).
3. **CI gate** — run `${CLAUDE_PLUGIN_ROOT}/lib/check-pr-checks.sh <PR>`. Refuse Gate 4 if exit code is non-zero (failing or still-pending checks). The script prints the failure list and the override hint. Override path: `--ignore-checks "<reason>"` skips the refusal but appends a `## Check overrides` section to the evidence comment with the reason. Use sparingly — the override is an audit trail, not a free pass.
4. Post the comment via `gh issue comment {N} --body-file ...`.
5. Flip status: `${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh set-status {N} "In Review"`.
6. Update the state file (`last_transition_at`, `current_status: in-review`).

If the issue is **not yet** at `documented` (e.g. user is shipping mid-flight), STOP after Step 3 and tell them:
```
PR #{X} is open for #{N}. Issue is currently status:{current}, not status:documented —
Gates 1–3 still need to pass before review can begin. Use /gh-pms:gh-advance #{N}
to move it forward, then re-run gh-push to compose Gate 4 evidence.
```

### Step 5 — Request user approval (Gate 5)

Use `AskUserQuestion`:

| Question | Options |
|---|---|
| `PR #{X} is open closing #{N}. {commit_count} commits, {file_count} files. Approve and merge?` | `Approve & merge` · `Needs edits` · `Cancel` |

Branch on the answer:

- **Approve & merge:**
  1. `gh pr review {X} --approve --body "Approved via /gh-pms:gh-push."`
  2. Pick merge style from `branching.merge_style` (default: `--squash`). Confirm with the user the first time per repo (cache the answer).
  3. `gh pr merge {X} --squash --delete-branch=true` (or `--merge` / `--rebase` per setting).
     - If checks are still running, ASK whether to use `--admin` (skip checks) or wait.
     - If conflicts, STOP and tell the user which files conflict.
  4. `git checkout {base} && git pull origin {base}` to bring local in sync.
  5. The `Closes #{N}` keyword auto-closes the issue. Verify: `gh issue view {N} --json state -q .state` should be `CLOSED`.
  6. Manually flip the status label to `done` (GitHub closes the issue but doesn't update status labels):
     `${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh set-status {N} "Done"`
  7. Update state file: `current_status: done`, `merged_at: now`, `pr: {X}`.
  8. Comment on the issue: `✅ Merged via #{X} on {timestamp}.`
  9. Report:
     ```
     Shipped #{N} {title}
       Branch:  {branch} → {base}
       Commits: {count}
       PR:      #{X} ({pr_url})
       Status:  documented → in-review → done
     Next: /gh-pms:gh-current #{next-issue-from-same-plan} (auto-suggested), or /gh-pms:gh-status for the dashboard.
     ```

- **Needs edits:**
  1. ASK for the reason via free-text input.
  2. Comment on PR #{X} via `gh pr comment` with `🔄 Needs edits: {reason}`.
  3. Flip issue status back to `in-progress`: `${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh set-status {N} "In Progress"`.
  4. Reset the cooldown timestamp.
  5. Report: `#{N} back to in-progress on branch {branch}. Address feedback, then re-run gh-push.`

- **Cancel:**
  1. ASK for the reason.
  2. Close PR: `gh pr close {X} --comment "❌ Cancelled: {reason}"`.
  3. Close issue with `not planned`: `gh issue close {N} --reason "not planned" --comment "❌ Cancelled: {reason}"`.
  4. Apply `wontfix` label if it exists.
  5. Report: `#{N} cancelled. Branch {branch} retained for archival.`

## Flags

| Flag | Behavior |
|---|---|
| `/gh-pms:gh-push #N` | Default — auto-detect everything, walk the full pipeline, ASK for approval at Gate 5. |
| `--message "<msg>"` | Use the provided commit message instead of auto-generating. Must still include `(#N)` suffix. |
| `--no-merge` | Stop after PR open + Gate 4 evidence post. Skip Gate 5. Useful when CI takes a long time. |
| `--admin` | Pass `--admin` to `gh pr merge` so it bypasses required checks. Use sparingly; the user must have admin rights. |
| `--squash` / `--merge` / `--rebase` | Force the merge style for this run. Default per `branching.merge_style`. |
| `--dry` | Print every command that *would* run. Don't execute. |
| `--force` | Allow `git push --force-with-lease`. Refuse plain `--force`. Reserved for explicit user request. |

## Safety rules

- **NEVER** push directly to a `protected_base` (main / master). Refuse with the error in pre-flight step 3.
- **NEVER** force-push without `--force` flag from the user.
- **NEVER** skip the `Closes #{N}` keyword — without it, the issue won't auto-close on merge.
- **NEVER** include secrets / build artifacts in the commit (see Step 1 EXCLUDE list).
- **NEVER** delete the protected base branch.
- **NEVER** advance to `done` without going through the `AskUserQuestion` approval gate (Step 5). This mirrors Gate 5's `required_user_approval`.
- **NEVER** add `Co-Authored-By` trailers unless the user explicitly asks.

## Cross-skill contract

After `Approve & merge`:
1. The skill should pick the next ready sub-issue from the same plan (milestone) — `gh issue list --milestone {plan} --label status:todo --state open --limit 1` — and offer to run `/gh-pms:gh-current` on it.
2. If no plan parent or no ready siblings, run `/gh-pms:gh-status` for the dashboard view.

If the user's intent was to ship work that wasn't yet on a feature branch (legacy state — work was committed to `main` before this rule existed), `gh-push` should:
1. Detect the situation (HEAD is on protected base, issue is in-progress/documented, has commits ahead of `origin/{base}`).
2. Offer a one-shot retro-rescue:
   - Create the feature branch at HEAD: `git branch {kind_short}/{N}-{slug}`
   - Reset main back to `origin/{base}`: `git reset --hard origin/{base}` (requires explicit user OK because this is destructive — confirm first).
   - Switch to the new branch: `git checkout {kind_short}/{N}-{slug}`
   - Push and PR as normal.
3. If the user prefers not to rewrite local main (e.g. main was already pushed), open a comparison PR documenting the work + add a `[gh-pms: branch-exception]` marker to the issue body so future Gate-1 checks don't trip on the same issue.
