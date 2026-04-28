---
name: gh-init
description: Bootstrap a GitHub repo for gh-pms — creates the `type:*`, `status:*`, and service labels, drops in issue templates and a PR template. Run this once per repo before using gh-pms. Idempotent — safe to re-run. Auto-invoke when the user is in a repo without the gh-pms label set, or when they say "set up issues", "init pms", "bootstrap this repo".
---

# gh-init

Bootstrap the current repository so the rest of gh-pms can run.

## When to use

- User is in a fresh repo and says "set up", "init", or "bootstrap"
- A `gh-*` skill is about to run but the required labels don't exist
- User explicitly invokes `/gh-pms:gh-init`

## What it does

1. Verifies you're inside a git repo with a GitHub remote (`gh repo view --json nameWithOwner`)
2. Creates these labels (idempotent — `gh label create --force` style):

   **Type labels:**
   - `type:feature` (#0E8A16 green)
   - `type:bug` (#D73A4A red)
   - `type:hotfix` (#B60205 dark red)
   - `type:chore` (#FBCA04 yellow)
   - `type:plan` (#5319E7 purple)
   - `type:prd` (#1D76DB blue)
   - `type:testcase` (#C5DEF5 light blue)
   - `type:request` (#BFDADC teal)

   **Status labels:**
   - `status:todo` (#FFFFFF white)
   - `status:in-progress` (#1F883D green)
   - `status:ready-for-testing` (#0969DA blue)
   - `status:in-testing` (#8250DF purple)
   - `status:ready-for-docs` (#9333EA violet)
   - `status:in-docs` (#A371F7 lavender)
   - `status:documented` (#3FB950 mint)
   - `status:in-review` (#BF8700 amber)
   - `status:blocked` (#CF222E red)
   - `status:done` (#1A7F37 dark green)

   **Generic service labels** (skip if user says "no services"):
   - `svc:app`, `svc:bridge`, `svc:studio`, `svc:edge`, `svc:db`, `svc:devops` (all #C5DEF5)

3. Copies issue templates from this plugin's `templates/` directory into `.github/ISSUE_TEMPLATE/` of the active repo:
   - `feature.md`, `bug.md`, `chore.md`, `plan.md`, `prd.md`, `request.md`
4. Copies the PR template into `.github/PULL_REQUEST_TEMPLATE.md`
5. Commits the templates with message `chore: bootstrap gh-pms templates and labels`
6. Reports a one-line summary: `gh-pms ready in <owner>/<repo> — N labels created, K templates added`

## How to execute

Use the `gh` CLI for batch label operations (faster than MCP one-by-one):

```bash
# For each label:
gh label create "type:feature" --color "0E8A16" --description "New functionality" --force
# ...etc
```

For template files, use the **Write** tool to drop them into `.github/ISSUE_TEMPLATE/`. The template content is in this plugin's `templates/` directory — read it via Read, then write to the target repo.

## Required inputs

None — operates on the current repo (cwd). If not inside a git repo with a GitHub remote, fail with: `gh-init: not in a GitHub repo. Run from inside one.`

## Output

```
gh-pms ready in {owner}/{repo}
  ✓ 18 labels created (8 type, 10 status)
  ✓ 6 issue templates added at .github/ISSUE_TEMPLATE/
  ✓ PR template added at .github/PULL_REQUEST_TEMPLATE.md
  ✓ Committed: chore: bootstrap gh-pms templates and labels
Next: use /gh-pms:gh-feature, /gh-pms:gh-bug, or /gh-pms:gh-plan
```

## Notes

- Re-running is safe. `gh label create --force` updates color/description without erroring.
- If the repo already has files at `.github/ISSUE_TEMPLATE/<name>.md`, ASK the user before overwriting.
- The plugin honors `${CLAUDE_PLUGIN_ROOT}` to locate its own `templates/` directory.
