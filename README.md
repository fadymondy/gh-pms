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

## What's new in v0.2

GitHub-native primitives replace label-only tracking:

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
| `/gh-pms:gh-current`      | `pms_set_current_feature` (project Status)    |
| `/gh-pms:gh-advance`      | `pms_advance_feature` (project Status)        |
| `/gh-pms:gh-validate`     | `pms_validate_gates`                          |
| `/gh-pms:gh-review`       | `pms_request_review` + `pms_submit_review`    |
| `/gh-pms:gh-relate` ✨    | (new in v0.2) — manage issue relationships    |
| `/gh-pms:gh-request`      | `pms_create_request`                          |
| `/gh-pms:gh-status`       | `pms_list_features` (reads project board)     |

## Hooks

| Event                                       | Behavior                                                                  |
| ------------------------------------------- | ------------------------------------------------------------------------- |
| `UserPromptSubmit`                          | Classifies the prompt, injects a context reminder for the agent           |
| `PreToolUse` on `mcp__github__create_pull_request` | Blocks PR creation if `Closes #N` is missing from the body         |
| `Stop`                                      | Surfaces stale in-progress issues at end of turn                          |

## Programmatic guardrails

- **WIP limit** — One in-progress issue per assignee
- **Gate cooldown** — 30s minimum between transitions on the same issue (prevents fake batch-advancement)
- **Kind-specific skips** — Bugs/hotfixes/testcases skip Gate 3 (docs)
- **PR enforcement** — Gate 4 requires an open PR with `Closes #N`
- **User-only Gate 5** — Only `gh-review`'s Phase 2 can move to `done`, and only after `AskUserQuestion` approval
- **Native primitives preferred** — Issue Types, Project Status field, and Milestones are used when available; labels stay as a fallback and visible-at-a-glance signal

## Configuration

Per-repo overrides in `.github/gh-pms.yaml` (planned for v0.3):

- Custom workflow definitions
- Disable/enable specific gates
- Custom service labels
- Custom severity scale
- Map custom Issue Types beyond the GitHub default set

## License

MIT — see [LICENSE](LICENSE)

## Author

[Fady Mondy](https://github.com/fadymondy)
