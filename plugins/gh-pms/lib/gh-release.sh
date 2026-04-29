#!/usr/bin/env bash
# gh-pms · gh-release.sh
# Bundle issues closed since the last release into a CHANGELOG entry, bump
# the plugin's semver, update the README "What's new" banner, optionally tag
# and create a GitHub release.
#
# Usage:
#   gh-release.sh [--bump patch|minor|major] [--dry] [--no-tag] [--no-release] [--commit] [--since <ref-or-date>]
#
# Defaults: --bump minor, with tag + release, no auto-commit (changes are
# left in the working tree for review).

set -euo pipefail

BUMP="minor"
DRY=0
DO_TAG=1
DO_RELEASE=1
DO_COMMIT=0
SINCE=""

while (( $# > 0 )); do
  case "$1" in
    --bump)        BUMP="${2:?--bump needs a value}"; shift 2 ;;
    --dry)         DRY=1; shift ;;
    --no-tag)      DO_TAG=0; shift ;;
    --no-release)  DO_RELEASE=0; shift ;;
    --commit)      DO_COMMIT=1; shift ;;
    --since)       SINCE="${2:?--since needs a ref or date}"; shift 2 ;;
    *) echo "gh-release: unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$BUMP" in
  patch|minor|major) ;;
  *) echo "gh-release: --bump must be patch|minor|major" >&2; exit 2 ;;
esac

# ---------- preflight --------------------------------------------------------

command -v gh   >/dev/null 2>&1 || { echo "gh-release: gh CLI required" >&2; exit 127; }
command -v jq   >/dev/null 2>&1 || { echo "gh-release: jq required" >&2; exit 127; }
command -v git  >/dev/null 2>&1 || { echo "gh-release: git required" >&2; exit 127; }

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

PLUGIN_JSON="$REPO_ROOT/plugins/gh-pms/.claude-plugin/plugin.json"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"
README="$REPO_ROOT/README.md"

[[ -f "$PLUGIN_JSON" ]] || { echo "gh-release: $PLUGIN_JSON not found" >&2; exit 1; }
[[ -f "$CHANGELOG"   ]] || { echo "gh-release: $CHANGELOG not found"   >&2; exit 1; }
[[ -f "$README"      ]] || { echo "gh-release: $README not found"      >&2; exit 1; }

# ---------- compute new version ---------------------------------------------

