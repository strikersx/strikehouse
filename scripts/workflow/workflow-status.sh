#!/usr/bin/env bash
# workflow-status.sh — read-only branch-as-key workflow status card.
# Resolves the current branch to a vault plan and reconstructs state from:
#   vault plan frontmatter, git tree, GitHub issue/PR, .git/workflow/ receipts.
# Usage: workflow-status.sh [--branch <b>]
# Exit: 0 (always, unless fatal error)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$SCRIPT_DIR/vault-path.sh"
VAULT="$(resolve_vault_path "$REPO_ROOT")" || exit 1
PLANS="$VAULT/Plans"

branch=""
while [ $# -gt 0 ]; do
  case "$1" in
    --branch) branch="$2"; shift 2 ;;
    *) echo "usage: workflow-status.sh [--branch <b>]" >&2; exit 2 ;;
  esac
done
[ -n "$branch" ] || branch="$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo "")"
[ -n "$branch" ] || branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# Resolve branch to a plan file. Precedence:
#   1. exact branch: match in frontmatter
#   2. alias match in branches: list
#   3. filename heuristic (branch suffix matches plan filename)
#   4. no match
resolve_plan() {
  local br="$1"
  python3 - "$PLANS" "$br" <<'PY'
import sys, os, re
plans_dir, br = sys.argv[1], sys.argv[2]
candidates = []

for fn in sorted(os.listdir(plans_dir)):
    if not fn.endswith('.md') or fn == '_CURRENT.md':
        continue
    p = os.path.join(plans_dir, fn)
    with open(p) as f:
        s = f.read()
    m = re.match(r'(?s)^---\n(.*?)\n---\n', s)
    if not m:
        continue
    fm = m.group(1)

    # 1. exact branch: match
    if re.search(rf'(?m)^branch:\s*["\']?{re.escape(br)}["\']?\s*$', fm):
        candidates.append((p, 'exact', fm))
        continue

    # 2. alias match in branches: list
    if re.search(r'(?m)^branches:\s*$', fm):
        # block form
        in_branches = False
        for line in fm.splitlines():
            if re.match(r'^branches:\s*$', line):
                in_branches = True
                continue
            if in_branches:
                if re.match(r'^\s+-\s', line):
                    val = line.strip().lstrip('-').strip()
                    if val == br:
                        candidates.append((p, 'alias', fm))
                        break
                else:
                    in_branches = False
    # inline branches: [a, b]
    inline = re.search(r'(?m)^branches:\s*\[([^\]]*)\]', fm)
    if inline:
        vals = [v.strip().strip('"\'') for v in inline.group(1).split(',')]
        if br in vals:
            candidates.append((p, 'alias', fm))
            continue

if not candidates:
    # 3. filename heuristic
    slug = re.sub(r'^(fix|feat|chore|docs|test)/', '', br)
    for fn in sorted(os.listdir(plans_dir)):
        if not fn.endswith('.md') or fn == '_CURRENT.md':
            continue
        base = fn[:-3]
        if slug.lower() in base.lower():
            p = os.path.join(plans_dir, fn)
            with open(p) as f:
                s = f.read()
            m = re.match(r'(?s)^---\n(.*?)\n---\n', s)
            fm = m.group(1) if m else ''
            candidates.append((p, 'heuristic', fm))

if not candidates:
    sys.exit(0)

if len(candidates) == 1:
    print(f'{candidates[0][0]}|{candidates[0][1]}')
    sys.exit(0)

# Disambiguate: prefer active status, then draft, then newest date
best = None
best_rank = -1
best_date = ''
for p, method, fm in candidates:
    st_match = re.search(r'(?m)^status:\s*(\S+)', fm)
    st = st_match.group(1) if st_match else ''
    dt_match = re.search(r'(?m)^date:\s*(\S+)', fm)
    dt = dt_match.group(1) if dt_match else ''
    rank = 0
    if st == 'active': rank = 2
    elif st == 'draft': rank = 1
    if rank > best_rank or (rank == best_rank and dt > best_date):
        best = (p, method)
        best_rank = rank
        best_date = dt

print(f'{best[0]}|{best[1]}')
PY
}

