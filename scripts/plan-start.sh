#!/usr/bin/env bash
# plan-start.sh — activate a vault plan for the current branch.
# Sets frontmatter `status: active`, `branch:`, `issue:`. Does NOT write _CURRENT.md.
# Usage: plan-start <plan-name> [--branch <branch>] [--force]
#   Refuses if an unshipped plan is already current, unless --force
#   (--force tags the outgoing plan lifecycle/superseded first — no silent orphan).
# Exit: 0 ok | 2 usage/plan-not-found | 3 active plan exists (plan-done it or --force)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/workflow/vault-path.sh"
VAULT="$(resolve_vault_path "$REPO_ROOT")" || exit 1
PLANS="$VAULT/Plans"

force=0; branch=""; issue=""; name=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force)  force=1; shift ;;
    --branch) branch="${2:-}"; shift 2 ;;
    --issue)  issue="${2:-}"; shift 2 ;;
    *)        name="$1"; shift ;;
  esac
done
[ -n "$name" ] || { echo "usage: plan-start <plan-name> [--branch <b>] [--issue <n>] [--force]" >&2; exit 2; }
name="${name%.md}"; name="${name#Plans/}"
plan="$PLANS/$name.md"
[ -f "$plan" ] || { echo "✗ plan not found: $plan" >&2; exit 2; }

# Resolve the target branch before collision detection, otherwise omitting
# --branch bypasses the guard entirely.
[ -n "$branch" ] || branch="$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo none)"
[ -n "$branch" ] || branch="none"

# Find any other active plan on the same branch and warn/supersede.
# Plans active but without a real branch: field are legacy data and are ignored here;
# the migration reporter will surface them.
for other in "$PLANS"/*.md; do
  [ -f "$other" ] || continue
  [ "$other" = "$plan" ] && continue
  other_status=$(grep -m1 '^status:' "$other" 2>/dev/null | sed 's/^status:[[:space:]]*//' | tr -d '"' || echo "")
  other_branch=$(grep -m1 '^branch:' "$other" 2>/dev/null | sed 's/^branch:[[:space:]]*//' | tr -d '"' || echo "")
  if [ "$other_status" = "active" ] && [ -n "$other_branch" ] && [ "$other_branch" != "none" ] && [ "$other_branch" = "$branch" ]; then
    if [ "$force" -eq 1 ]; then
      # workflow-link: 0 ok | 1 nothing changed (idempotent) | 2 usage |
      # 3 malformed frontmatter. During --force supersede, 1 is a success.
      set +e
      "$SCRIPT_DIR/workflow/workflow-link.sh" "$other" --status superseded >/dev/null
      supersede_rc=$?
      set -e
      if [ "$supersede_rc" -eq 2 ] || [ "$supersede_rc" -eq 3 ]; then
        exit "$supersede_rc"
      fi
      # Also remove lifecycle/active from the outgoing plan's tags so tag-based
      # Obsidian queries do not keep treating it as active.
      python3 - "$other" <<'PY'
import sys, re
p = sys.argv[1]
with open(p) as f:
    s = f.read()
m = re.match(r'(?s)^(---\n.*?\n---\n)(.*)$', s)
if m:
    fm, body = m.group(1), m.group(2)
    fm = re.sub(r'(?m)^(tags:.*)$',
                lambda x: re.sub(r'\b(active)\b(?=\s*(?:,|\]|\'|"|\s*$))', 'superseded', x.group(1)), fm, count=1)
    fm = re.sub(r'(?m)^(\s*-\s*(?:[\w-]+/)?)active\s*["\']?\s*$', r'\1superseded', fm)
    with open(p, 'w') as f:
        f.write(fm + body)
PY
      echo "⚠ superseded outgoing active plan: ${other#$VAULT/} (branch: $other_branch)"
    else
      echo "✗ active plan already exists on branch $branch: ${other#$VAULT/}" >&2
      echo "  run: plan-done $(basename "$other" .md)   (or re-run with --force to supersede it)" >&2
      exit 3
    fi
  fi
done

# Build link arguments. Omit --branch when the resolved branch is "none"
# (e.g. detached HEAD), so we do not overwrite an existing branch value or
# write an unusable `branch: none` into the plan (#351).
link_args=("$plan" --status active)
[ "$branch" != "none" ] && link_args+=(--branch "$branch")
[ -n "$issue" ] && link_args+=(--issue "$issue")

# Link this plan to the branch and activate it.
# workflow-link exit codes: 0 ok | 1 nothing changed (idempotent) | 2 usage |
# 3 malformed/missing frontmatter. Only 1 is a success here.
set +e
"$SCRIPT_DIR/workflow/workflow-link.sh" "${link_args[@]}"
link_rc=$?
set -e
if [ "$link_rc" -eq 2 ] || [ "$link_rc" -eq 3 ]; then
  exit "$link_rc"
fi

echo "✓ plan active: Plans/$name.md (branch: ${branch:-none})"
