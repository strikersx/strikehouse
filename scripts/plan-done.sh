#!/usr/bin/env bash
# plan-done.sh — close a plan: tag it shipped via frontmatter.
# Does NOT reset _CURRENT.md; the plan branch is the source of truth.
# dev-workflow Step 7 / Process Invariant 13.
#
# Usage: plan-done <plan-name>
#   e.g. plan-done 2026-06-11-context-router-memory-cascade
#        plan-done Plans/2026-06-11-context-router-memory-cascade.md
#
# Exit: 0 ok | 2 usage/not-found
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/workflow/vault-path.sh"
VAULT="$(resolve_vault_path "$REPO_ROOT")" || exit 1
PLANS="$VAULT/Plans"

[ $# -ge 1 ] || { echo "usage: plan-done <plan-name>" >&2; exit 2; }
arg="$1"; arg="${arg%.md}"; arg="${arg#Plans/}"
plan="$PLANS/$arg.md"
[ -f "$plan" ] || { echo "✗ plan not found: $plan" >&2; exit 2; }

# 1. swap active/draft → shipped in the frontmatter.
python3 - "$plan" <<'PY'
import sys, re
p = sys.argv[1]
with open(p) as f:
    s = f.read()
m = re.match(r'(?s)^(---\n.*?\n---\n)(.*)$', s)
if not m:
    print("nao ha frontmatter YAML — nada tocado", file=sys.stderr); sys.exit(1)
fm, body = m.group(1), m.group(2)
before = fm

# Inline list: `tags: [..., lifecycle/active, ...]` or `tags: ["lifecycle/active"]`
# Word boundary + lookahead for a tag terminator (comma, closing bracket, quote,
# or end of value) so `active-foo` is never corrupted.
fm = re.sub(r'(?m)^(tags:.*)$',
            lambda x: re.sub(r'\b(active|draft)\b(?=\s*(?:,|\]|\'|"|\s*$))', 'shipped', x.group(1)), fm, count=1)

# Block list: `  - lifecycle/active`, `  - "active"`, or `  - 'active'`
fm = re.sub(r'(?m)^(\s*-\s*(?:[\w-]+/)?)(active|draft)\s*["\']?\s*$', r'\1shipped', fm)

# Standalone status: key (not inside tags)
fm = re.sub(r'(?m)^status:\s*(active|draft)\s*$', 'status: shipped', fm)

if fm == before:
    print("✗ nada mudou — o plano ja' estava fechado, ou o formato e' outro", file=sys.stderr); sys.exit(1)
with open(p, 'w') as f:
    f.write(fm + body)
PY
echo "✓ tagged shipped: ${plan#$VAULT/}"

# 2. Deprecated: _CURRENT.md is no longer the canonical active-plan pointer.
# The branch frontmatter in the vault plan is the source of truth.
# During transition, humans may still read _CURRENT.md as a convenience cache,
# but no script writes it as a control plane.
echo "→ Step 7 reminder: write a completion summary to the vault and link it from [[The Vault.md]]."
