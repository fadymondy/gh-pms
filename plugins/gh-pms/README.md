# gh-pms — Plugin

The `gh-pms` plugin itself. See the [marketplace README](../../README.md) for the user-facing overview, install instructions, and lifecycle diagram.

## Plugin layout

```
gh-pms/
├── .claude-plugin/plugin.json   # plugin manifest
├── README.md                    # this file
├── skills/                      # 13 skills, model-invoked by description match
│   ├── gh-init/SKILL.md
│   ├── gh-plan/SKILL.md
│   ├── gh-breakdown/SKILL.md
│   ├── gh-feature/SKILL.md
│   ├── gh-bug/SKILL.md
│   ├── gh-task/SKILL.md
│   ├── gh-current/SKILL.md       # auto-creates feature branch per branching policy
│   ├── gh-advance/SKILL.md       # Gate 1 refuses if HEAD is on protected base
│   ├── gh-push/SKILL.md          # commit + push + PR + Gate 4 + Gate 5 in one shot
│   ├── gh-validate/SKILL.md
│   ├── gh-review/SKILL.md
│   ├── gh-request/SKILL.md
│   └── gh-status/SKILL.md
├── agents/
│   └── gh-pms-orchestrator.md   # specialist sub-agent for full-lifecycle work
├── hooks/
│   ├── hooks.json               # event → script declarations
│   ├── user-prompt-submit.sh    # classifies prompts, injects reminders
│   ├── pre-pr-create.sh         # enforces Closes #N in PR body
│   └── on-stop.sh               # surfaces stale in-progress issues
├── workflows/
│   └── default.yaml             # statuses, gates, kinds, guardrails
├── templates/                   # markdown templates for each kind + PR
│   ├── feature.md, bug.md, chore.md, plan.md, prd.md, request.md, testcase.md
│   └── pull-request.md
└── lib/
    ├── classify.sh              # heuristic prompt → kind
    ├── validate-evidence.sh     # gate evidence validator
    └── ghcall.sh                # gh CLI wrapper for batch ops
```

## How skills get invoked

Skills are **model-invoked** based on the `description` in their frontmatter — Claude reads the descriptions of every available skill at session start and picks one when the user's request matches. The plugin's `UserPromptSubmit` hook adds a reminder banner that nudges Claude toward the right skill for each classified prompt kind.

## How hooks compose

- **`UserPromptSubmit`** runs every turn before Claude reads the user's message. Returns JSON with `hookSpecificOutput.additionalContext` — that string is invisibly appended to the prompt Claude sees.
- **`PreToolUse`** with `matcher: "mcp__github__create_pull_request"` only fires when that exact MCP tool is called. Returns `decision: "block"` to halt the call with a reason (no PR is created).
- **`Stop`** runs at end-of-turn. Outputs to stderr only — non-blocking.

## How `lib/validate-evidence.sh` works

Reads an evidence markdown blob (the comment the agent is about to post on the issue) and verifies:

1. Every required `## Section` is present
2. Each section has at least 10 chars of content
3. Sections marked `require_file_paths` contain at least one path that exists in the repo

Output is JSON — the calling skill parses it and either proceeds or surfaces the errors verbatim.

## Local development

```bash
# Test the plugin without installing — point Claude Code at the local plugin dir
claude --plugin-dir ~/Sites/gh-pms/plugins/gh-pms

# After making changes, reload
/reload-plugins

# Verify a specific skill description triggers correctly
# (model-invoked — say a matching prompt and watch it fire)
```

## Versioning

`plugin.json` declares `"version": "0.1.0"`. Bump on every release so users get an update prompt; omit `version` to use commit SHA (continuous delivery).

## Tests

Unit-test the lib scripts with bats (`brew install bats-core`):

```bash
bats tests/   # planned
```

## Roadmap

- v0.1 — labels, templates, 12 skills, 3 hooks, gate validation
- v0.2 — `.github/gh-pms.yaml` per-repo overrides
- v0.3 — GitHub Project (kanban) integration via `gh project`
- v0.4 — multi-repo plans (cross-repo sub-issues)
- v0.5 — `gh-pms-stats` skill: cycle time, gate failures, WIP heatmap
