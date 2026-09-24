#!/usr/bin/env bash
# vault-path.sh — resolve the docs vault. SOURCE it; do not execute.
#
# Resolution order matches the development-workflow skill cfg_get table:
#   .claude/project.local.yml  →  .claude/project.yml  →  PROJECT_VAULT  →  ../vault
#
# The skill reads project.yml first and falls back to env vars, so this
# resolver must do the same; otherwise guard-pr / stop-plan-open hooks read
# a different vault than plan-start / workflow-status (#351).

# resolve_vault_path <repo_root>
#   Echoes the absolute vault path, or exits 1 with an actionable message.
resolve_vault_path() {
  local repo_root="$1" vault="" cfg_root="$1" yml_local yml

  # Num WORKTREE ligado o `.git` e' um FICHEIRO com `gitdir: <mae>/.git/worktrees/<nome>`.
  # E os project*.yml sao config de MAQUINA (caminhos absolutos), logo gitignored, logo
  # NAO viajam para dentro do worktree. Sem este salto, qualquer script corrido de la'
  # nao achava o vault e mandava exportar PROJECT_VAULT a' mao — um passo manual por
  # worktree, que e' precisamente o atrito que faz a gente deixar de os usar.
  # Sentido em 2026-08-18 a fechar o plano do #411.
  if [ ! -f "$cfg_root/.claude/project.local.yml" ] && [ ! -f "$cfg_root/.claude/project.yml" ] \
     && [ -f "$repo_root/.git" ]; then
    local gd mae
    # `|| :` e nao `|| gd=""`: um .git sem newline final devolve rc=1 MAS ja' atribuiu a
    # linha. O `gd=""` deitava-a fora e anulava a correccao inteira nesse caso.
    read -r gd < "$repo_root/.git" 2>/dev/null || :
    case "$gd" in
      gitdir:*)
        # Um gitdir RELATIVO ancora-se contra o `repo_root`, nunca contra o CWD.
        #
        # A primeira versao disto so' aceitava absolutos e descartava os relativos. Era
        # seguro mas INERTE: o git 2.49 escreve-os relativos com `worktree.useRelativePaths`,
        # com `worktree add --relative-paths` e depois de `git worktree repair` — e nesses
        # repos o salto nunca acontecia, em silencio. O defeito original era resolver contra
        # o CWD do CHAMADOR (o mesmo worktree dava vaults diferentes conforme o cwd, e
        # adoptava a config de um repo alheio); ancorar mata isso E mantem o salto vivo.
        # E' tambem o que este ficheiro ja' faz aos caminhos de vault relativos mais abaixo:
        # recusar ancorar aqui era a incoerencia.
        #
        # Nao se reutiliza o `wt_main_of` do plugin (hooks/lib/worktree-env.sh): vive num
        # caminho VERSIONADO do cache (.../0.3.6/hooks/lib/), que varia por maquina e por
        # versao instalada — um script deste repo nao lhe pode chamar de forma fiavel.
        gd="${gd#gitdir:}"; gd="${gd# }"
        case "$gd" in
          /*) ;;
          *)  gd="$repo_root/$gd" ;;
        esac
        # A verificacao do ABSOLUTO tem de vir DEPOIS de tirar o prefixo e o espaco: um
        # `.git` real diz `gitdir: /caminho`, com espaco, e um `case gitdir:/*` nunca
        # casaria com ele — partia o caso normal por completo (apanhado pelo harness).
        case "$gd" in
          /*)
            gd="${gd%/worktrees/*}"; mae="${gd%/.git}"
            if [ -n "$mae" ] && { [ -f "$mae/.claude/project.local.yml" ] || [ -f "$mae/.claude/project.yml" ]; }; then
              cfg_root="$mae"
            fi ;;
        esac ;;
    esac
  fi
  yml_local="$cfg_root/.claude/project.local.yml"; yml="$cfg_root/.claude/project.yml"

  # 1. Committed/per-user project configs take precedence over env vars.
  if [ -f "$yml_local" ] || [ -f "$yml" ]; then
    if ! command -v python3 >/dev/null 2>&1; then
      echo "[workflow] python3 is required to parse .claude/project*.yml" >&2
      return 1
    fi
    if ! python3 -c "import yaml" 2>/dev/null; then
      echo "[workflow] PyYAML is required to parse .claude/project*.yml (install: pip install pyyaml)" >&2
      return 1
    fi
    vault=$(python3 - "$yml_local" "$yml" 2>/dev/null <<'PY'
import sys, os, yaml
for path in sys.argv[1:]:
    if not path or not os.path.exists(path):
        continue
    try:
        with open(path) as f:
            d = yaml.safe_load(f) or {}
    except Exception:
        continue
    v = d.get('vault')
    if isinstance(v, dict):
        v = v.get('path')
    if v:
        print(v)
        break
PY
)
  fi

  # 2. Env var fallback (matches the skill's env fallback column).
  [ -n "$vault" ] || vault="${PROJECT_VAULT:-}"

  # 3. Sibling vault default — irmao de QUEM tem a config (`cfg_root`), nao do worktree.
  # Sem isto o sintoma do #429 sobrevivia no caso MAIS COMUM: a config existe SO' na mae
  # — que e' o que acontece aqui, porque o .gitignore ignora `.claude/*` e o ficheiro nao
  # viaja para o worktree — e sem chave `vault:`. De dentro do worktree,
  # `$repo_root/../vault` apontava para <mae>/.claude/worktrees/../vault, que nao existe.
  #
  # NOTA de coerencia: o cabecalho deste ficheiro fala do project.yml como COMMITADO, que
  # e' o que o README do plugin descreve. Neste repo esta' gitignored, e e' por isso que o
  # salto e' preciso. Se algum dia passar a viajar para o worktree, o salto deixa de
  # disparar e este default volta a resolver contra o worktree — medido pelo [R14].
  [ -n "$vault" ] || vault="$cfg_root/../vault"

  # Expand tilde, including bare "~".
  # `${HOME:-}` e nao `$HOME`: os cinco chamadores correm sob `set -u` e um HOME por
  # definir abortava aqui com "unbound variable" em vez de degradar. Pre-existente, mas
  # o salto para a mae cria uma via nova para la' chegar — um `path: ~/...` na config da
  # MAE passa a ser legivel de dentro de um worktree, onde antes nunca era.
  case "$vault" in
    "~"/*) [ -n "${HOME:-}" ] && vault="$HOME/${vault#"~/"}" ;;
    "~")   [ -n "${HOME:-}" ] && vault="${HOME}" ;;
  esac

  # Relativo resolve contra quem DECLAROU o valor (`cfg_root`), nao contra o worktree.
  # Sao o mesmo directorio no caso normal; com o salto para a mae deixam de ser, e um
  # `path: ../vault` na config da mae apontava para <mae>/.claude/worktrees/<wt>/../vault.
  case "$vault" in
    /*) ;;
    *) vault="$cfg_root/$vault" ;;
  esac

  if [ ! -d "$vault" ]; then
    cat >&2 <<EOF
[workflow] Vault not found: $vault

The vault holds the plans these scripts read. Point them at it with either:

  export PROJECT_VAULT=/path/to/vault

or a \`vault:\` entry in $cfg_root/.claude/project.local.yml or .claude/project.yml:

  vault:
    path: /path/to/vault

(Those files are gitignored, so a fresh clone will not have them.)
EOF
    return 1
  fi
  (cd "$vault" && pwd)
}
