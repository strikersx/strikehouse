#!/usr/bin/env bash
# workflow-validate-plan.sh — read-only schema check for vault plan frontmatter.
# Validates the branch-as-key contract: status:, branch:, date:, title:, type:.
# Usage: workflow-validate-plan.sh <plan-path>
# Exit: 0 valid | 1 invalid | 2 file not found
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: workflow-validate-plan.sh <plan-path>" >&2; exit 2; }
plan="$1"
[ -f "$plan" ] || { echo "✗ plan not found: $plan" >&2; exit 2; }

python3 - "$plan" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p).read()
m = re.match(r'(?s)^(---\n.*?\n---\n)(.*)$', s)
if not m:
    print("✗ missing YAML frontmatter")
    sys.exit(1)
fm = m.group(1)

required = ['title:', 'type:', 'date:', 'status:', 'branch:']
missing = [k for k in required if not re.search(rf'(?m)^{re.escape(k)}\s', fm)]

if missing:
    print(f"✗ missing required frontmatter fields: {', '.join(missing)}")
    sys.exit(1)

status = re.search(r'(?m)^status:\s*(\S+)', fm)
if status and status.group(1) not in ('draft', 'active', 'shipped', 'superseded', 'aborted'):
    print(f"✗ invalid status value: {status.group(1)}")
    sys.exit(1)

branch = re.search(r'(?m)^branch:\s*["\']?([^\"\'\n]+)', fm)
if branch and not branch.group(1).strip():
    print("✗ branch field is empty")
    sys.exit(1)

print("✓ plan frontmatter valid")
PY
