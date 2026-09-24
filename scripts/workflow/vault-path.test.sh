#!/usr/bin/env bash
# vault-path.test.sh — offline harness for vault-path.sh.
# Usage: bash vault-path.test.sh [test_name]
#
# Same shape as scripts/dream.test.sh: temp dirs, no network, no vault touched.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/vault-path.sh"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

# Every case runs with a clean repo root and no inherited PROJECT_VAULT.
setup(){
  ROOT=$(mktemp -d)
  mkdir -p "$ROOT/repo/.claude" "$ROOT/vault"
  unset PROJECT_VAULT
}
teardown(){ rm -rf "$ROOT"; }

yml(){ printf '%s\n' "$1" > "$ROOT/repo/.claude/project.yml"; }

# ── o salto para a arvore-mae (#429) ────────────────────────────────────────────
# Num worktree ligado o `.git` e' um FICHEIRO; os project*.yml sao gitignored e nao
# viajam. Estes casos cobrem o ramo que o #429 acrescentou — e o par que importa e' o
# gitdir RELATIVO, que so' devolve resposta certa por acaso: resolveria contra o CWD do
# chamador e podia adoptar a config de um repo alheio (must-fix do [R14]).

# Monta <mae>/.claude/worktrees/wt, com o .git do worktree a apontar para a mae.
# O modo vai por NOME e o conteudo e' construido AQUI: os casos nao podem interpolar
# $ROOT no argumento, porque o $ROOT so' nasce dentro desta funcao — e um $ROOT vazio
# escrevia um gitdir sem caminho, com os testes a falharem por defeito do harness e nao
# do codigo. (Aconteceu, e a funcao real resolvia o fixture manual sem problema.)
#   absoluto | relativo | sem-newline | sem-gitdir
wt_setup(){
  ROOT=$(mktemp -d)
  mkdir -p "$ROOT/mae/.claude/worktrees/wt" "$ROOT/vault-da-mae"
  unset PROJECT_VAULT
  WT="$ROOT/mae/.claude/worktrees/wt"
  case "${1:-absoluto}" in
    relativo)    printf 'gitdir: ../../../mae/.git/worktrees/wt\n' > "$WT/.git" ;;
    rel-legitimo) printf 'gitdir: ../../../.git/worktrees/wt\n' > "$WT/.git" ;;
    sem-newline) printf 'gitdir: %s/mae/.git/worktrees/wt' "$ROOT" > "$WT/.git" ;;
    sem-gitdir)  printf 'lixo qualquer\n' > "$WT/.git" ;;
    *)           printf 'gitdir: %s/mae/.git/worktrees/wt\n' "$ROOT" > "$WT/.git" ;;
  esac
}
mae_yml(){ printf '%s\n' "$1" > "$ROOT/mae/.claude/project.yml"; }

t_wt_sobe_para_a_mae(){
  wt_setup absoluto
  mae_yml 'vault:
  path: '"$ROOT"'/vault-da-mae'
  got=$(resolve_vault_path "$WT")
  [ "$got" = "$ROOT/vault-da-mae" ] && ok "worktree sobe para a config da mae" \
    || no "worktree sobe para a config da mae" "got=$got"
  teardown
}

t_wt_gitdir_relativo_nao_adopta_repo_alheio(){
  # O MUST-FIX, e o caso tem de trazer o repo ALHEIO — sem ele nao discrimina nada.
  #
  # Com um gitdir relativo, o salto resolvia contra o CWD do CHAMADOR. Monta-se um
  # `alheio/` com config propria, alcancavel por `../alheio` a partir do cwd, e sem
  # relacao nenhuma com o worktree. A versao sem guarda adopta-o e devolve o vault de
  # outro repo, com rc=0 e sem um aviso. A versao certa nao salta e degrada para o erro.
  wt_setup relativo
  mae_yml 'vault:
  path: '"$ROOT"'/vault-da-mae'
  mkdir -p "$ROOT/sub" "$ROOT/alheio/.claude" "$ROOT/vault-alheio"
  printf 'vault:\n  path: %s/vault-alheio\n' "$ROOT" > "$ROOT/alheio/.claude/project.yml"
  printf 'gitdir: ../alheio/.git/worktrees/w\n' > "$WT/.git"
  # Asercao POSITIVA: exige o valor de recurso exacto. A versao anterior era `!= alheio`,
  # que um estoiro da funcao (saida vazia) tambem satisfazia — achado 6 do [R14].
  mkdir -p "$ROOT/from-env"
  got=$(cd "$ROOT/sub" && PROJECT_VAULT="$ROOT/from-env" resolve_vault_path "$WT" 2>/dev/null)
  [ "$got" = "$ROOT/from-env" ] && ok "gitdir relativo NAO adopta repo alheio" \
    || no "gitdir relativo NAO adopta repo alheio" "esperado $ROOT/from-env, veio: $got"
  teardown
}

