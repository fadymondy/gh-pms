---
name: gh-init
description: Bootstrap a GitHub repo for gh-pms — detects available native features (Issue Types, Projects v2, Milestones), provisions what's missing, drops in issue templates and a PR template. Run this once per repo before using gh-pms. Idempotent. Auto-invoke when the user is in a repo without the gh-pms project, or when they say "set up issues", "init pms", "bootstrap this repo".
---

# gh-init

Bootstrap the current repo so the rest of gh-pms can run with full GitHub-native primitives.

## When to use

- User is in a fresh repo and says "set up", "init", "bootstrap"
- A `gh-*` skill reports missing infrastructure (no project, no labels, no milestones)
- User explicitly invokes `/gh-pms:gh-init`

## Step 1 — Verify location

Run `gh repo view --json nameWithOwner -q .nameWithOwner` (via Bash). If it fails, fail with: `gh-init: not in a GitHub repo. Run from inside one.`

## Step 2 — Detect native features

```bash
${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh detect-features
```

This returns JSON like:
```json
{
  "issue_types": true,
  "projects_scope": false,
  "owner_kind": "Organization",
  "types": [{"id": "IT_kw...", "name": "Feature", "color": "BLUE"}, ...]
}
```

Use this to decide which primitives to provision.

## Step 3 — Provision Issue Types (if available)

If `issue_types: true` AND the org has at least Feature/Bug/Task: nothing to do — types are already at org level. Just remember the IDs for later steps.

If `issue_types: false`: skip; we'll use `type:*` labels.

## Step 4 — Provision Projects v2 (opt-in)

If the user passed `--with-project` (or said "create a project too"):

a. Check token scope: `gh auth status | grep "'project'"`. If missing, run:
   ```
   gh auth refresh -s project
   ```
   and ASK the user to complete the browser flow before continuing.

b. Create or find the project:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh ensure-project "gh-pms"
   ```

c. Ensure the required fields exist (idempotent):
   ```bash
   PN=<project_number>
   ${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh ensure-project-field "$PN" "Status"   "Todo" "In Progress" "Ready for Testing" "In Testing" "Ready for Docs" "In Docs" "Documented" "In Review" "Blocked" "Done"
   ${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh ensure-project-field "$PN" "Severity" "Critical" "High" "Medium" "Low"
   ${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh ensure-project-field "$PN" "Effort"   "S" "M" "L" "XL"
   ${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh ensure-project-field "$PN" "Service"  "app" "bridge" "studio" "edge" "db" "devops"
   ```

If the user opts out: skip; status lives on labels only.

## Step 5 — Provision labels (always)

Even with native types + projects, labels are the visible-at-a-glance signal in the issue list. Always create the full label set:

```bash
${CLAUDE_PLUGIN_ROOT}/lib/ghcall.sh bootstrap-labels
```

## Step 6 — Drop in templates

Copy from this plugin's `templates/` to the active repo's `.github/`:

```
.github/ISSUE_TEMPLATE/feature.md      ← templates/feature.md
.github/ISSUE_TEMPLATE/bug.md          ← templates/bug.md
.github/ISSUE_TEMPLATE/chore.md        ← templates/chore.md
.github/ISSUE_TEMPLATE/plan.md         ← templates/plan.md
.github/ISSUE_TEMPLATE/prd.md          ← templates/prd.md
.github/ISSUE_TEMPLATE/request.md      ← templates/request.md
.github/ISSUE_TEMPLATE/testcase.md     ← templates/testcase.md
.github/PULL_REQUEST_TEMPLATE.md       ← templates/pull-request.md
```

If a target already exists, ASK before overwriting.

## Step 7 — Commit templates

```bash
git add .github/
git commit -m "chore: bootstrap gh-pms templates and labels"
```

Do NOT add Co-Authored-By trailers. Use the user's git config.

## Step 8 — Report

```
gh-pms ready in {owner}/{repo}
  Native features:
    Issue Types:  ✓ Feature / Bug / Task (org-level)         [or ✗ falling back to type:* labels]
    Projects v2:  ✓ "gh-pms" project #{N} with 4 fields      [or ✗ skipped]
    Milestones:   ✓ enabled
  Labels: 26 created (8 type, 10 status, 4 severity, 4 service)
  Templates: 7 issue templates + PR template added
  Committed: chore: bootstrap gh-pms templates and labels
Next: /gh-pms:gh-feature, /gh-pms:gh-bug, /gh-pms:gh-plan
```

## Notes

- Re-running is safe end-to-end
- `--with-project` requires `project` token scope — user must run `gh auth refresh -s project` once
- Issue Types are an org-level setting; can't be created from the plugin. If you want them on a user repo, the only path is to move the repo to an org first.
