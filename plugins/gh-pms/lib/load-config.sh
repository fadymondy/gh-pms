#!/usr/bin/env bash
# gh-pms · load-config.sh
# Merge the plugin's default workflow with the per-repo override (if any).
# Output: a single JSON document on stdout. Callers parse with jq.
#
# Resolution order (later wins, shallow merge per top-level key):
#   1. plugins/gh-pms/workflows/default.yaml          (always)
#   2. .github/gh-pms.yaml in the active repo         (if present)
#   3. GH_PMS_CONFIG env var pointing to a YAML file  (if set; for tests)
#
# Per-repo overrides are shallow at the top-level key. Whole sections
# (severities, github_features, gates, etc.) replace their default
# equivalents when present in the override file. Lists are not merged
# element-wise — a partial `severities.values` override replaces the
# whole list. This keeps semantics predictable; if you want to extend,
# copy the default values into your override and add yours.
#
# Requires: yq (mikefarah/yq v4+), jq.

set -euo pipefail

CACHE_TTL_DEFAULT=60
CACHE_TTL="${1:-$CACHE_TTL_DEFAULT}"

DEFAULT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/workflows/default.yaml"
OVERRIDE_REPO=""
OVERRIDE_ENV="${GH_PMS_CONFIG:-}"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REPO_ROOT=$(git rev-parse --show-toplevel)
  if [[ -f "$REPO_ROOT/.github/gh-pms.yaml" ]]; then
    OVERRIDE_REPO="$REPO_ROOT/.github/gh-pms.yaml"
  fi
fi

# ---------- preflight --------------------------------------------------------

command -v yq >/dev/null 2>&1 \
  || { echo "load-config: yq not found. Install via 'brew install yq'." >&2; exit 127; }
command -v jq >/dev/null 2>&1 \
  || { echo "load-config: jq not found." >&2; exit 127; }
[[ -f "$DEFAULT" ]] \
  || { echo "load-config: default workflow missing at $DEFAULT" >&2; exit 1; }

# ---------- cache lookup -----------------------------------------------------

CACHE_DIR="${HOME}/.cache/gh-pms"
mkdir -p "$CACHE_DIR"

# Cache key incorporates the override paths + their mtimes (so edits invalidate)
key_input="$DEFAULT"
[[ -n "$OVERRIDE_REPO" ]] && key_input+=":$(stat -f %m "$OVERRIDE_REPO" 2>/dev/null || stat -c %Y "$OVERRIDE_REPO")"
[[ -n "$OVERRIDE_ENV"  ]] && key_input+=":$(stat -f %m "$OVERRIDE_ENV"  2>/dev/null || stat -c %Y "$OVERRIDE_ENV")"
key=$(echo "$key_input" | shasum 2>/dev/null | awk '{print $1}' || echo "no-sha")
CACHE_FILE="${CACHE_DIR}/config-${key}.json"

if (( CACHE_TTL > 0 )) && [[ -f "$CACHE_FILE" ]]; then
  age=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE") ))
  if (( age < CACHE_TTL )); then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

# ---------- merge ------------------------------------------------------------

# Convert each YAML to JSON, then jq-merge top-level keys (shallow merge).
default_json=$(yq -o=json '.' "$DEFAULT")
merged="$default_json"

if [[ -n "$OVERRIDE_REPO" ]]; then
  override_json=$(yq -o=json '.' "$OVERRIDE_REPO")
  merged=$(jq -n --argjson a "$merged" --argjson b "$override_json" '$a * $b')
fi

if [[ -n "$OVERRIDE_ENV" && -f "$OVERRIDE_ENV" ]]; then
  override_json=$(yq -o=json '.' "$OVERRIDE_ENV")
  merged=$(jq -n --argjson a "$merged" --argjson b "$override_json" '$a * $b')
fi

# ---------- emit + cache -----------------------------------------------------

echo "$merged" > "$CACHE_FILE"
echo "$merged"
