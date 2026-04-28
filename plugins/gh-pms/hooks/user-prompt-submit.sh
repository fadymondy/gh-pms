#!/usr/bin/env bash
# gh-pms · UserPromptSubmit hook
# Injects gh-pms protocol reminder into the agent's context every turn.
# Skips silently when not in a GitHub repo, or when the prompt is clearly
# non-actionable (questions, "show me", status checks, single-line tweaks).

set -euo pipefail

# Read the hook payload (JSON on stdin)
INPUT="$(cat)"
PROMPT="$(echo "$INPUT" | jq -r '.prompt // ""')"
CWD="$(echo "$INPUT" | jq -r '.cwd // ""')"

# Bail if not in a git repo with a GitHub remote
cd "$CWD" 2>/dev/null || exit 0
REMOTE=$(git remote get-url origin 2>/dev/null || true)
if [[ -z "$REMOTE" ]] || [[ ! "$REMOTE" =~ github\.com ]]; then
  exit 0
fi

# Extract owner/repo
REPO_SLUG=$(echo "$REMOTE" | sed -E 's#.*github\.com[:/]([^/]+/[^/]+)\.git#\1#; s#\.git$##')

# Classify the prompt — call the classifier
KIND=$("${CLAUDE_PLUGIN_ROOT}/lib/classify.sh" "$PROMPT" 2>/dev/null || echo "unknown")

# If kind is "skip" (questions, status, trivial), do nothing
if [[ "$KIND" == "skip" ]]; then
  exit 0
fi

# Map kind → recommended skill
case "$KIND" in
  plan)     SKILL="/gh-pms:gh-plan then /gh-pms:gh-breakdown" ;;
  feature)  SKILL="/gh-pms:gh-feature" ;;
  bug)      SKILL="/gh-pms:gh-bug" ;;
  chore)    SKILL="/gh-pms:gh-feature with kind=chore" ;;
  hotfix)   SKILL="/gh-pms:gh-feature with kind=hotfix" ;;
  request)  SKILL="/gh-pms:gh-request" ;;
  current)  SKILL="/gh-pms:gh-current" ;;
  advance)  SKILL="/gh-pms:gh-advance" ;;
  review)   SKILL="/gh-pms:gh-review" ;;
  status)   SKILL="/gh-pms:gh-status" ;;
  *)        SKILL="the appropriate /gh-pms:* skill" ;;
esac

# Inject context for the agent
cat <<EOF
{
  "hookSpecificOutput": {
    "additionalContext": "**[gh-pms protocol active]** This repo is ${REPO_SLUG}. The user's request was classified as kind=${KIND}. Before doing the work: (1) ensure the gh-pms labels exist in the repo (run /gh-pms:gh-init if a previous skill reports missing labels); (2) ensure a GitHub issue exists for this work (use ${SKILL}); (3) reference the issue number in your response; (4) follow the lifecycle (todo → in-progress → ... → done) with evidence at each gate. Never advance to status:done without explicit user approval via /gh-pms:gh-review."
  }
}
EOF
