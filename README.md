# Github PMS Plugin

**GitHub Issues as a project-management system for Claude Code.**

A Claude Code plugin marketplace that turns GitHub Issues into the source of truth for your project: plans, features, bugs, evidence-gated lifecycle, PR-driven review. Inspired by Orchestra MCP and Studio PMS, backed by GitHub's first-class primitives — **Issue Types**, **Projects v2**, **Milestones**, **sub-issues**, and **relationships** — not just labels.

## Why

Most teams use GitHub Issues as a dumb backlog. `gh-pms` adds the structure that real project management needs:

- **Plans** = Milestones with due dates and native progress bars
- **Features / Bugs** use GitHub's native **Issue Types** when available, fall back to labels otherwise
- **Status** tracked in a Projects v2 board's `Status` field (when configured) or `status:*` labels
- **Sub-issues** for plan → feature breakdown, **dependency relationships** (`depends on`, `blocks`, `related to`, `duplicate of`)
- **Evidence-gated lifecycle** — 5 gates with required `## Sections` (file paths, test results, self-review)
- **WIP limits**, **cooldowns**, **kind-specific skips** (bugs auto-skip the docs gate)
- **PR-driven review** — `Closes #N` keyword + `AskUserQuestion` approval + `gh pr merge` closes the loop

Everything lives natively in GitHub. Open the Issues, Milestones, or Projects tab and you see exactly where the project is.

## What's new in v0.5

Two skills that close adoption gaps the v0.4 release made obvious — sessions starting blind to the issue tracker, and releases requiring a manual edit-bump-tag dance.