t_wt_sem_newline_final(){
  # `read` devolve rc=1 mas JA' atribuiu a linha; o `|| gd=""` antigo deitava-a fora.
  wt_setup sem-newline
  mae_yml 'vault:
  path: '"$ROOT"'/vault-da-mae'
  got=$(resolve_vault_path "$WT")
  [ "$got" = "$ROOT/vault-da-mae" ] && ok ".git sem newline final continua a saltar" \
    || no ".git sem newline final continua a saltar" "got=$got"
  teardown
}

t_wt_git_sem_gitdir(){
  wt_setup sem-gitdir
  mae_yml 'vault:
  path: '"$ROOT"'/vault-da-mae'
  # Asercao POSITIVA, como as outras: exige o valor de recurso exacto. A negativa
  # (`!= vault-da-mae`) era satisfeita tambem por um estoiro da funcao — era o ultimo
  # oraculo nao-discriminante do ficheiro. Medido: contra um mutante
  # `resolve_vault_path(){ return 1; }` os outros 17 falham e este passava.
  mkdir -p "$ROOT/from-env"
  got=$(PROJECT_VAULT="$ROOT/from-env" resolve_vault_path "$WT" 2>/dev/null)
  [ "$got" = "$ROOT/from-env" ] && ok ".git sem linha gitdir: degrada" \
    || no ".git sem linha gitdir: degrada" "esperado $ROOT/from-env, veio: $got"
  teardown
}

t_wt_mae_sem_config(){
  wt_setup absoluto
  mkdir -p "$ROOT/from-env"
  got=$(PROJECT_VAULT="$ROOT/from-env" resolve_vault_path "$WT")
  [ "$got" = "$ROOT/from-env" ] && ok "mae sem config cai na cadeia normal" \
    || no "mae sem config cai na cadeia normal" "got=$got"
  teardown
}

t_wt_vault_relativo_da_mae(){
  # Relativo resolve contra QUEM DECLAROU (a mae), nao contra o worktree.
  wt_setup absoluto
  mkdir -p "$ROOT/mae/vault-rel"
  mae_yml 'vault:
  path: vault-rel'
  got=$(resolve_vault_path "$WT")
  [ "$got" = "$ROOT/mae/vault-rel" ] && ok "vault relativo resolve contra a mae" \
    || no "vault relativo resolve contra a mae" "got=$got"
  teardown
}

t_wt_gitdir_relativo_legitimo_salta(){
  # Um gitdir relativo que aponta MESMO para a mae tem de saltar. A guarda anterior
  # descartava-o: seguro, mas o salto ficava inerte em silencio nos repos que o git 2.49
  # escreve com caminhos relativos.
  wt_setup rel-legitimo
  mae_yml 'vault:
  path: '"$ROOT"'/vault-da-mae'
  got=$(cd / && resolve_vault_path "$WT")
  [ "$got" = "$ROOT/vault-da-mae" ] && ok "gitdir relativo legitimo salta" \
    || no "gitdir relativo legitimo salta" "got=$got"
  teardown
}

t_wt_default_irmao_da_mae(){
  # O caso MAIS COMUM: project.yml commitado SEM chave `vault:` — a forma que o
  # `development-workflow init` documenta como canonica. O default `../vault` tem de ser
  # irmao da MAE, nao do worktree.
  wt_setup absoluto
  mkdir -p "$ROOT/vault"
  printf 'tests:\n  e2e: "true"\n' > "$ROOT/mae/.claude/project.yml"
  got=$(resolve_vault_path "$WT")
  [ "$got" = "$ROOT/mae/../vault" ] || [ "$got" = "$ROOT/vault" ] \
    && ok "default ../vault e' irmao da mae" \
    || no "default ../vault e' irmao da mae" "got=$got"
  teardown
}

t_project_yml_wins_over_env(){
  setup
  yml 'vault:
  path: '"$ROOT"'/vault'
  mkdir -p "$ROOT/from-env"
  got=$(PROJECT_VAULT="$ROOT/from-env" resolve_vault_path "$ROOT/repo")
  [ "$got" = "$ROOT/vault" ] && ok "project.yml wins over PROJECT_VAULT" \
    || no "project.yml wins over PROJECT_VAULT" "got=$got"
  teardown
}

