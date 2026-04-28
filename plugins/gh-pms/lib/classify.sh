#!/usr/bin/env bash
# gh-pms · classify.sh
# Heuristic classifier — maps a user prompt to a kind that determines which
# skill should be invoked. NOT an LLM — just regex over the message.
#
# Output: one of
#   skip      — informational/question/trivial, do nothing
#   plan      — multi-feature work
#   feature   — single new functionality
#   bug       — defect report
#   chore     — refactor / cleanup / ci / deps
#   hotfix    — urgent prod fix
#   request   — mid-flow defer
#   current   — start work on existing issue
#   advance   — move existing issue forward
#   review    — request review on existing issue
#   status    — show dashboard
#   unknown   — fallback (let the agent classify)

set -euo pipefail

PROMPT="${1:-}"
[[ -z "$PROMPT" ]] && { echo "skip"; exit 0; }

# Lowercase for matching
LP=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Skip patterns — questions, status checks, trivial commands
if echo "$LP" | grep -qE '^(what|why|how|where|who|when|can you|could you|is it|are there|do we|does this|explain|show me|tell me|describe)' ; then
  echo "skip"; exit 0
fi
if echo "$LP" | grep -qE '\b(typo|format|lint|run tests|run the tests|hello|thanks|thank you|ok|yes|no|sure)\b' && [[ ${#PROMPT} -lt 80 ]]; then
  echo "skip"; exit 0
fi

# Status / list dashboard
if echo "$LP" | grep -qE '\b(status|where are we|whats next|what next|dashboard|list issues|show issues)\b'; then
  echo "status"; exit 0
fi

# Lifecycle on existing issue (mentions #N)
if echo "$LP" | grep -qE '#[0-9]+'; then
  if echo "$LP" | grep -qE '\b(start|begin|work on|current|active)\b.*#[0-9]+'; then
    echo "current"; exit 0
  fi
  if echo "$LP" | grep -qE '\b(advance|move|tests pass|ready for testing|ready for docs|done)\b'; then
    echo "advance"; exit 0
  fi
  if echo "$LP" | grep -qE '\b(review|open pr|pull request|approve|merge)\b'; then
    echo "review"; exit 0
  fi
fi

# Plans (3+ features)
if echo "$LP" | grep -qE '\b(plan|design|architect|roadmap|break down|breakdown)\b'; then
  echo "plan"; exit 0
fi

# Bugs
if echo "$LP" | grep -qE '\b(bug|broken|fails|crash|error|wrong|incorrect|regression|fix.*?(issue|problem|behavior))\b'; then
  echo "bug"; exit 0
fi

# Hotfixes
if echo "$LP" | grep -qE '\b(hotfix|urgent|critical|production.*?down|prod.*?broken)\b'; then
  echo "hotfix"; exit 0
fi

# Chore (refactor, deps, CI, cleanup)
if echo "$LP" | grep -qE '\b(refactor|cleanup|clean up|deprecate|migrate.*?dep|update deps|upgrade.*?package|rename|reorganize|ci|cloud build|github actions)\b'; then
  echo "chore"; exit 0
fi

# Mid-flow request markers
if echo "$LP" | grep -qE '\b(while.*at.*it|btw|by the way|also.*?can|after this|after that.*?do|next.*?could.*?you)\b'; then
  echo "request"; exit 0
fi

# Build/add/implement → feature
if echo "$LP" | grep -qE '\b(build|add|implement|create|new|introduce|enable|support).*?(feature|component|page|endpoint|hook|api|button|form)\b'; then
  echo "feature"; exit 0
fi
if echo "$LP" | grep -qE '\b(build|add|implement|create) [a-z]'; then
  echo "feature"; exit 0
fi

echo "unknown"
