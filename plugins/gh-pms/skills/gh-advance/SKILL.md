---
name: gh-advance
description: Advance an issue to the next workflow status with evidence. Validates the gate per `workflows/default.yaml` — required `## Sections`, file paths, cooldown, kind-specific skips. Mirrors Orchestra MCP's `advance_feature`. Auto-invoke when the user says "tests pass for #N", "ready for review on #N", "advance #N", "move #N to {status}".
---

# gh-advance

Move an issue forward through its lifecycle, enforcing the gate.

## What it does

1. Read target issue: `mcp__github__issue_read({issue_number})`
2. Determine current status from labels (the unique `status:*` label)
3. Determine target status:
   - If user specifies one ("move to in-testing"), use it
   - Otherwise advance to the natural next status per workflow:
     - in-progress → ready-for-testing (Gate 1)
     - in-testing → ready-for-docs (Gate 2)
     - in-docs → documented (Gate 3, auto-skipped for bug/hotfix/testcase — go straight to documented with placeholder comment)
     - documented → in-review (Gate 4, requires PR)
     - in-review → done (Gate 5, requires user approval)
4. Look up the gate for `from → to` in `workflows/default.yaml`
5. **If free transition**: update via the unified setter (updates Project Status field + status:* label):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh set-status {N} "{Target Status Name}"
   ```
   Done.
6. **Branch-policy pre-check (Gate 1 only)**: per `workflows/default.yaml#branching.gate1_refuses_protected_base`, before validating Gate 1 evidence, check the current git branch. If it is in `branching.protected_base` (default: main / master) AND the issue's kind is in `branching.pr_required_kinds`, REJECT:
   ```
   Gate 1 BLOCKED: feature work must be on a branch, not on `{base}`.
   Run: git checkout -b {kind_short}/{N}-{slug}
        git cherry-pick / git reset to move your commits onto the branch.
   Re-run /gh-pms:gh-advance #{N} from the branch.
   ```
   Skip this check only if the issue body or a comment contains the literal string `[gh-pms: branch-exception]` (a one-off escape hatch — should be rare).
7. **If gated**:
   a. Check cooldown: read `~/.cache/gh-pms/state.json[issue_key].last_transition_at`. If < 30s ago, REJECT:
      ```
      Gate cooldown: last transition was {N}s ago. Wait {30-N}s and verify your evidence is real, not boilerplate.
      ```
   b. Build the evidence comment from the user's input. The user provides evidence either inline or as a structured payload. Format MUST be:
      ```markdown
      ## {Section1}
      {content, ≥10 chars}

      ## {Section2}
      {content, ≥10 chars, with file paths if required}
      ```
   c. Run `lib/validate-evidence.sh` (via Bash tool) — passes evidence + gate spec, returns `{ valid: bool, errors: [...] }`
   d. If invalid, STOP and report each error:
      ```
      Gate {gate_id} BLOCKED:
        ✗ Missing section: ## Verification
        ✗ ## Changes has only 4 chars (min 10)
        ✗ ## Changes has no file paths (require_file_paths: true)
      Fix the evidence and re-run.
      ```
   e. If valid:
      - Post the evidence as a comment via `mcp__github__add_issue_comment`
      - Update via unified setter (label + Project Status field):
        ```bash
        ${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh set-status {N} "{Target Status Name}"
        ```
      - Update `~/.cache/gh-pms/state.json[issue_key].last_transition_at = now()`
      - Update `current_status = to`
      - Report:
        ```
        ✓ Gate {gate_id} passed
        #{N} {title}: status:{from} → status:{to}
        Evidence: {comment_url}
        Next: {next-action-hint}
        ```
8. **For Gate 4 (documented → in-review)**: must verify a PR is open with `Closes #{N}` in body. Use `mcp__github__list_pull_requests` to find any PR mentioning the issue number. If no PR exists, route the user to `/gh-pms:gh-push #{N}` which handles push + PR creation + review-request in one shot. Then run the CI check:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/lib/check-pr-checks.sh <PR-number>
   ```
   - Exit 0 → Gate 4 proceeds.
   - Exit 1 → REFUSE the transition. The script prints which checks are failing/pending and the override hint.
   - **Override**: if the user passes `--ignore-checks "<reason>"`, skip the refusal **but** append a `## Check overrides` section to the gate evidence comment with the reason. This is for cases like "flaky linter, will fix in follow-up #123" — the audit trail is the point. Don't let it become a habit; the cooldown won't help here.
9. **For Gate 5 (in-review → done)**: this skill REJECTS direct calls. User must approve via `/gh-pms:gh-review`'s `submit_review` step. Return:
   ```
   Cannot advance to status:done directly. Use /gh-pms:gh-review to request user approval, then submit the decision.
   ```

## Auto-skip logic for kinds

Per `workflows/default.yaml` `gates[*].skip_for_kinds`:
- `bug`, `hotfix`, `testcase` → skip Gate 3 (docs)
- When skipping: insert a system comment `Gate 3 auto-skipped (kind: bug)` and proceed `ready-for-docs → documented` in one move.

## Programmatic guardrails (re-state)

- Cooldown: 30s between transitions
- WIP limit: enforced by `gh-current` not here (advance assumes you're already current)
- Evidence file-path check: `## Changes` and `## Checklist` must contain at least one path that exists in the repo (`-` prefix list, validate via Bash `test -f`)
- Branch-policy check (Gate 1): refuses to advance feature work that is still on the protected base branch — see step 6 above
- macOS bash 3.2 compatibility: `lib/validate-evidence.sh` uses bash 4+ associative arrays. On systems with only bash 3 (default on macOS), the validator errors with `declare: -A: invalid option`. Until the script is rewritten, fall back to a manual section-length + file-existence check before posting evidence; this is a known plugin issue tracked separately.

## Cross-skill contract

After Gate 4 passes, the agent calls `AskUserQuestion` to ask: "Approve PR #X / Closes #N?" with options Approve / Needs Edits. Then runs `/gh-pms:gh-review` with the decision.
