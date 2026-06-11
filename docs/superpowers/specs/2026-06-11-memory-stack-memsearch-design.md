# Memory Stack (memsearch + custom glue) — Design

**Date:** 2026-06-11
**Status:** ⚠️ SUPERSEDED by `vault/Plans/2026-06-11-context-router-memory-cascade.md`.
Brainstorming reframed the problem from "storage" to "routing + state"; memsearch is
now Slice 2 of that larger plan, with the vault as the canonical recall corpus. Kept
for history only.
**Author:** ricore + Claude

## Goal

Recreate, verbatim, the three-job memory architecture from the referenced video
(STORE / INJECT / RECALL) inside Claude Code, using `memsearch` as the
search/index engine and hand-built glue (Stop hook, SessionStart hook,
memory-write skill, progressive recall ladder) on top.

The author of the video deliberately built custom hooks around memsearch rather
than using memsearch's own Claude Code plugin. We follow that approach: memsearch
provides L1/L2 recall + the vector index; everything else is bespoke.

## Decisions (locked)

| Decision | Choice |
|---|---|
| Scope | **Global, all projects.** Hooks + skill live in `~/.claude`; each repo gets its own `context/` data + index. |
| Coexistence with claude-mem | **Disable claude-mem's session-start injection.** Its DB stays installed; the new stack is the sole injector. |
| Identity files placement | `SOUL.md` + `USER.md` are **global** (`~/.claude/context/`). `MEMORY.md` + transcripts are **per-repo** (`<repo>/context/`). |
| Embedding provider | `onnx` — **local, free, no API key** (downloads ~558MB model on first run). |
| Per-turn summarizer | `claude -p --model claude-haiku-4-5` (uses logged-in CLI, no API key). |
| Python | memsearch needs ≥3.10; system is 3.9.6. Install via **`uv tool install "memsearch[onnx]" --python 3.12`**. |
| Nightly index cron | **Off by default.** Manual `memsearch index` for now. |

## Architecture

### 1. Engine — memsearch

```bash
uv tool install "memsearch[onnx]" --python 3.12   # 3.10+ via uv-managed interpreter
memsearch config set embedding.provider onnx        # local, zero API cost
```

Per repo, `memsearch index` builds `.memsearch/` (Milvus-lite vector DB) from the
repo's markdown files (`context/*.md`). `.memsearch/` is gitignored and rebuildable.

**CLI verbs (confirmed against PyPI 0.4.6):**
- `memsearch index` → build/refresh the vector index from markdown
- `memsearch search "<query>"` → ranked chunks (L1)
- `memsearch expand <chunk_hash>` → full markdown section around a chunk (L2)

### 2. STORE

**`~/.claude/hooks/transcript-capture.mjs`** — registered as a **Stop hook** (global).
- Fires after each turn completes.
- Summarizes the latest exchange via `claude -p --model claude-haiku-4-5` into a
  ≤500-char bullet.
- Appends the bullet to `<repo>/context/transcripts/YYYY-MM-DD.md` (the "daily log").
- Uses `$CLAUDE_PROJECT_DIR` to resolve the current repo; no-ops if there is no repo.
- **Recursion guard (critical):** sets an env sentinel (e.g. `MEMCAP_CHILD=1`) on the
  `claude -p` child so the Stop/SessionStart hooks no-op when that var is present —
  otherwise the summarizer call would re-trigger the hooks and loop forever.

**`~/.claude/skills/memory-write/SKILL.md`** — agent-invoked skill.
- Operations: `add | replace | remove` a curated fact in `<repo>/context/MEMORY.md`.
- Enforces a **2,500-char cap** on `MEMORY.md`.
- Dedup guard: skip/merge a fact that already exists.

**Indexing.** Manual `memsearch index` after meaningful writes. (Optional nightly
cron deferred.)

### 3. INJECT

**`~/.claude/hooks/memory-inject.mjs`** — registered as a **SessionStart hook** (global).
- Emits an `additionalContext` frozen snapshot **once per session** (~3,000 tokens):
  - `~/.claude/context/SOUL.md` — agent identity/voice
  - `~/.claude/context/USER.md` — user profile, **1.4KB cap**
  - `<repo>/context/MEMORY.md` — curated repo facts, **2.5KB cap**
  - `<repo>/context/transcripts/<today>.md` — today's daily log
- No-ops under the `MEMCAP_CHILD` sentinel.
- **claude-mem's session-start injection is disabled** so context isn't doubled.

### 4. RECALL — progressive ladder

Documented in the project `CLAUDE.md` so the agent knows the escalation order:

| Tier | Action | Cost |
|---|---|---|
| Tier 0 | Read already-injected `MEMORY.md` + daily log | free |
| L1 | `memsearch search "<query>"` → ranked chunks | local embed |
| L2 | `memsearch expand <chunk_hash>` → full section | local |
| L3 | `parse-transcript <session.jsonl>` → raw dialogue | local |

**`~/.claude/bin/parse-transcript.mjs`** — L3 fallback. Reads a Claude Code session
transcript (`~/.claude/projects/<slug>/*.jsonl`) and prints the raw dialogue for a
session id / hash.

## Files

**Create (global, `~/.claude/`):**
- `hooks/transcript-capture.mjs`
- `hooks/memory-inject.mjs`
- `bin/parse-transcript.mjs`
- `skills/memory-write/SKILL.md`
- `context/SOUL.md`
- `context/USER.md`

**Create (per-repo, strikehouse now):**
- `context/MEMORY.md`
- `context/transcripts/` (directory)
- `.memsearch/` (created by `memsearch index`, gitignored)

**Update:**
- `~/.claude/settings.json` — register Stop + SessionStart hooks; disable claude-mem
  session-start injection.
- strikehouse `CLAUDE.md` — add recall ladder + memory-write rules.
- strikehouse `.gitignore` — `.memsearch/` and `context/transcripts/` (noisy
  auto-generated daily logs). `context/MEMORY.md` (curated facts) **is** committed.

## Risks / Notes

- **Hook recursion** — the single most dangerous detail. The `MEMCAP_CHILD` sentinel
  must be set and honored by both hooks before the summarizer is ever invoked.
- **First-run onnx download** (~558MB) happens on the first `memsearch index`/`search`.
- **Stop-hook latency/cost** — one haiku call per turn; keep the summarizer prompt
  small and bounded.
- **Disabling claude-mem injection** — locate and remove/disable its SessionStart hook
  in settings without uninstalling the plugin (DB + `mem-search` skill remain usable).
- **`$CLAUDE_PROJECT_DIR` resolution** — hooks must gracefully no-op outside a repo.

## Out of scope (YAGNI)

- The GBrain reranker + cited-answer synthesis layer (video's "extra" on top of
  recall). Can be added later as an L1.5 step.
- Team/shared brain (Supabase + row-level security) — separate future project.
- Nightly index cron / launchd automation.
