#!/usr/bin/env bash
# gh-pms · validate-evidence.sh
# Validates an evidence comment against a gate spec from workflows/default.yaml.
#
# Input  (env):
#   GATE_ID                  — gate1..gate5
#   EVIDENCE_FILE            — path to a file containing the evidence markdown
#   ISSUE_KIND               — feature | bug | chore | hotfix | testcase | plan
#   REPO_ROOT                — git repo root (for file-path checks)
#
# Output (stdout, JSON):
#   { "valid": bool, "errors": [string, ...], "skipped": bool }

set -euo pipefail

GATE_ID="${GATE_ID:?GATE_ID env var required}"
EVIDENCE_FILE="${EVIDENCE_FILE:?EVIDENCE_FILE env var required}"
ISSUE_KIND="${ISSUE_KIND:-feature}"
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"

ERRORS=()

# Gate spec (could be parsed from workflows/default.yaml via yq, but to keep
# zero-deps we encode the rules here and keep them in sync with the YAML).
declare -A SECTIONS
case "$GATE_ID" in
  gate1)
    # Per-kind overrides — keep in sync with workflows/default.yaml
    # `gates[*].required_sections_per_kind`. Each kind's list REPLACES the
    # base for that kind; everything else uses the generic Summary/Changes/
    # Verification trio.
    case "$ISSUE_KIND" in
      bug)
        REQUIRED="Summary Reproduction Root_cause Fix Regression_test"
        FILES_REQUIRED_IN="Fix Regression_test"
        ;;
      hotfix)
        REQUIRED="Summary Impact Fix Verification Follow-up"
        FILES_REQUIRED_IN="Fix"
        ;;
      *)
        REQUIRED="Summary Changes Verification"
        FILES_REQUIRED_IN="Changes"
        ;;
    esac
    SKIP_KINDS=""
    ;;
  gate2)
    REQUIRED="Summary Results Coverage"
    FILES_REQUIRED_IN=""
    SKIP_KINDS=""
    ;;
  gate3)
    REQUIRED="Summary Location"
    FILES_REQUIRED_IN="Location"
    SKIP_KINDS="bug hotfix testcase"
    ;;
  gate4)
    REQUIRED="Summary Quality Checklist"
    FILES_REQUIRED_IN="Checklist"
    SKIP_KINDS=""
    ;;
  gate5)
    # User-approval gate, no evidence parsed here
    echo '{"valid": false, "errors": ["Gate 5 requires user approval via AskUserQuestion, not evidence"], "skipped": false}'
    exit 0
    ;;
  *)
    echo "{\"valid\": false, \"errors\": [\"Unknown gate: $GATE_ID\"], \"skipped\": false}"
    exit 1
    ;;
esac

# Auto-skip for kinds
if [[ -n "$SKIP_KINDS" ]] && echo " $SKIP_KINDS " | grep -q " $ISSUE_KIND "; then
  echo "{\"valid\": true, \"errors\": [], \"skipped\": true}"
  exit 0
fi

# Read evidence
if [[ ! -f "$EVIDENCE_FILE" ]]; then
  echo "{\"valid\": false, \"errors\": [\"Evidence file not found: $EVIDENCE_FILE\"], \"skipped\": false}"
  exit 1
fi
EVIDENCE=$(cat "$EVIDENCE_FILE")

# Check each required section
for SECTION in $REQUIRED; do
  # Find the section header
  if ! echo "$EVIDENCE" | grep -qE "^## ${SECTION}\b"; then
    ERRORS+=("Missing section: ## ${SECTION}")
    continue
  fi

  # Extract section content (between this header and next ## or end of file)
  CONTENT=$(echo "$EVIDENCE" | awk -v s="$SECTION" '
    BEGIN { capturing = 0 }
    /^## / {
      if (capturing) exit
      if ($0 ~ "^## " s "($|[^a-zA-Z])") capturing = 1
      next
    }
    capturing { print }
  ')

  # Strip whitespace and check min length
  TRIMMED=$(echo "$CONTENT" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  if [[ ${#TRIMMED} -lt 10 ]]; then
    ERRORS+=("## ${SECTION} has only ${#TRIMMED} chars (min 10)")
  fi

  # File-path check
  if [[ -n "$FILES_REQUIRED_IN" ]] && [[ "$FILES_REQUIRED_IN" == "$SECTION" ]]; then
    # Look for path-like tokens — bullet lines starting with - and containing / or .ext
    PATHS=$(echo "$CONTENT" | grep -E '^[[:space:]]*[-*][[:space:]]+' | grep -oE '[a-zA-Z0-9_./-]+\.[a-zA-Z0-9]+' || true)
    if [[ -z "$PATHS" ]]; then
      ERRORS+=("## ${SECTION} has no file paths (require_file_paths: true)")
    else
      # Verify at least one path exists in the repo
      FOUND=0
      while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        if [[ -e "$REPO_ROOT/$p" ]]; then
          FOUND=1; break
        fi
      done <<< "$PATHS"
      if [[ $FOUND -eq 0 ]]; then
        ERRORS+=("## ${SECTION} references files but none exist in the repo")
      fi
    fi
  fi
done

# Build JSON output
if [[ ${#ERRORS[@]} -eq 0 ]]; then
  echo '{"valid": true, "errors": [], "skipped": false}'
else
  ERROR_JSON=$(printf '%s\n' "${ERRORS[@]}" | jq -R . | jq -s .)
  echo "{\"valid\": false, \"errors\": $ERROR_JSON, \"skipped\": false}"
fi
