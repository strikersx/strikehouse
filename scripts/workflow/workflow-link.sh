#!/usr/bin/env bash
# workflow-link.sh — safely mutate plan frontmatter for branch-as-key linking.
# Usage: workflow-link.sh <plan-path> --branch <b> [--status <s>] [--issue <n>] [--branches a,b]
#        workflow-link.sh <plan-path> --rename --branch <new-branch>
# Exit: 0 ok | 1 nothing changed | 2 usage/not-found | 3 malformed/missing frontmatter
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: workflow-link.sh <plan> --branch <b> [--status <s>] [--issue <n>] [--branches a,b]" >&2; exit 2; }
plan="$1"; shift
[ -f "$plan" ] || { echo "✗ plan not found: $plan" >&2; exit 2; }

branch=""; status=""; issue=""; branches=""; rename=0
while [ $# -gt 0 ]; do
  case "$1" in
    --branch)   branch="$2"; shift 2 ;;
    --status)   status="$2"; shift 2 ;;
    --issue)    issue="$2";  shift 2 ;;
    --branches) branches="$2"; shift 2 ;;
    --rename)   rename=1; shift ;;
    *) echo "✗ unknown option: $1" >&2; exit 2 ;;
  esac
done

python3 - "$plan" "$branch" "$status" "$issue" "$branches" "$rename" <<'PY'
import sys, re
p, branch, status, issue, branches, rename = sys.argv[1:7]
rename = rename == '1'
with open(p) as f:
    s = f.read()
m = re.match(r'(?s)^---\n(.*?)\n---\n(.*)$', s, re.DOTALL)
if not m:
    print("✗ missing YAML frontmatter"); sys.exit(3)
fm, body = m.group(1), m.group(2)
before = fm

# Update or add status:
if status:
    if re.search(r'(?m)^status:\s', fm):
        fm = re.sub(r'(?m)^status:\s*\S+', f'status: {status}', fm, count=1)
    else:
        fm = fm.rstrip('\n') + f'\nstatus: {status}'

# Update or add branch:
old_branch = None
if branch:
    br_match = re.search(r'(?m)^branch:\s*["\']?([^\"\'\n]+)', fm)
    if br_match:
        old_branch = br_match.group(1).strip()
    if re.search(r'(?m)^branch:\s', fm):
        fm = re.sub(r'(?m)^branch:\s*[^\n]+', f'branch: {branch}', fm, count=1)
    else:
        fm = fm.rstrip('\n') + f'\nbranch: {branch}'
    # On rename, append old branch to branches: list
    if rename and old_branch and old_branch != branch:
        branches = old_branch + (',' + branches if branches else '')

# Update or add issue:
if issue:
    if re.search(r'(?m)^issue:\s', fm):
        fm = re.sub(r'(?m)^issue:\s*[^\n]+', f'issue: "{issue}"', fm, count=1)
    else:
        fm = fm.rstrip('\n') + f'\nissue: "{issue}"'

# Update or add branches: list, deduplicating against existing entries.
if branches:
    items = [b.strip() for b in branches.split(',') if b.strip()]
    if re.search(r'(?m)^branches:\s*$', fm):
        # block form
        lines = fm.splitlines()
        new_lines = []
        in_branches = False
        added = False
        seen = set()
        for b in items:
            seen.add(b)
        for line in lines:
            if re.match(r'^branches:\s*$', line):
                in_branches = True
                new_lines.append(line)
                continue
            if in_branches:
                if re.match(r'^\s+-\s', line):
                    existing = line.strip().lstrip('-').strip().strip('"\'')
                    if existing not in seen:
                        seen.add(existing)
                    # discard original line; we will emit the canonical sorted list below
                    continue
                else:
                    # end of block; emit canonical list once
                    if not added:
                        for b in sorted(seen):
                            new_lines.append(f'  - {b}')
                        added = True
                    in_branches = False
            new_lines.append(line)
        if in_branches and not added:
            for b in sorted(seen):
                new_lines.append(f'  - {b}')
        fm = '\n'.join(new_lines)
    elif re.search(r'(?m)^branches:\s*\[', fm):
        existing_match = re.search(r'(?m)^branches:\s*\[([^\]]*)\]', fm)
        existing = [b.strip().strip('"\'') for b in existing_match.group(1).split(',')] if existing_match else []
        seen = set(items)
        for b in existing:
            if b and b not in seen:
                seen.add(b)
        fm = re.sub(r'(?m)^branches:\s*\[[^\]]*\]', f'branches: [{", ".join(sorted(seen))}]', fm, count=1)
    else:
        fm = fm.rstrip('\n') + '\nbranches:\n' + ''.join(f'  - {b}\n' for b in sorted(set(items)))

if fm == before:
    print("✗ nada mudou — o plano ja' tinha os valores")
    sys.exit(1)

with open(p, 'w') as f:
    f.write('---\n' + fm.rstrip('\n') + '\n---\n' + body)
print(f"✓ linked plan: branch={branch or 'unchanged'} status={status or 'unchanged'} issue={issue or 'unchanged'}")
PY
