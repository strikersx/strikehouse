# StrikeHouse - Makefile
# Comandos comuns para desenvolvimento

.PHONY: dev build test test-e2e lint push-ci clean help db-push db-types db-reset db-local db-local-stop

# Desenvolvimento
dev:
	npm run dev

build:
	npm run build

# Testes
test:
	npm run test:unit -- --run --exclude="**/integration/**"

test-watch:
	npm run test:unit --exclude="**/integration/**"

test-coverage:
	npx vitest --coverage --run --exclude="**/integration/**"

test-integration:
	npm run test:integration:run

test-e2e:
	npx playwright test e2e/pricing/ --workers=1

# Linting
lint:
	npm run lint

lint-fix:
	npm run lint -- --fix

# Deploy
deploy:
	npm run build && git add -A && git commit -m "Deploy" && git push

# Push com token CI (para ficheiros de workflow)
push-ci:
	@source .env && \
	git remote set-url origin "https://$${GITHUB_CI_TOKEN}@github.com/ricore77995/strikehouse.git" && \
	git push && \
	git remote set-url origin "https://github.com/ricore77995/strikehouse.git"
	@echo "Push completo. Remote URL limpo."

# Supabase
# Este worktree tem stack local propria? (criada por `make db-local`)
WT_LOCAL := $(wildcard .supabase-wt/supabase/config.toml)

db-push:
ifeq ($(WT_LOCAL),)
	@echo "→ REMOTO (projecto ligado)"
	@if [ -z "$$SUPABASE_ACCESS_TOKEN" ] && [ -f .env ]; then \
		export $$(cat .env | grep -v '^#' | xargs) && npx supabase db push --include-all; \
	else \
		npx supabase db push --include-all; \
	fi
else
	@echo "→ LOCAL (.supabase-wt)"
	@npx supabase migration up --local --workdir .supabase-wt
endif

# `cmd > ficheiro` TRUNCA o ficheiro antes de o comando correr: se ele falha, ficamos com
# types.ts vazio e um diff de -2529 linhas. Aconteceu aqui hoje. Escreve-se para temporario
# e so' se move se houve saida — um ficheiro de tipos vazio compila a nada e o erro aparece
# 50 ficheiros a' frente, longe da causa.
define gen_types
	tmp=$$(mktemp); \
	if $(1) > "$$tmp" && [ -s "$$tmp" ]; then \
		mv "$$tmp" src/integrations/supabase/types.ts; \
		echo "✓ tipos regenerados ($$(wc -l < src/integrations/supabase/types.ts | tr -d ' ') linhas)"; \
	else \
		rm -f "$$tmp"; \
		echo "✗ geracao de tipos falhou — types.ts NAO foi tocado"; \
		exit 1; \
	fi
endef

# GOTCHA medido 2026-09-24: gerar do LOCAL produz tipos de schema IDENTICOS aos do remoto
# — excepto o bloco __InternalSupabase.PostgrestVersion, que e' metadado da versao do
# PostgREST e difere entre a stack local e a hospedada. Nao commitar types.ts gerado do
# local: o bloco desaparecia para toda a gente. Gera-se do local para VERIFICAR; commita-se
# o do remoto.
db-types:
ifeq ($(WT_LOCAL),)
	@echo "→ tipos a partir do REMOTO"
	@if [ -z "$$SUPABASE_ACCESS_TOKEN" ] && [ -f .env ]; then \
		export $$(cat .env | grep -v '^#' | xargs); \
	fi; \
	$(call gen_types,npx supabase gen types typescript --linked)
else
	@echo "→ tipos a partir do LOCAL"
	@$(call gen_types,npx supabase gen types typescript --local --workdir .supabase-wt)
endif

# scripts/db-reset.ts TRUNCA tabelas e apaga auth users no que quer que o
# VITE_SUPABASE_URL aponte. Ate' hoje isso era sempre a Supabase hospedada, a partir de
# qualquer um dos worktrees. O travao abaixo nao e' paranoia: e' a diferenca entre um
# engano e uma base de dados vazia. Quem quiser mesmo fazer reset ao remoto tem de o
# dizer por extenso, e o comando nao o diz por ele.
db-reset:
	@set -a; [ -f .env ] && . ./.env; set +a; \
	case "$$VITE_SUPABASE_URL" in \
	  *localhost*|*127.0.0.1*) \
	    echo "Reset completo (LOCAL: $$VITE_SUPABASE_URL)" ;; \
	  *) \
	    if [ "$$FORCE_REMOTE_RESET" != "1" ]; then \
	      echo ""; \
	      echo "  RECUSADO — o alvo nao e' local:"; \
	      echo "    $$VITE_SUPABASE_URL"; \
	      echo ""; \
	      echo "  Isto TRUNCA tabelas e apaga auth users. Para uma stack local:"; \
	      echo "    make db-local"; \
	      echo ""; \
	      echo "  Se e' mesmo o remoto que queres esvaziar, di-lo por extenso:"; \
	      echo "    FORCE_REMOTE_RESET=1 make db-reset"; \
	      echo ""; \
	      exit 1; \
	    fi; \
	    echo "Reset completo (REMOTO, forcado: $$VITE_SUPABASE_URL)" ;; \
	esac; \
	npx tsx scripts/db-reset.ts

# Limpeza
clean:
	rm -rf dist node_modules/.cache coverage

# Ajuda
help:
	@echo "Comandos disponíveis:"
	@echo ""
	@echo "  make dev            - Iniciar servidor de desenvolvimento"
	@echo "  make build          - Build de produção"
	@echo "  make test           - Rodar testes unitários"
	@echo "  make test-watch     - Testes em modo watch"
	@echo "  make test-coverage  - Relatório de cobertura"
	@echo "  make test-e2e       - Rodar testes E2E (pricing)"
	@echo "  make lint           - Verificar linting"
	@echo "  make lint-fix       - Corrigir linting automaticamente"
	@echo "  make deploy         - Build + commit + push"
	@echo "  make push-ci        - Push com token CI (para workflows)"
	@echo "  make db-push        - Aplicar migrações Supabase"
	@echo "  make db-types       - Regenerar tipos TypeScript"
	@echo "  make db-reset       - Reset completo (recusa alvo remoto sem FORCE_REMOTE_RESET=1)"
	@echo "  make db-local       - Levantar stack Supabase local deste worktree"
	@echo "  make db-local-stop  - Parar essa stack e largar os volumes"
	@echo "  make clean          - Limpar cache e builds"

db-local:
	@bash scripts/workflow/supabase-worktree.sh provision

db-local-stop:
	@bash scripts/workflow/supabase-worktree.sh teardown
