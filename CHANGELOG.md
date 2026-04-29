# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.0] — 2026-04-29

### Added

- gh-test-plan skill — generate testcase sub-issues from acceptance criteria (#17, PR #31)
- gh-search skill — ad-hoc issue queries beyond gh-status (#16, PR #30)
- gh-bulk skill — safe batch label / close / reassign / set-severity (#15, PR #29)
- Cross-repo plans — milestones spanning multiple repos (#14, PR #28)

### Changed

- Per-kind gate evidence sections (bug-specific Reproduction + Regression test) (#18, PR #32)

## [0.7.0] — 2026-04-29

### Added

- gh-metrics skill — time-in-status, gate failure rate, throughput (#13, PR #27)
- Optional AI reviewer on Gate 4 (sub-agent code review before user approval) (#12, PR #26)
- Wire Effort field end-to-end (gh-feature input + gh-status velocity) (#11, PR #25)
- gh-reopen skill — re-enter a done issue at in-progress (#10, PR #24)

## [0.6.0] — 2026-04-29

### Added

- gh-triage skill — accept/reject/dedupe the type:request inbox (#8, PR #23)
- CI gate on Gate 4 — refuse review-ready when checks are red (#7, PR #22)
- Per-repo config in .github/gh-pms.yaml (#6, PR #21)

## [0.5.0] — 2026-04-29

### Added

- gh-release skill — bundle issues, bump version, generate changelog, tag (#5, PR #20)
- gh-context — summarize repo history at session start (#9, PR #19)

## [0.4.0] — 2026-04-29

### Added — Severity is first-class on every issue kind

Severity (`critical | high | medium | low`) was bug-only in v0.3. v0.4 makes it a first-class dimension on **every** issue kind so a P0 feature blocking launch is meaningfully different from a polish item — that signal is no longer lost. Closes #2.

- **Canonical scale in `workflows/default.yaml#severities`** — single source of truth (`default: medium` + four-value list with label + Project field mapping). All severity-aware skills reference this list, so per-repo severity scales become a config-only change.
- **`gh-feature` skill** — accepts an optional `severity` input on every kind (not just hotfix). Defaults to `medium`. Applies both the `severity:*` label and (when a Project v2 board is attached) the `Severity` field. Hotfixes still default to `critical`.
- **`gh-task` skill** — sub-issue tasks **inherit the parent feature's severity** by default; can be overridden when the task is meaningfully more or less urgent than its parent. Checkbox tasks inherit implicitly.
- **`gh-bug` skill** — drops its private `critical | high | medium | low` definition; references the workflow file instead. Same defaults, same behavior, one source of truth.
- **`gh-status` skill** — within each Status bucket on the dashboard, issues are sorted by severity (Critical → Low) so urgent items surface first regardless of kind. Legend added to the example output.
- **Templates** — `feature.md`, `chore.md`, and `testcase.md` gain a `## Severity` section. `plan.md` and `prd.md` stay exempt (they aggregate child severities).
- **`gh-pms-orchestrator` agent** — skill-routing table calls out `severity` as an optional input on the relevant skills, plus a paragraph noting severity is first-class across kinds.

### Changed

- **Plugin manifest** — `version: 0.3.0 → 0.4.0`.

### Backwards compatibility

- Existing issues without a `severity:*` label remain valid.
- Skills called without `severity` get `medium` and are not blocked.
- `gh-bug` consumers see no behavior change.
- `gh-init bootstrap-labels` already creates the four severity labels; no re-bootstrapping needed.

## [0.3.0] — 2026-04-29

### Added — `gh-push` skill + branching policy

- **`gh-push` skill** — Ship completed work in one command. Composes commit (with conventional prefix and `(#N)` issue reference), branch push, PR open with `Closes #N`, Gate 4 self-review evidence, `AskUserQuestion` approval gate, and `gh pr merge` (configurable style). Auto-flips status `documented → in-review → done` on approval; routes back to `in-progress` on `Needs edits`. Mirrors the popular `/push` skill but PR-aware and lifecycle-integrated. Supports `--message`, `--no-merge`, `--admin`, `--squash` / `--merge` / `--rebase`, `--dry`, `--force` flags.
- **Branching policy** — New `branching` block in `workflows/default.yaml` enforcing the rule **every feature must end with a linked PR**. `protected_base` (default: `main` / `master`) and `pr_required_kinds` (default: feature / bug / hotfix / chore / testcase) define what cannot be committed directly to the base. `branch_template` (default: `{kind_short}/{number}-{slug}`) controls auto-generated branch names. `pr_must_close_issue: true` requires `Closes #N` in every PR body.

### Changed

- **`gh-current`** — Now creates the feature branch automatically when starting a `pr_required_kinds` issue from a `protected_base` checkout. Records `branch` + `base` in the per-issue state file so `gh-push` can find them later. The "🚧 Work started" comment now mentions the branch name.
- **`gh-advance`** — Gate 1 (in-progress → ready-for-testing) refuses to advance feature work that is still on the protected base branch. The error message walks the user through `git switch -c …` rescue. Bypassable per-issue with the `[gh-pms: branch-exception]` marker for legacy state.
- **`gh-pms-orchestrator` agent** — Skill-routing table now includes `gh-push`. Hard-rules section adds "never commit feature work directly to a `protected_base` branch" and "every feature must end with a linked PR containing `Closes #N`".
- **Plugin manifest** — `version: 0.2.0 → 0.3.0`.

### Known issues

- `lib/validate-evidence.sh` uses bash 4+ associative arrays (`declare -A`); macOS ships bash 3.2.57 by default and the script errors with `declare: -A: invalid option`. Skills currently fall back to manual section-length + file-existence checks on macOS. Tracked separately for a portability rewrite.

## [0.2.0] — 2026-04-29

### Added — GitHub-native primitives

The plugin now uses GitHub's first-class project-management features rather than leaning on labels for everything.

- **Issue Types** — When the repo's owner is an organization with Issue Types enabled (Feature, Bug, Task), the plugin sets the native type via GraphQL `updateIssue.issueTypeId` instead of (or in addition to) `type:*` labels. User-account repos and orgs without types fall back to labels seamlessly.
- **Projects v2** — `gh-init --with-project` provisions a `gh-pms` project with custom fields (Status, Severity, Effort, Service). All issue creation skills add new issues to the project; `gh-current` and `gh-advance` update the project's `Status` field as the canonical source of truth.
- **Milestones for plans** — `gh-plan` now creates a GitHub Milestone (with optional due date) as the primary plan primitive. The tracker issue still exists for narrative context, but progress and grouping live on the milestone. `gh-breakdown` attaches every child issue to the milestone via `--milestone` so GitHub's native progress bar reflects work completion.
- **`gh-relate` skill** — New skill for managing relationships: `depends_on`, `blocks`, `related_to`, `duplicate_of`. Encodes both ends (e.g. `## Depends on` on source, `## Blocks` on target) and uses GitHub's native cross-reference timeline. `duplicate_of` auto-closes the source with the `not planned` reason.
- **Auto-detection** — New `lib/ghcall.sh detect-features` subcommand reports which native primitives are available in the current repo. `gh-init` uses this to decide what to provision.
- **`set-status` unified setter** — `lib/ghcall.sh set-status <issue> "<Status Name>"` updates BOTH the `status:*` label AND the Project v2 Status field atomically. Skills no longer touch labels directly for status.

### Changed

- `workflows/default.yaml` — added `github_features` block (`issue_types`, `projects`, `milestones`, `fallback_to_labels`, `project_name`, `project_fields`), `kind_to_issue_type` mapping, and `relationships` definitions.
- `lib/ghcall.sh` — gained 14 new subcommands: `detect-features`, `ensure-project`, `ensure-project-field`, `project-item-add`, `project-item-set-field`, `ensure-milestone`, `issue-set-milestone`, `close-milestone`, `set-issue-type`, `resolve-issue-type-id`, `issue-node-id`, `issue-relate`, `duplicate-of`, `set-status`.
- `gh-init` — now performs feature detection, optionally creates a Project, and provisions custom fields. Old label-only path is preserved as fallback.
- `gh-plan` — creates a Milestone first; the tracker issue links to it.
- `gh-feature` / `gh-bug` — set native Issue Type after creation when available; add to project; attach to milestone if working under a plan.
- `gh-breakdown` — attaches every child to the parent plan's milestone and to the project board.
- `gh-current` / `gh-advance` — update the Project Status field via the unified setter (label + project field, atomic).
- `gh-status` — reads from the Project board first when one exists; shows milestone progress bars for plans.

### Notes

- **Token scope**: Projects v2 features require the `project` scope. `gh-init` checks for it and instructs the user to run `gh auth refresh -s project` if missing.
- **Org vs user accounts**: Issue Types are an org-level GitHub feature. Repos under user accounts fall back to `type:*` labels — no change in behavior, just no native types available.
- **Backwards compatible**: All changes preserve the v0.1 label-only flow as a fallback. Existing repos that bootstrapped with v0.1 keep working without re-running `gh-init`.

## [0.1.0] — 2026-04-29

### Added — Initial release

- Marketplace + plugin manifests
- 12 skills: `gh-init`, `gh-plan`, `gh-breakdown`, `gh-feature`, `gh-bug`, `gh-task`, `gh-current`, `gh-advance`, `gh-validate`, `gh-review`, `gh-request`, `gh-status`
- `gh-pms-orchestrator` agent for full-lifecycle delegation
- 3 hooks: `UserPromptSubmit` (classify + remind), `PreToolUse` on PR create (enforce `Closes #N`), `Stop` (stale-issue surface)
- 5-gate workflow with kind-specific skips, WIP guardrail, gate cooldown
- 7 issue templates + PR template
- Lib scripts: `classify.sh`, `validate-evidence.sh`, `ghcall.sh`