CURRENT=$(jq -r .version "$PLUGIN_JSON")
[[ "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] \
  || { echo "gh-release: current version '$CURRENT' is not semver" >&2; exit 1; }

MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac
NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
TAG="v${NEW_VERSION}"

# Idempotency: refuse if the new version already shipped
if grep -q "^## \[${NEW_VERSION}\]" "$CHANGELOG"; then
  echo "gh-release: ${NEW_VERSION} already in CHANGELOG.md — refusing to re-release" >&2
  exit 1
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "gh-release: tag $TAG already exists — refusing to re-release" >&2
  exit 1
fi

# ---------- find the cutoff (since when?) -----------------------------------

if [[ -n "$SINCE" ]]; then
  CUTOFF="$SINCE"
elif LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null) && [[ -n "$LAST_TAG" ]]; then
  CUTOFF="$LAST_TAG"
else
  echo "gh-release: no git tag found and no --since provided." >&2
  echo "  For the first release with this skill, pass --since <date-or-ref>." >&2
  echo "  Example: --since 2026-04-28  (the day before the last hand-cut release)" >&2
  exit 1
fi

# Translate cutoff into an ISO date for `gh` search
if [[ "$CUTOFF" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  SINCE_DATE="$CUTOFF"
else
  # Assume it's a git ref; pull the commit date
  SINCE_DATE=$(git log -1 --format=%cd --date=short "$CUTOFF" 2>/dev/null || echo "")
  [[ -n "$SINCE_DATE" ]] || { echo "gh-release: could not resolve --since '$CUTOFF'" >&2; exit 1; }
fi

# ---------- gather merged PRs and the issues they closed --------------------

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

MERGED_PRS=$(gh pr list --repo "$REPO" --state merged \
  --search "merged:>$SINCE_DATE" --limit 100 \
  --json number,title,body,mergedAt,labels)

# For each merged PR, parse "Closes #N" from its body and pull the issue's labels
ISSUES=$(echo "$MERGED_PRS" | jq -r '.[] | "\(.number)\t\(.body // "")"' | while IFS=$'\t' read -r pr_num pr_body; do
  # Extract the closed issue number; first match wins
  closed=$(echo "$pr_body" | grep -oiE 'closes[[:space:]]+#[0-9]+' | head -1 | grep -oE '[0-9]+' || true)
  if [[ -n "$closed" ]]; then
    issue=$(gh issue view "$closed" --repo "$REPO" --json number,title,labels 2>/dev/null || echo "{}")
    if [[ -n "$issue" && "$issue" != "{}" ]]; then
      jq -n --argjson i "$issue" --arg pr "$pr_num" '$i + {pr: ($pr | tonumber)}'
    fi
  fi
done | jq -s '.')

ISSUE_COUNT=$(echo "$ISSUES" | jq 'length')
if (( ISSUE_COUNT == 0 )); then
  echo "gh-release: no closed issues found since $SINCE_DATE — refusing to release an empty version" >&2
  exit 1
fi

# ---------- group issues into Added / Changed / Fixed -----------------------

bucket_for() {
  local labels_json="$1"
  local types
  types=$(echo "$labels_json" | jq -r '.[].name' | grep -E '^type:' || true)
  case "$types" in
    *type:bug*|*type:hotfix*) echo "Fixed" ;;
    *type:chore*)             echo "Changed" ;;
    *type:feature*)           echo "Added" ;;
    *)                        echo "Added" ;;
  esac
}

ADDED=""
CHANGED=""
FIXED=""

while IFS= read -r row; do
  num=$(echo "$row" | jq -r '.number')
  title=$(echo "$row" | jq -r '.title' | sed -E 's/^\[[A-Z][a-z]+\][[:space:]]+//')
  pr=$(echo "$row" | jq -r '.pr')
  bucket=$(bucket_for "$(echo "$row" | jq '.labels')")
  line="- ${title} (#${num}, PR #${pr})"
  case "$bucket" in
    Added)   ADDED+="${line}"$'\n' ;;
    Changed) CHANGED+="${line}"$'\n' ;;
    Fixed)   FIXED+="${line}"$'\n' ;;
  esac
done < <(echo "$ISSUES" | jq -c '.[]')

TODAY=$(date -u +"%Y-%m-%d")

# ---------- assemble the new CHANGELOG block --------------------------------

ENTRY="## [${NEW_VERSION}] — ${TODAY}

"
[[ -n "$ADDED"   ]] && ENTRY+="### Added"$'\n\n'"$ADDED"$'\n'
[[ -n "$CHANGED" ]] && ENTRY+="### Changed"$'\n\n'"$CHANGED"$'\n'
[[ -n "$FIXED"   ]] && ENTRY+="### Fixed"$'\n\n'"$FIXED"$'\n'

# ---------- assemble the README "What's new" block --------------------------

# Demote any existing "## What's new in vX.Y" -> "### From vX.Y: ..."
README_NEW_BLOCK="## What's new in v${MAJOR}.${MINOR}

