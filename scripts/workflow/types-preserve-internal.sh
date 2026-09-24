#!/usr/bin/env bash
# types-preserve-internal.sh <tipos-novos> <tipos-actuais>
#
# Reimprime <tipos-novos> em stdout, reinserindo o bloco `__InternalSupabase` que
# <tipos-actuais> tenha e <tipos-novos> nao.
#
# PORQUE EXISTE, medido 2026-09-24:
# `supabase gen types --local` produz tipos de schema IDENTICOS aos do `--linked` — o
# unico delta sao 5 linhas:
#
#   __InternalSupabase: {
#     PostgrestVersion: "14.1"
#   }
#
# Sao metadados da versao do PostgREST, e a stack local corre uma versao diferente da
# hospedada, por isso o gerador local omite-as. Sem isto, correr `make db-types` num
# worktree local apagava-as de um ficheiro VERSIONADO — e a primeira versao desta mudanca
# "resolvia" isso com um comentario a dizer para nao commitar. Um comentario nao e' um
# guarda; foi o que a revisao por pares disse, e tinha razao.
#
# Preservar o valor do ficheiro actual e' o correcto e nao um remendo: a app implantada
# fala com a Supabase HOSPEDADA, logo e' a versao dela que o tipo deve descrever. O
# gerador local nao sabe isso; este script sabe.

set -euo pipefail

novo="${1:?uso: types-preserve-internal.sh <novos> <actuais>}"
actual="${2:?uso: types-preserve-internal.sh <novos> <actuais>}"

[ -f "$novo" ] || { printf 'ficheiro novo inexistente: %s\n' "$novo" >&2; exit 1; }

# Nada a preservar: ou o actual nao existe, ou nao tem o bloco, ou o novo ja' o traz.
# A DECLARACAO, nao qualquer mencao: o ficheiro gerado contem sempre
# `Omit<Database, "__InternalSupabase">` la' para baixo, e um grep solto casava com ISSO.
# O script concluia "o novo ja' tem o bloco" e nao fazia nada — silenciosamente.
declara() { grep -qE '^  __InternalSupabase: \{' "$1"; }

if [ ! -f "$actual" ] || ! declara "$actual" || declara "$novo"; then
  cat "$novo"
  exit 0
fi

# O bloco vive imediatamente a seguir a `export type Database = {`, e inclui os dois
# comentarios que o Supabase emite por cima dele. Extrai-se do ficheiro actual tal e qual.
tmp_bloco="$(mktemp)"
trap 'rm -f "$tmp_bloco"' EXIT

awk '
  /^export type Database = \{/ { dentro = 1; next }
  dentro && /^  [a-zA-Z_]+: \{/ && !/__InternalSupabase/ { exit }   # comecou a 1a schema
  dentro                        { print }
' "$actual" > "$tmp_bloco"

if [ ! -s "$tmp_bloco" ]; then
  # Nao se inventa: se a extraccao veio vazia, passa o novo tal e qual e diz-se porque.
  printf 'aviso: __InternalSupabase existe em %s mas nao foi extraido; tipos passam intactos\n' \
    "$actual" >&2
  cat "$novo"
  exit 0
fi

# `sed ... r ficheiro` e nao `awk -v bloco=...`: o -v do awk NAO aceita valores
# multi-linha e morre com "newline in string" — silenciosamente, porque quem chama
# redirecciona stdout e fica com um ficheiro VAZIO. Custou-me uma iteracao.
# `awk NF{u=NR}` guarda a ultima linha NAO vazia e imprime so' ate' la': o gerador termina
# com uma linha em branco a mais, e sem isto `make db-types` produzia um diff de 1 linha
# de cada vez que corresse, mesmo sem nada ter mudado. Ruido que ensina a ignorar diffs.
sed "/^export type Database = {/r $tmp_bloco" "$novo" | awk 'NF{u=NR} {l[NR]=$0} END{for(i=1;i<=u;i++) print l[i]}'
