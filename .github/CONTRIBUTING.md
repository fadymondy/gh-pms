# Contributing

Contributions are **welcome** and will be fully **credited**.

Please read and understand the contribution guide before creating an issue or pull request.

## Etiquette

This project is open source, and as such, the maintainers give their free time to build and maintain the source code held within. They make the code freely available in the hope that it will be of use to other developers. It would be extremely unfair for them to suffer abuse or anger for their hard work.

Please be considerate towards maintainers when raising issues or presenting pull requests. Let's show the world that developers are civilized and selfless people.

It's the duty of the maintainer to ensure that all submissions to the project are of sufficient quality to benefit the project. Many developers have different skills, strengths, and weaknesses. Respect the maintainer's decision, and do not be upset or abusive if your submission is not used.

## Viability

When requesting or submitting new features, first consider whether it might be useful to others. Open source projects are used by many developers, who may have entirely different needs to your own. Think about whether or not your feature is likely to be used by other users of the project.

This plugin sits in a specific niche — it implements GitHub-Issues-as-PMS for Claude Code. Features should align with that mission. If you want a generic PMS feature unrelated to GitHub or Claude Code, this is probably not the right project.

## Procedure

Before filing an issue:

- Attempt to replicate the problem to ensure it wasn't a coincidental incident
- Check existing issues — your bug or feature may already be tracked
- Check open pull requests in case a fix or feature is already in progress

Before submitting a pull request:

- Run `bash plugins/gh-pms/lib/ghcall.sh detect-features` against the test repo you're working in — confirm your changes work in both label-fallback and native-primitive paths
- Add or update tests if applicable
- Update the CHANGELOG.md (`Unreleased` section)

## Requirements

- **Bash 4+** for hooks and `lib/*.sh` scripts (works fine on macOS via brew bash, ships on most Linux)
- **`gh` CLI** authenticated, with `project` scope when developing project-related code
- **`jq`** for hook output parsing
- **No new heavy dependencies** in skill or hook scripts — keep the plugin install footprint small

### Code style

- **Skills** are markdown with YAML frontmatter. Keep `description` field crisp — that's what the model matches against
- **Bash scripts** use `set -euo pipefail` and quoted variables. No bashisms that fail on Bash 3 (we want macOS default-shell compatibility where possible)
- **Workflow YAML** changes must be backwards compatible — never remove a status or gate without a migration path
- **Hooks** must fail open (exit 0) on errors that aren't security-critical — the user shouldn't lose a turn because a stale-issue check timed out

### Pull request hygiene

- One concern per PR. Splitting a "fix bug + add feature" into two PRs is preferred
- Coherent commit history — squash WIP commits before opening the PR
- Use the user's own git config — **no `Co-Authored-By: Claude` lines** in commits or PR bodies
- PR body must include `Closes #N` so the issue auto-closes on merge (the plugin's own pre-pr-create hook will block PRs that don't)

### Versioning

We follow [SemVer 2.0](https://semver.org). Skill names, gate semantics, and CLI subcommand signatures are public API. Breaking changes warrant a major bump.

**Happy contributing!**