fm_value() {
  local file="$1" key="$2"
  grep -m1 "^$key:" "$file" 2>/dev/null | sed "s/^$key:[[:space:]]*//" | sed "s/^['\"]//; s/['\"]$//" || echo ""
}

fm_status() {
  local file="$1"
  local st=$(fm_value "$file" status)
  [ -n "$st" ] && { echo "$st"; return; }
  grep -m1 'lifecycle/active' "$file" >/dev/null 2>&1 && { echo "active"; return; }
  grep -m1 'lifecycle/draft' "$file" >/dev/null 2>&1 && { echo "draft"; return; }
  echo "unknown"
}

receipt_dir() {
  local root r
  root=$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null) || return
  r=$(git -C "$root" rev-parse --git-common-dir 2>/dev/null) || return
  case "$r" in /*) ;; *) r="$root/$r" ;; esac
  # Must match where receipt.sh writes. It pointed at .git/striker/ while the hook
  # wrote .git/workflow/, so the card reported e2e=no even with a signed receipt —
  # and "Next step" is computed from that flag, so the guidance was wrong too (#319).
  echo "$r/workflow"
}

# Locate the receipt.sh hook so the status card prints a runnable command.
# The skill lives in a versioned repo; older instructions pointed at a
# ~/.claude/skills/development-workflow path that is not always populated.
find_receipt_script() {
  local candidates=(
    "$REPO_ROOT/.claude/skills/development-workflow/hooks/receipt.sh"
    "$HOME/.claude/skills/development-workflow/hooks/receipt.sh"
    "$HOME/Documents/Project/development-workflow/hooks/receipt.sh"
    "$(command -v receipt.sh 2>/dev/null || true)"
  )
  for c in "${candidates[@]}"; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  echo "receipt.sh"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------


echo ""
echo "┌─ Workflow Status Card ──────────────────────────────────────────────────────┐"
printf "│ Branch:     %s\n" "$branch"

if [ "$branch" = "main" ] || [ "$branch" = "unknown" ]; then
  echo "│ Step:       on main / no branch — no feature workflow to resume."
  echo "└─────────────────────────────────────────────────────────────────────────────┘"
  exit 0
fi

resolved=$(resolve_plan "$branch")
if [ -z "$resolved" ]; then
  echo "│ Plan:       ✗ no vault plan resolves to this branch"
  echo "│ Next step:  Step 0 — create/link a plan"
  echo "│ Command:    bash scripts/plan-start.sh <plan-name> --branch $branch --issue <n>"
  echo "└─────────────────────────────────────────────────────────────────────────────┘"
  exit 0
fi
plan=$(printf '%s' "$resolved" | cut -d'|' -f1)
resolution=$(printf '%s' "$resolved" | cut -d'|' -f2-)

plan_rel="${plan#$VAULT/}"
plan_status=$(fm_status "$plan")
plan_branch=$(fm_value "$plan" branch)
issue=$(fm_value "$plan" issue)
title=$(fm_value "$plan" title)

printf "│ Plan:       %s (%s)\n" "$plan_rel" "$resolution"
printf "│ Title:      %s\n" "$title"
printf "│ Status:     %s\n" "$plan_status"
[ -n "$issue" ] && printf "│ Issue:      #%s\n" "$issue"

# Git state
branch_exists=$(git -C "$REPO_ROOT" rev-parse --verify "$branch" >/dev/null 2>&1 && echo "yes" || echo "no")
dirty=$(git -C "$REPO_ROOT" status --short 2>/dev/null | grep -q '^[^?]' && echo "dirty" || echo "clean")
untracked=$(git -C "$REPO_ROOT" status --short 2>/dev/null | grep -q '^??' && echo "+untracked" || echo "")
merged=$(git -C "$REPO_ROOT" merge-base --is-ancestor "$branch" origin/main 2>/dev/null && echo "merged" || echo "not merged")
last_commit_age=$(git -C "$REPO_ROOT" log -1 --format='%ar' "$branch" 2>/dev/null || echo "n/a")

printf "│ Git:        exists=%s %s %s merged=%s last=%s\n" "$branch_exists" "$dirty" "$untracked" "$merged" "$last_commit_age"

# GitHub state (graceful degradation)
gh_issue_state=""; gh_pr_state=""
if command -v gh >/dev/null 2>&1; then
  if [ -n "$issue" ]; then
    gh_issue_state=$(gh issue view "$issue" --repo strikersx/strikex --json state --jq '.state' 2>/dev/null || echo "")
  fi
  gh_pr_state=$(gh pr list --repo strikersx/strikex --head "$branch" --state all --json state --jq '.[0].state' 2>/dev/null || echo "")
fi
[ -n "$gh_issue_state" ] && printf "│ GitHub:     issue #%s = %s\n" "$issue" "$gh_issue_state"
[ -n "$gh_pr_state" ] && printf "│ GitHub:     PR = %s\n" "$gh_pr_state"
[ -z "$gh_issue_state" ] && [ -z "$gh_pr_state" ] && echo "│ GitHub:     (gh unavailable or no data)"

# Receipts
R=$(receipt_dir)
sha=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "")
e2e_receipt=""; review_receipt=""
if [ -n "$R" ] && [ -n "$sha" ]; then
  [ -f "$R/test-$sha.ok" ] && e2e_receipt="yes"
  [ -f "$R/review-$sha.json" ] && review_receipt="yes"
fi
printf "│ Receipts:   e2e=%s review=%s (HEAD %s)\n" "${e2e_receipt:-no}" "${review_receipt:-no}" "${sha:0:8}"

# Branch mismatch warning
if [ -n "$plan_branch" ] && [ "$plan_branch" != "$branch" ]; then
  printf "│ ⚠️  plan.branch (%s) differs from current branch (%s)\n" "$plan_branch" "$branch"
fi

# Merged-but-active warning
if [ "$merged" = "merged" ] && [ "$plan_status" = "active" ]; then
  echo "│ ⚠️  branch is merged but plan is still active — run plan-done"
fi

# Infer next step
next=""
if [ "$plan_status" = "draft" ]; then
  next="Step 1/2: Karpathy guidelines + brainstorm + adversarial review"
elif [ "$e2e_receipt" != "yes" ] && [ "$review_receipt" != "yes" ] && [ "$dirty" = "dirty" ]; then
  next="Step 3: finish the change, then commit"
elif [ "$e2e_receipt" != "yes" ]; then
  next="Step 4: run full e2e (bash $(find_receipt_script) test)"
elif [ "$review_receipt" != "yes" ]; then
  next="Step 4.5/4.7: self-review + peer review"
elif [ -z "$gh_pr_state" ] || [ "$gh_pr_state" = "OPEN" ] || [ "$gh_pr_state" = "DRAFT" ]; then
  next="Step 5: create/finalize PR with Closes #$issue"
elif [ "$merged" = "merged" ] && [ "$plan_status" = "shipped" ]; then
  next="Done — branch merged and plan shipped"
elif [ "$merged" = "merged" ] && [ "$plan_status" != "shipped" ]; then
  next="Step 7: run plan-done and write completion summary"
elif [ "$gh_pr_state" = "CLOSED" ]; then
  next="Step 7: PR closed without merge — re-open it or run plan-done"
else
  next="Step 6: merge / wait for CI"
fi

printf "│ Next step:  %s\n" "$next"
echo "└─────────────────────────────────────────────────────────────────────────────┘"