- **`gh-context`** ✨ — compact session-start summary of WIP, pipeline, milestones, recent closes, deferred requests. Auto-runs via the new `SessionStart` hook so the agent picks up where the last session left off (#9).
- **`gh-release`** ✨ — bundle PRs merged since the last tag into a structured CHANGELOG entry, bump `plugin.json`, refresh the README banner, tag, and (optionally) create a GitHub release in one shot. Idempotent; refuses without an anchor (#5).

See [CHANGELOG.md](CHANGELOG.md) for the full list.

### From v0.4: severity first-class

Severity is now a first-class dimension on **every** issue kind, not just bugs. A P0 feature blocking a launch is meaningfully different from a polish item — that signal was previously lost. Closes #2.

- **Canonical scale** — `workflows/default.yaml#severities` is now the single source of truth (`default: medium` + four values, each mapped to a `severity:*` label and a Project v2 `Severity` field option). Per-repo severity scales become a config-only change.
- **`gh-feature`** ✨ — accepts an optional `severity` on every kind (not just hotfix). Applied as label + Project field. Hotfixes still default to `critical`.
- **`gh-task`** — sub-issue tasks inherit the parent feature's severity by default; override when the task is meaningfully more or less urgent. Checkbox tasks inherit implicitly.
- **`gh-bug`** — references the canonical scale instead of defining its own. Same defaults, no behavior change.
- **`gh-status`** — within each Status bucket, issues are sorted Critical → Low so urgent items surface first regardless of kind.
- **Templates** — `feature.md`, `chore.md`, `testcase.md` gain a `## Severity` section. `plan.md` / `prd.md` stay exempt (they aggregate child severities).

Backwards compatible — existing issues without a `severity:*` label remain valid, and skills called without `severity` get `medium`.

### From v0.3: `gh-push` skill + branching policy

The "every feature must end with a linked PR" rule is baked into the lifecycle:

- **`gh-push` skill** — One command to commit, push, open PR with `Closes #N`, post Gate 4 self-review evidence, ask the user to approve, and `gh pr merge`. Mirrors the popular `/push` pattern but PR-aware and lifecycle-integrated. Supports `--message`, `--no-merge`, `--admin`, `--squash` / `--merge` / `--rebase`, `--dry`, `--force`.
- **Branching policy** — `workflows/default.yaml#branching` defines `protected_base` (default: `main` / `master`), `pr_required_kinds` (feature / bug / hotfix / chore / testcase), `branch_template` (default: `{kind_short}/{number}-{slug}`), and `pr_must_close_issue: true`. The rule is enforced in three places: `gh-current` auto-creates the branch on start, `gh-advance` Gate 1 refuses if HEAD is on the protected base, and `gh-push` refuses to ship from the protected base.
- **`gh-current`** records `branch` + `base` in the per-issue state file so `gh-push` finds them later. The "🚧 Work started" comment mentions the branch name.
- **`gh-advance`** Gate 1 has a clear rescue-recipe error if work is on the wrong branch. One-off legacy state can opt out with the `[gh-pms: branch-exception]` marker in the issue body.

### From v0.2: GitHub-native primitives

- **Issue Types** (orgs only): `Feature`, `Bug`, `Task` set via GraphQL, not labels — when the org has them enabled
- **Projects v2** integration: `gh-init --with-project` provisions a `gh-pms` board with `Status`, `Severity`, `Effort`, `Service` custom fields
- **Milestones for plans**: `gh-plan` creates a milestone; `gh-breakdown` attaches every child via `--milestone`; closes auto-progress
- **`gh-relate` skill**: encode `depends_on`, `blocks`, `related_to`, `duplicate_of` between issues
- **Auto-detection**: `gh-init` queries the org for available features and provisions only what's missing; user-account repos gracefully fall back to labels
- **Unified status setter**: `lib/ghcall.sh set-status <issue> "<Status>"` updates label + project field atomically

See [CHANGELOG.md](CHANGELOG.md) for the full list.

## Install

```bash
# Add the marketplace (one-time)
/plugin marketplace add fadymondy/gh-pms

# Install the plugin
/plugin install gh-pms@gh-pms
```

Requires:

- **GitHub MCP** — already configured in Claude Code (auth via OAuth or PAT)
- **`gh` CLI** — for batch label / project / milestone ops: `brew install gh && gh auth login`
- **`gh` `project` scope** — only if you want Projects v2 integration: `gh auth refresh -s project`
- **`jq`** — for JSON parsing in hooks: `brew install jq`

## Quick start

In any GitHub repo:

```bash
# 1. Bootstrap (creates labels + templates; optionally creates a Project)
/gh-pms:gh-init                  # labels + templates only
/gh-pms:gh-init --with-project   # also create the gh-pms Projects v2 board

# 2. From now on, just talk normally — the plugin auto-classifies prompts
#    and ensures every actionable request becomes an issue.
```

Examples:

```text
"Plan the migration of auth flow to the bridge"
  → /gh-pms:gh-plan creates milestone + tracker issue
  → /gh-pms:gh-breakdown creates feature sub-issues, attaches them to the milestone

"Add a /entities endpoint that returns sentiment scores"
  → /gh-pms:gh-feature creates issue, sets Issue Type "Feature" (if org), adds to project
  → /gh-pms:gh-current sets Status: In Progress
  → work happens, gates open, PR opens with Closes #N
  → user approves, PR merges, issue auto-closes

"Build the launch-blocking SSO refresh — this is P0"
  → /gh-pms:gh-feature with severity: critical
  → severity:critical label + Severity = Critical on the project board

"The login page redirects to 404 after 2FA"
  → /gh-pms:gh-bug creates issue, sets Issue Type "Bug", severity:medium

"#42 depends on #38 and #39"
  → /gh-pms:gh-relate updates body sections on all three, posts cross-reference comments
```

## What gets created in your repo

After `gh-init`:

```text
.github/
├── ISSUE_TEMPLATE/
│   ├── feature.md
│   ├── bug.md
│   ├── chore.md
│   ├── plan.md
│   ├── prd.md
│   ├── request.md
│   └── testcase.md
└── PULL_REQUEST_TEMPLATE.md
```

Labels (always created — used directly when native features unavailable, otherwise as a visible-at-a-glance secondary signal):

```text
type:      feature, bug, hotfix, chore, plan, prd, testcase, request
status:    todo, in-progress, ready-for-testing, in-testing,
           ready-for-docs, in-docs, documented, in-review, blocked, done
severity:  critical, high, medium, low
svc:       app, bridge, studio, edge, db, devops
```

GitHub native (provisioned when available + opted in):

```text
Issue Types  (org-level): Feature, Bug, Task — set via GraphQL on creation
Projects v2  (--with-project): gh-pms board with fields Status / Severity / Effort / Service
Milestones   (always): one per plan, with optional due date + auto-progress
```

## The lifecycle

```text
   todo  ──(free)──► in-progress
                          │
                       Gate 1   (## Summary, ## Changes [files], ## Verification)
                          ▼
                   ready-for-testing  ──(free)──► in-testing
                                                       │
                                                    Gate 2   (## Summary, ## Results, ## Coverage)
                                                       ▼
                                                ready-for-docs
                                                       │
                                                  (free) │  [auto-skip if bug/hotfix/testcase]
                                                       ▼
                                                    in-docs ──Gate 3──► documented
                                                                              │
                                                                           Gate 4   (## Summary, ## Quality, ## Checklist [files], PR with Closes #N)
                                                                              ▼
                                                                         in-review
                                                                              │
                                                                           Gate 5   (user approval via AskUserQuestion)
                                                                              ▼
                                                                            done
```

## Skills

| Skill                     | Mirrors                                       |
| ------------------------- | --------------------------------------------- |
| `/gh-pms:gh-init`         | (bootstrap)                                   |
| `/gh-pms:gh-plan`         | `pms_create_plan` (now creates milestone)     |
| `/gh-pms:gh-breakdown`    | `pms_breakdown_plan` (attaches to milestone)  |
| `/gh-pms:gh-feature`      | `pms_create_feature` (sets native type)       |
| `/gh-pms:gh-bug`          | `pms_create_bug_report` (sets native type)    |
| `/gh-pms:gh-task`         | `pms_create_task`                             |
| `/gh-pms:gh-current`      | `pms_set_current_feature` (auto-creates feature branch) |
| `/gh-pms:gh-advance`      | `pms_advance_feature` (Gate 1 refuses from protected base) |
| `/gh-pms:gh-push` ✨      | (new in v0.3) — commit + push + PR + Gate 4 + Gate 5 in one shot |
| `/gh-pms:gh-validate`     | `pms_validate_gates`                          |
| `/gh-pms:gh-review`       | `pms_request_review` + `pms_submit_review`    |
| `/gh-pms:gh-relate`       | (new in v0.2) — manage issue relationships    |
| `/gh-pms:gh-request`      | `pms_create_request`                          |
| `/gh-pms:gh-status`       | `pms_list_features` (reads project board)     |
| `/gh-pms:gh-context` ✨   | (new in v0.5) — session-start summary         |
| `/gh-pms:gh-release` ✨   | (new in v0.5) — version bump + tag + release  |

## Hooks

| Event                                       | Behavior                                                                  |
| ------------------------------------------- | ------------------------------------------------------------------------- |
| `SessionStart`                              | Injects a `gh-context` summary so the agent isn't blind on a new session  |
| `UserPromptSubmit`                          | Classifies the prompt, injects a context reminder for the agent           |
| `PreToolUse` on `mcp__github__create_pull_request` | Blocks PR creation if `Closes #N` is missing from the body         |
| `Stop`                                      | Surfaces stale in-progress issues at end of turn                          |

## Programmatic guardrails

- **WIP limit** — One in-progress issue per assignee
- **Gate cooldown** — 30s minimum between transitions on the same issue (prevents fake batch-advancement)
- **Kind-specific skips** — Bugs/hotfixes/testcases skip Gate 3 (docs)
- **Branching policy** (v0.3) — Feature work must land on a feature branch, not on `main` / `master`. `gh-current` auto-creates the branch; `gh-advance` Gate 1 refuses from the protected base; `gh-push` refuses to ship from the protected base. Bootstrap commits with no issue number are exempt.
- **PR enforcement** — Every feature must end with a PR containing `Closes #N` so merge auto-closes the issue. Gate 4 requires it; `gh-push` injects it automatically.
- **CI gate on Gate 4** (v0.5+) — `documented → in-review` refuses if any required PR check is failing or still pending. `lib/check-pr-checks.sh` is the source of truth. Override only with `--ignore-checks "<reason>"`, which records the reason in a `## Check overrides` section of the evidence comment for audit.
- **User-only Gate 5** — Only `gh-push` Step 5 (or `gh-review`'s Phase 2) can move to `done`, and only after `AskUserQuestion` approval
- **Native primitives preferred** — Issue Types, Project Status field, and Milestones are used when available; labels stay as a fallback and visible-at-a-glance signal

## Configuration

The plugin's defaults live in [`plugins/gh-pms/workflows/default.yaml`](plugins/gh-pms/workflows/default.yaml). To override per repo, drop a `.github/gh-pms.yaml` in the repo (an annotated example lives at [`plugins/gh-pms/templates/gh-pms.yaml.example`](plugins/gh-pms/templates/gh-pms.yaml.example) — `gh-init --customize` copies it for you).

The merge is shallow at the top-level key: any section you set in your override **replaces** its default counterpart wholesale. To extend a list, copy the defaults into your override and add yours.

Inspect the merged result anytime:

```bash
${CLAUDE_PLUGIN_ROOT}/lib/load-config.sh 0 | jq .
```

Common overrides:

- **Severity scale** — replace the `severities` block to use blocker/high/medium/nit instead of the default critical/high/medium/low
- **Service taxonomy** — swap `github_features.project_fields[Service].options` to your team's repo set; `gh-init bootstrap-labels` creates the matching `svc:*` labels automatically
- **Gate evidence** — add or remove required sections per gate (e.g. add a `Threat model` section to Gate 1 for security-sensitive repos)
- **Branching policy** — change `protected_base` or `branch_template` to fit non-`main` defaults
- **Custom kinds** — add a new issue kind beyond feature/bug/hotfix/chore/testcase/plan/prd/request

## License

MIT — see [LICENSE](LICENSE)

## Author

[Fady Mondy](https://github.com/fadymondy)
