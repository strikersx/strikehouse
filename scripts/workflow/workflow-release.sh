#!/usr/bin/env bash
# workflow-release.sh — append a release entry to the Active-Sessions log.
# Usage: workflow-release.sh --plan <plan-path> [--session <id>] [--note "..."]
# Exit: 0 ok | 2 usage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$SCRIPT_DIR/vault-path.sh"
VAULT="$(resolve_vault_path "$REPO_ROOT")" || exit 1
LOG="$VAULT/00-Meta/Active-Sessions.md"

plan=""; session_id=""; note=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plan)     plan="$2"; shift 2 ;;
    --session)  session_id="$2"; shift 2 ;;
    --note)     note="$2"; shift 2 ;;
    *) echo "usage: workflow-release.sh --plan <path> [--session <id>] [--note \"...\"]" >&2; exit 2 ;;
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

when=$(date -u +%Y-%m-%dT%H:%M:%SZ)
[ -n "$note" ] || note="paused / released"
note_esc=$(md_escape "$note")

printf "| %s | %s | %s | %s | %s | %s |\n" "$when" "$session_id_esc" "$br_esc" "$plan_rel_esc" "release" "$note_esc" >> "$LOG"
echo "✓ logged release: $br ($plan_rel)"
