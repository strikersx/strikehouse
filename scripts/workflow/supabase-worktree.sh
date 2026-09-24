#!/usr/bin/env bash
# supabase-worktree.sh — uma stack Supabase local por worktree.
#
#   supabase-worktree.sh provision   # levanta a stack deste worktree e reescreve o .env
#   supabase-worktree.sh teardown    # para-a e larga os volumes
#   supabase-worktree.sh inventory   # read-only: o que esta' de pe' e o que e' orfao
#
# Contrato do plugin (worktree-enter.sh exporta-as):
#   WORKTREE_MAIN  WORKTREE_DIR  WORKTREE_SLUG  WORKTREE_PORT
#   WORKTREE_LIVE_SLUGS (so' no inventory)
#
# POR QUE EXISTE, medido 2026-09-24 neste repo:
# os 6 worktrees partilhavam um unico Supabase HOSPEDADO. `vitest.config.integration.ts`
# diz-o no proprio comentario ("run against REAL Supabase database"), o e2e sobe o dev
# server que le o mesmo .env, e `make db-reset` TRUNCA tabelas e apaga auth users la'.
# Uma linha errada de qualquer worktree esvaziava producao.
#
# DUAS coisas isolam, e falhar uma nao chega — provado a correr, nao lido no --help:
#   1. project_id  — os containers chamam-se supabase_<servico>_<project_id>, e o
#      project_id vem do config.toml, que e' TRACKED, logo identico nos 6 worktrees.
#   2. portas      — so' com o project_id derivado a 2a stack nasce com o nome certo
#      (supabase_db_wt1) e morre em "Bind for 0.0.0.0:54322: port is already allocated".
# Dai o config DERIVADO: project_id = slug E bloco de portas deslocado.

set -euo pipefail

cmd="${1:-}"
WT_DIR="${WORKTREE_DIR:-$PWD}"
WT_MAIN="${WORKTREE_MAIN:-}"
SLUG="${WORKTREE_SLUG:-$(basename "$WT_DIR")}"
# project_id do Supabase aceita [a-zA-Z0-9_-]; um slug com barras (feat/x) parte tudo.
SLUG="$(printf '%s' "$SLUG" | tr -c 'a-zA-Z0-9_-' '-')"
DERIVED="$WT_DIR/.supabase-wt"
CFG="$DERIVED/supabase/config.toml"

# Portas base da CLI. O offset desloca o bloco inteiro de uma vez.
declare -a PORT_KEYS=(api db shadow studio inbucket analytics)
declare -a PORT_BASE=(54321 54322 54320 54323 54324 54327)

die() { printf '%s\n' "$*" >&2; exit 1; }

port_free() {
  # `lsof` e' externo e pode nao resolver; o fallback em bash nao depende de PATH.
  if command -v lsof >/dev/null 2>&1; then
    ! lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  else
    ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
  fi
}

# Escolhe o primeiro bloco de 100 em que TODAS as portas estao livres. Determinista para
# uma stack ja' criada: se o config derivado existe, reutiliza-se o offset que la' esta',
# senao dois `provision` seguidos mudavam as portas debaixo de um .env ja' escrito.
pick_offset() {
  if [ -f "$CFG" ]; then
    local existing
    existing="$(awk -F'= *' '/^port *=/ {print $2; exit}' "$CFG" 2>/dev/null || true)"
    if [ -n "$existing" ]; then printf '%s' "$(( existing - 54321 ))"; return 0; fi
  fi
  local off
  for off in $(seq 100 100 9000); do
    local i free=1
    for i in "${!PORT_BASE[@]}"; do
      port_free "$(( PORT_BASE[i] + off ))" || { free=0; break; }
    done
    [ "$free" = 1 ] && { printf '%s' "$off"; return 0; }
  done
  die "sem bloco de portas livre entre +100 e +9000"
}

# Quais funcoes correm SEM verificacao de JWT. Lido de scripts/deploy-edge-functions.sh,
# nao hardcodado: e' esse script que decide o que vai para producao, e duas listas
# separadas divergem em silencio — o local passaria a testar uma politica de auth que
# producao nao tem. [R21], o codigo e' a verdade.
jwt_exempt_functions() {
  local dep="$WT_DIR/scripts/deploy-edge-functions.sh"
  [ -f "$dep" ] || return 0
  grep -oE 'functions deploy [a-z0-9-]+ [^|]*--no-verify-jwt' "$dep" 2>/dev/null |
    awk '{print $3}' | sort -u
}

