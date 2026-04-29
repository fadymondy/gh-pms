---
name: gh-release
description: Cut a new release for the plugin — bundle issues closed since the last tag into a CHANGELOG entry, bump semver in plugin.json, refresh the README "What's new" banner, tag the commit, and (optionally) create a GitHub release. Auto-invoke when the user says "ship vX.Y", "cut a release", "release the plugin", "bump version".
---

# gh-release

Ship a new release in one shot. Replaces the manual sequence of "edit plugin.json → write CHANGELOG entry → update README → tag → push".

## When to use

- After a milestone closes and several PRs have merged since the last release
- User says "release v0.5", "cut a release", "ship the plugin", "bump version"
- As the **last** step before pushing — typically run from `main` after merging the final PR

## Inputs

```
gh-release [--bump patch|minor|major]
           [--dry]
           [--no-tag]
           [--no-release]
           [--commit]
           [--since <ref-or-date>]
```

| Flag | Default | Effect |
|---|---|---|
| `--bump` | `minor` | Semver step. `patch` for bug-only, `major` for breaking changes. |
| `--dry` | off | Print what would change without touching anything. |
| `--no-tag` | tags by default | Skip `git tag` (you'll tag manually). |
| `--no-release` | creates GH release after push | Skip `gh release create` (only writes CHANGELOG + README). |
| `--commit` | off (changes left staged for review) | Auto-commit the version bump as `chore(release): vX.Y.Z`. |
| `--since` | last git tag | Override the cutoff. Required for the very first run if the repo has no tags yet. Accepts a ref, tag, or `YYYY-MM-DD`. |

## What it does

### Step 1 — Compute the new version

Reads `plugins/gh-pms/.claude-plugin/plugin.json`, applies the requested semver bump, refuses if the resulting version already appears in `CHANGELOG.md` or as a git tag (idempotency).

### Step 2 — Find the cutoff

Default: `git describe --tags --abbrev=0`. If no tags exist, the skill **refuses** and asks for an explicit `--since` — better than silently bundling everything that ever merged.

### Step 3 — Gather merged PRs and the issues they closed

Calls `gh pr list --state merged --search "merged:>$cutoff"`. For each merged PR, parses `Closes #N` from the body and pulls that issue's labels. PRs with no `Closes #` reference are skipped (so non-issue commits like docs/CI don't show up — they belong in `### Changed` of the user's own writing if material).

### Step 4 — Group into Added / Changed / Fixed

Based on the closed issue's `type:*` label:

| Issue label | CHANGELOG bucket |
|---|---|
| `type:feature` (or no type) | `### Added` |
| `type:chore` | `### Changed` |
| `type:bug` / `type:hotfix` | `### Fixed` |

### Step 5 — Apply the changes

- `plugin.json` — bumps `version`
- `CHANGELOG.md` — prepends the new `## [X.Y.Z] — YYYY-MM-DD` entry above any prior entries
- `README.md` — inserts a new `## What's new in vX.Y` block; demotes the previous one to `### From vX.Y: (previous release)` (rename the placeholder to a punchier title afterwards if you like)
- (optional `--commit`) commits with `chore(release): vX.Y.Z`
- (default) creates the git tag `vX.Y.Z`
- (default) prints next-step commands to push and create the GitHub release

### Step 6 — Reports

```
✓ plugin.json: 0.4.0 → 0.5.0
✓ CHANGELOG.md: prepended v0.5.0 entry (5 issues)
✓ README.md: 'What's new in v0.5' banner inserted; previous demoted
✓ tagged v0.5.0

Next steps:
  git push origin main --follow-tags
  gh release create v0.5.0 --title "v0.5.0" --notes-file <(...)
```

## Cross-skill contract

- This is the dogfood-unblocker: every other skill in `gh-pms` ultimately needs this to ship.
- Run **after** all v0.5 PRs have merged into `main`, **not** during. The skill operates on the merged state, not in-flight branches.
- If you forget `--since` on the very first run (no tags yet), the skill refuses with a clear error — fix is to pass `--since <date-of-prior-release>`.

## First-time bootstrap on a repo with no tags

If you've been hand-cutting releases (or this is the first release ever):

```bash
# Tag the previous release retroactively at its release-commit:
git tag -a v0.4.0 <sha-of-the-v0.4-release-commit> -m "Release v0.4.0"
git push origin v0.4.0

# Then the skill works without --since on every subsequent release:
${CLAUDE_PLUGIN_ROOT}/lib/gh-release.sh --bump minor --commit
```

## Notes

- The README "What's new" demotion replaces the previous heading's prose-title with `(previous release)` — refine it manually if you want the historical title preserved with character.
- No CI integration: the skill does not check that PRs had passing checks (that's #7's job). Don't run release until you're confident main is green.
- Out of scope: signing artifacts, publishing to a marketplace registry beyond GitHub releases.