See [CHANGELOG.md](CHANGELOG.md#${NEW_VERSION//./}) for the full list. Highlights:

"
if [[ -n "$ADDED" ]]; then
  README_NEW_BLOCK+="$(echo "$ADDED" | head -3)"$'\n\n'
fi
README_NEW_BLOCK+="See \`CHANGELOG.md\` for the full v${NEW_VERSION} entry.

"

# ---------- dry mode --------------------------------------------------------

if (( DRY )); then
  echo "===== gh-release · DRY RUN ====="
  echo "Current:  $CURRENT"
  echo "New:      $NEW_VERSION   (bump=$BUMP)"
  echo "Tag:      $TAG   ($([ $DO_TAG -eq 1 ] && echo create || echo skip))"
  echo "Release:  $([ $DO_RELEASE -eq 1 ] && echo create || echo skip)"
  echo "Commit:   $([ $DO_COMMIT -eq 1 ] && echo auto || echo manual)"
  echo "Cutoff:   $SINCE_DATE"
  echo "Issues:   $ISSUE_COUNT"
  echo
  echo "===== CHANGELOG entry ====="
  printf '%s' "$ENTRY"
  echo
  echo "===== README banner ====="
  printf '%s' "$README_NEW_BLOCK"
  exit 0
fi

# ---------- apply changes ---------------------------------------------------

# 1. plugin.json version
tmp=$(mktemp)
jq --arg v "$NEW_VERSION" '.version = $v' "$PLUGIN_JSON" > "$tmp"
mv "$tmp" "$PLUGIN_JSON"

# 2. CHANGELOG — insert new entry after the prelude (before the first "## [")
tmp=$(mktemp)
awk -v entry="$ENTRY" '
  BEGIN { inserted = 0 }
  /^## \[/ && !inserted { print entry; inserted = 1 }
  { print }
  END { if (!inserted) print entry }
' "$CHANGELOG" > "$tmp"
mv "$tmp" "$CHANGELOG"

# 3. README — demote previous "## What's new in vX.Y" to "### From vX.Y: ..."
#    then insert the new block above it.
tmp=$(mktemp)
awk -v new_block="$README_NEW_BLOCK" '
  BEGIN { demoted = 0; inserted = 0 }
  /^## What.s new in v/ && !demoted {
    if (!inserted) { print new_block; inserted = 1 }
    sub(/^## /, "### From ")
    sub(/in v/, "v")
    sub(/$/, ": (previous release)")
    demoted = 1
    print
    next
  }
  { print }
  END { if (!inserted) print new_block }
' "$README" > "$tmp"
mv "$tmp" "$README"

echo "✓ plugin.json: $CURRENT → $NEW_VERSION"
echo "✓ CHANGELOG.md: prepended v${NEW_VERSION} entry ($ISSUE_COUNT issues)"
echo "✓ README.md: 'What's new in v${MAJOR}.${MINOR}' banner inserted; previous demoted"

# 4. Commit
if (( DO_COMMIT )); then
  git add "$PLUGIN_JSON" "$CHANGELOG" "$README"
  git commit -m "chore(release): v${NEW_VERSION}

Auto-generated by gh-release. ${ISSUE_COUNT} issues bundled since ${SINCE_DATE}." >/dev/null
  echo "✓ committed"
fi

# 5. Tag
if (( DO_TAG )); then
  if (( ! DO_COMMIT )); then
    echo "gh-release: --no-commit + tagging is unsafe — refusing. Pass --commit or --no-tag." >&2
    echo "  Changes are staged in your working tree. Commit, then run with --no-release --no-commit and tag manually if you want." >&2
  else
    git tag -a "$TAG" -m "Release ${TAG}"
    echo "✓ tagged $TAG"
  fi
fi

# 6. GitHub release (requires the tag to exist + be pushed; we'll create after push)
if (( DO_RELEASE )) && (( DO_TAG )) && (( DO_COMMIT )); then
  echo
  echo "Next steps:"
  echo "  git push origin main --follow-tags"
  echo "  gh release create $TAG --title \"$TAG\" --notes-file <(awk '/^## \\[${NEW_VERSION}\\]/{flag=1;next} /^## \\[/{flag=0} flag' $CHANGELOG)"
fi

echo
echo "Done. Review the changes, then push."