write_cfg() {
  local off="$1"
  mkdir -p "$DERIVED/supabase"
  # migrations por SYMLINK, nao copia: uma copia envelhece contra o worktree em silencio
  # e passa-se a testar o schema de ontem.
  ln -sfn "$WT_DIR/supabase/migrations" "$DERIVED/supabase/migrations"
  [ -d "$WT_DIR/supabase/functions" ] &&
    ln -sfn "$WT_DIR/supabase/functions" "$DERIVED/supabase/functions"
  cat > "$CFG" <<TOML
# GERADO por supabase-worktree.sh — nao editar a mao, nao commitar.
# O supabase/config.toml do repo fica intocado; este e' o derivado deste worktree.
project_id = "$SLUG"

[api]
port = $(( PORT_BASE[0] + off ))

[db]
port = $(( PORT_BASE[1] + off ))
shadow_port = $(( PORT_BASE[2] + off ))

[studio]
port = $(( PORT_BASE[3] + off ))

[inbucket]
port = $(( PORT_BASE[4] + off ))

[analytics]
port = $(( PORT_BASE[5] + off ))

[edge_runtime]
enabled = true
# "oneshot" e nao o "per_worker" por omissao: o proprio template da CLI diz que o hot
# reload do per_worker da' problemas "in large repos or with symlinks", e functions/ ENTRA
# aqui por symlink. Escolher o default seria escolher o caso que o aviso descreve.
policy = "oneshot"
inspector_port = $(( 8083 + off ))

[edge_runtime.secrets]
# env() le' a variavel do ambiente de quem corre o supabase start — por isso o provision
# exporta o .env antes. Os valores nunca entram neste ficheiro.
STRIPE_SECRET_KEY = "env(STRIPE_SECRET_KEY)"
STRIPE_WEBHOOK_SECRET = "env(STRIPE_WEBHOOK_SECRET)"
TOML

  # Um webhook do Stripe chega sem JWT: com verify_jwt ligado o endpoint responde 401 e o
  # teste ve' um 401 onde esperava 200 — que foi exactamente o que aconteceu antes disto.
  local fn
  for fn in $(jwt_exempt_functions); do
    printf '\n[functions.%s]\nverify_jwt = false\n' "$fn" >> "$CFG"
  done
}

# O .env de um worktree e' um SYMLINK para o do main (worktree-enter liga os ignorados).
# Escrever "para dentro" dele reescrevia o .env do main E o de todos os outros worktrees.
# Tem de se PARTIR o link primeiro. Foi isto que tornou esta tarefa impossivel de fazer
# com o mecanismo que ja' existia.
rewrite_env() {
  local src="${WT_MAIN:-$WT_DIR}/.env" dst="$WT_DIR/.env" tmp
  [ -f "$src" ] || die "sem .env em $src"
  local api key svc
  api="$(npx --no-install supabase status -o env --workdir "$DERIVED" 2>/dev/null | awk -F'=' '/^API_URL=/{print $2}' | tr -d '"')"
  key="$(npx --no-install supabase status -o env --workdir "$DERIVED" 2>/dev/null | awk -F'=' '/^PUBLISHABLE_KEY=/{print $2}' | tr -d '"')"
  svc="$(npx --no-install supabase status -o env --workdir "$DERIVED" 2>/dev/null | awk -F'=' '/^SERVICE_ROLE_KEY=/{print $2}' | tr -d '"')"
  [ -n "$api" ] && [ -n "$key" ] && [ -n "$svc" ] || die "a stack nao respondeu com as chaves"

  tmp="$(mktemp)"
  # Preserva tudo o que nao e' Supabase (STRIPE_*, GITHUB_CI_TOKEN, ...) a partir do main.
  # `|| true` nao e' decoracao: com `set -e`, um grep -v que nao deixa NENHUMA linha
  # devolve 1 e mata o script em silencio — exit 1, stderr vazio. Acontece a qualquer
  # .env que so' tenha chaves Supabase. Apanhado pelo teste de idempotencia.
  grep -vE '^(VITE_SUPABASE_URL|VITE_SUPABASE_PUBLISHABLE_KEY|SUPABASE_SERVICE_ROLE_KEY)=' "$src" > "$tmp" || true
  {
    printf '\n# --- reescrito por supabase-worktree.sh: stack local deste worktree ---\n'
    printf 'VITE_SUPABASE_URL="%s"\n' "$api"
    printf 'VITE_SUPABASE_PUBLISHABLE_KEY="%s"\n' "$key"
    printf 'SUPABASE_SERVICE_ROLE_KEY="%s"\n' "$svc"
  } >> "$tmp"
  # `mv` e nao um redirect, e a diferenca E' o invariante: um rename SUBSTITUI o proprio
  # link, enquanto `> "$dst"` o SEGUE e escreve no alvo — o .env do main, e portanto o
  # dos outros 5 worktrees. Havia aqui um `rm -f "$dst"` antes do mv, com um comentario
  # a dizer que era ele a proteger isto; um mutante que o removeu deixou os 10 testes
  # verdes, o que provou que era redundante e que o comentario estava errado. Quem
  # protege e' o mv. Mutar o mv para `cat > "$dst"` poe o teste vermelho — [R25].
  mv "$tmp" "$dst"
  printf '✓ .env deste worktree aponta para %s\n' "$api"
}