t_env_fallback(){
  setup
  mkdir -p "$ROOT/from-env"
  got=$(PROJECT_VAULT="$ROOT/from-env" resolve_vault_path "$ROOT/repo")
  [ "$got" = "$ROOT/from-env" ] && ok "PROJECT_VAULT fallback when no project.yml" \
    || no "PROJECT_VAULT fallback when no project.yml" "got=$got"
  teardown
}

t_local_yml_wins(){
  setup
  yml 'vault:
  path: '"$ROOT"'/vault'
  printf 'vault:\n  path: %s/from-local\n' "$ROOT" > "$ROOT/repo/.claude/project.local.yml"
  mkdir -p "$ROOT/from-local"
  got=$(resolve_vault_path "$ROOT/repo")
  [ "$got" = "$ROOT/from-local" ] && ok "project.local.yml wins over project.yml" \
    || no "project.local.yml wins over project.yml" "got=$got"
  teardown
}

t_nested(){
  setup
  yml 'github:
  repo: x/y
vault:
  path: '"$ROOT"'/vault'
  got=$(resolve_vault_path "$ROOT/repo")
  [ "$got" = "$ROOT/vault" ] && ok "nested vault:/path:" || no "nested vault:/path:" "got=$got"
  teardown
}

t_flat(){
  setup
  yml "vault: $ROOT/vault"
  got=$(resolve_vault_path "$ROOT/repo")
  [ "$got" = "$ROOT/vault" ] && ok "flat vault:" || no "flat vault:" "got=$got"
  teardown
}

# Regression for the greedy `sed 's/.*:…//'` class that reduced tests.e2e to "e2e".
t_value_with_colon(){
  setup
  mkdir -p "$ROOT/v:colon"
  yml 'vault:
  path: "'"$ROOT"'/v:colon"'
  got=$(resolve_vault_path "$ROOT/repo")
  [ "$got" = "$ROOT/v:colon" ] && ok "quoted value containing a colon" \
    || no "quoted value containing a colon" "got=$got"
  teardown
}

t_trailing_comment(){
  setup
  yml "vault: $ROOT/vault   # onde vivem os planos"
  got=$(resolve_vault_path "$ROOT/repo")
  [ "$got" = "$ROOT/vault" ] && ok "trailing comment stripped" \
    || no "trailing comment stripped" "got=$got"
  teardown
}

# Was broken: ${v#~/} tilde-expands its pattern, so `~/x` came out as "$HOME/~/x".
# The path need not exist — the error message carries the resolved path, which is
# what we assert.
t_tilde(){
  setup
  yml 'vault:
  path: ~/nao-existe-vault-test'
  err=$(resolve_vault_path "$ROOT/repo" 2>&1 >/dev/null)
  case "$err" in
    *"$HOME/nao-existe-vault-test"*) ok "tilde expands to \$HOME" ;;
    *"~"*) no "tilde expands to \$HOME" "tilde survived: $err" ;;
    *) no "tilde expands to \$HOME" "unexpected: $err" ;;
  esac
  teardown
}

t_sibling_fallback(){
  setup
  got=$(resolve_vault_path "$ROOT/repo")   # no project.yml at all
  [ "$got" = "$ROOT/vault" ] && ok "falls back to ../vault" \
    || no "falls back to ../vault" "got=$got"
  teardown
}

t_missing_is_actionable(){
  setup
  rm -rf "$ROOT/vault"
  err=$(resolve_vault_path "$ROOT/repo" 2>&1 >/dev/null); rc=$?
  [ "$rc" -eq 1 ] || no "missing vault exits 1" "rc=$rc"
  case "$err" in
    *"PROJECT_VAULT"*|*"project.yml"*) ok "missing vault names the fix" ;;
    *) no "missing vault names the fix" "message was: $err" ;;
  esac
  teardown
}

for t in ${1:-t_project_yml_wins_over_env t_env_fallback t_local_yml_wins t_nested t_flat t_value_with_colon t_trailing_comment t_tilde t_sibling_fallback t_missing_is_actionable t_wt_sobe_para_a_mae t_wt_gitdir_relativo_nao_adopta_repo_alheio t_wt_sem_newline_final t_wt_git_sem_gitdir t_wt_mae_sem_config t_wt_vault_relativo_da_mae t_wt_gitdir_relativo_legitimo_salta t_wt_default_irmao_da_mae}; do
  echo "$t"; "$t"
done
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
