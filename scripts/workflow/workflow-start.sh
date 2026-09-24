#!/usr/bin/env bash
# workflow-start.sh — append a claim entry to the Active-Sessions log.
# Usage: workflow-start.sh --plan <plan-path> [--session <id>] [--note "..."] [--force]
# Exit: 0 ok | 2 usage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$SCRIPT_DIR/vault-path.sh"
VAULT="$(resolve_vault_path "$REPO_ROOT")" || exit 1
LOG="$VAULT/00-Meta/Active-Sessions.md"

plan=""; session_id=""; note=""; force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --plan)     plan="$2"; shift 2 ;;
    --session)  session_id="$2"; shift 2 ;;
    --note)     note="$2"; shift 2 ;;
    --force)    force=1; shift ;;
    *) echo "usage: workflow-start.sh --plan <path> [--session <id>] [--note \"...\"] [--force]" >&2; exit 2 ;;
  esac
done

[ -n "$plan" ] || { echo "✗ --plan required" >&2; exit 2; }
[ -f "$plan" ] || { echo "✗ plan not found: $plan" >&2; exit 2; }

[ -n "$session_id" ] || session_id="${PPID:-unknown}"
br=$(grep -m1 '^branch:' "$plan" 2>/dev/null | sed 's/^branch:[[:space:]]*//' | tr -d '"' || echo "unknown")
plan_rel="${plan#$VAULT/}"

# Escape pipes so markdown table columns stay intact.
md_escape() { printf '%s' "$1" | sed 's/|/\\|/g'; }
session_id_esc=$(md_escape "$session_id")
br_esc=$(md_escape "$br")
plan_rel_esc=$(md_escape "$plan_rel")

# Ensure the log directory exists before appending.
mkdir -p "$(dirname "$LOG")"

# Detect unclosed claim for same branch (claim or takeover counts as active).
# Use fixed-string matching so branch/plan names containing regex metacharacters
# (e.g. feature/round+score) do not corrupt the pattern or match the wrong row.
if [ "$force" -eq 0 ]; then
  pattern_base="| $session_id_esc | $br_esc | $plan_rel_esc |"
  last_claim=$({ grep -F "$pattern_base claim |" "$LOG" 2>/dev/null || true; grep -F "$pattern_base takeover |" "$LOG" 2>/dev/null || true; } | tail -1)
  if [ -n "$last_claim" ]; then
    echo "⚠ active claim already exists for $br — use --force to append a takeover note" >&2
    exit 2
  fi
fi

when=$(date -u +%Y-%m-%dT%H:%M:%SZ)
action="claim"
[ "$force" -eq 1 ] && action="takeover"
[ -n "$note" ] || note="starting work"
note_esc=$(md_escape "$note")

printf "| %s | %s | %s | %s | %s | %s |\n" "$when" "$session_id_esc" "$br_esc" "$plan_rel_esc" "$action" "$note_esc" >> "$LOG"
echo "✓ logged $action: $br ($plan_rel)"