case "$cmd" in
  provision)
    off="$(pick_offset)"
    write_cfg "$off"
    printf '· stack "%s", portas +%s (api %s, db %s)\n' \
      "$SLUG" "$off" "$(( PORT_BASE[0] + off ))" "$(( PORT_BASE[1] + off ))"
    # Os `env(...)` do [edge_runtime.secrets] resolvem-se contra o ambiente de QUEM corre
    # o start. Sem isto o runtime sobe sem STRIPE_* e as funcoes falham por falta de
    # segredo em vez de por JWT — dois erros que se parecem no teste e nao na causa.
    # Le-se o .env do MAIN: o do worktree pode ja' ter sido reescrito para local, e os
    # segredos do Stripe nao sao locais.
    envsrc="${WT_MAIN:-$WT_DIR}/.env"
    if [ -f "$envsrc" ]; then
      set -a
      # shellcheck disable=SC1090
      . "$envsrc"
      set +a
    fi
    npx --no-install supabase start --workdir "$DERIVED" >/dev/null
    rewrite_env
    printf '✓ provisionado: %s\n' "$SLUG"
    ;;

  teardown)
    [ -d "$DERIVED" ] || { printf '· nada para largar (%s)\n' "$SLUG"; exit 0; }
    npx --no-install supabase stop --project-id "$SLUG" --no-backup >/dev/null 2>&1 || true
    rm -rf "$DERIVED"
    printf '✓ stack "%s" parada e volumes largados\n' "$SLUG"
    ;;

  inventory)
    # Read-only. So' reporta; nunca apaga — quem apaga e' o teardown, e so' o que criou.
    live=" ${WORKTREE_LIVE_SLUGS:-} "
    docker ps -a --filter 'name=supabase_db_' --format '{{.Names}}' 2>/dev/null |
      sed 's/^supabase_db_//' | sort -u | while read -r s; do
        [ -n "$s" ] || continue
        case "$live" in
          *" $s "*) printf '  %-28s viva\n' "$s" ;;
          *)        printf '  %-28s ORFA — supabase stop --project-id %s\n' "$s" "$s" ;;
        esac
      done
    ;;

  # Costuras para teste, e nao so': ambas sao uteis a mao quando algo corre mal.
  # `config` escreve o config derivado SEM tocar em Docker — e' o que torna possivel
  # testar a geracao do TOML (o bug dos backticks passava despercebido de outra forma,
  # porque so' se manifestava quando a CLI tentava parsear o ficheiro).
  config)
    off="$(pick_offset)"
    write_cfg "$off"
    printf '%s\n' "$CFG"
    ;;

  # `rewrite-env` isolado porque o invariante que ele protege e' o mais caro de partir:
  # o .env do worktree e' um SYMLINK para o do main, logo escrever "para dentro" dele
  # reescreve o do main E o dos outros 5 worktrees. Um teste tem de poder exercitar
  # isto sem levantar uma stack.
  rewrite-env)
    rewrite_env
    ;;

  *) die "uso: supabase-worktree.sh provision|teardown|inventory|config|rewrite-env" ;;
esac
