# gh-pms

**GitHub Issues as a project-management system for Claude Code.**

A Claude Code plugin marketplace that turns GitHub Issues into the source of truth for your project: plans, features, bugs, evidence-gated lifecycle, PR-driven review. Inspired by Orchestra MCP and Studio PMS, backed by GitHub primitives.

## Why

Most teams already use GitHub Issues, but they use them as a dumb backlog. `gh-pms` adds the structure that real project management needs:

- **Plans** broken into **feature** sub-issues with dependency tracking
- **Status labels** that move through a real lifecycle (`todo → in-progress → ready-for-testing → ... → done`)
- **Gates** that require structured evidence (file paths, test results, self-review checklist) before a transition is allowed
- **WIP limits**, **cooldowns**, and **kind-specific skips** (bugs auto-skip the docs gate)
- **PR-driven review** — a `Closes #N` line, an `AskUserQuestion` approval, and `gh pr merge` close the loop

Everything lives natively in GitHub. No external database, no shadow state, no `.plans/` folder. Open the Issues tab and you see exactly where the project is.

## Install

```bash
# Add the marketplace (one-time)
/plugin marketplace add fadymondy/gh-pms

# Install the plugin
/plugin install gh-pms@gh-pms
```

Requires:
- **GitHub MCP** — already configured in Claude Code (auth via OAuth or PAT)
- **`gh` CLI** — for batch label operations: `brew install gh && gh auth login`
- **`jq`** — for JSON parsing in hooks: `brew install jq`

## Quick start

In any GitHub repo:

```bash
# 1. Bootstrap the repo (creates labels + templates + PR template)
/gh-pms:gh-init

# 2. From now on, just talk normally to Claude — the plugin auto-classifies
#    your prompts and ensures every actionable request becomes an issue.

# Examples:
"Plan the migration of auth flow to the bridge"
  → /gh-pms:gh-plan creates issue #N (type:plan)
  → /gh-pms:gh-breakdown creates feature sub-issues

"Add a /entities endpoint that returns sentiment scores"
  → /gh-pms:gh-feature creates issue #N (type:feature)
  → /gh-pms:gh-current sets status:in-progress
  → work happens, gates open, PR opens with Closes #N
  → user approves, PR merges, issue auto-closes

"The login page redirects to 404 after 2FA"
  → /gh-pms:gh-bug creates issue #N (type:bug, severity:medium)
```

## What gets created in your repo

After `gh-init`:

```
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

Labels (created in the repo settings):
  type:feature, type:bug, type:hotfix, type:chore, type:plan, type:prd, type:testcase, type:request
  status:todo, status:in-progress, status:ready-for-testing, status:in-testing,
    status:ready-for-docs, status:in-docs, status:documented, status:in-review,
    status:blocked, status:done
  severity:critical, severity:high, severity:medium, severity:low
  svc:app, svc:bridge, svc:studio, svc:edge, svc:db, svc:devops
```

## The lifecycle

```
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

| Skill | Mirrors |
|---|---|
| `/gh-pms:gh-init` | (bootstrap) |
| `/gh-pms:gh-plan` | `pms_create_plan` |
| `/gh-pms:gh-breakdown` | `pms_breakdown_plan` |
| `/gh-pms:gh-feature` | `pms_create_feature` |
| `/gh-pms:gh-bug` | `pms_create_bug_report` |
| `/gh-pms:gh-task` | `pms_create_task` |
| `/gh-pms:gh-current` | `pms_set_current_feature` |
| `/gh-pms:gh-advance` | `pms_advance_feature` |
| `/gh-pms:gh-validate` | `pms_validate_gates` |
| `/gh-pms:gh-review` | `pms_request_review` + `pms_submit_review` |
| `/gh-pms:gh-request` | `pms_create_request` |
| `/gh-pms:gh-status` | `pms_list_features` |

## Hooks

| Event | Behavior |
|---|---|
| `UserPromptSubmit` | Classifies the prompt, injects a context reminder so the agent knows to create/update issues |
| `PreToolUse` (on `mcp__github__create_pull_request`) | Blocks PR creation if `Closes #N` is missing from the body |
| `Stop` | Surfaces stale in-progress issues at end of turn |

## Programmatic guardrails

- **WIP limit** — One `status:in-progress` issue per assignee
- **Gate cooldown** — 30s minimum between transitions on the same issue (prevents fake batch-advancement)
- **Kind-specific skips** — Bugs/hotfixes/testcases skip Gate 3 (docs)
- **PR enforcement** — Gate 4 requires an open PR with `Closes #N`
- **User-only Gate 5** — Only `gh-review`'s Phase 2 can move to `done`, and only after `AskUserQuestion` approval

## Configuration

Per-repo overrides in `.github/gh-pms.yaml` (planned for v0.2):
- Custom workflow definitions
- Disable/enable specific gates
- Custom service labels
- Custom severity scale

## Inspiration

- **[Orchestra MCP](https://github.com/orchestra-mcp/framework)** — the gate model, evidence sections, sub-agent constraints
- **[Studio PMS](https://github.com/sentra-hub/studio)** — the workflow/gate/transition primitives via Supabase
- **GitHub Sub-issues** — the parent/child issue feature shipped late 2024

## License

MIT — see [LICENSE](LICENSE)

## Author

[Fady Mondy](https://github.com/fadymondy) · [@ID8-Media](https://github.com/ID8-Media)
