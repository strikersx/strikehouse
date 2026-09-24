# StrikeHouse - Makefile
# Comandos comuns para desenvolvimento

.PHONY: dev build test test-e2e lint push-ci clean help db-reset

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
db-push:
	@if [ -z "$$SUPABASE_ACCESS_TOKEN" ] && [ -f .env ]; then \
		export $$(cat .env | grep -v '^#' | xargs) && npx supabase db push --include-all; \
	else \
		npx supabase db push --include-all; \
	fi

db-types:
	@if [ -z "$$SUPABASE_ACCESS_TOKEN" ] && [ -f .env ]; then \
		export $$(cat .env | grep -v '^#' | xargs) && npx supabase gen types typescript --linked > src/integrations/supabase/types.ts; \
	else \
		npx supabase gen types typescript --linked > src/integrations/supabase/types.ts; \
	fi

db-reset:
	@echo "Reset completo: limpa dados + recria test users"
	@if [ -z "$$SUPABASE_ACCESS_TOKEN" ] && [ -f .env ]; then \
		export $$(cat .env | grep -v '^#' | xargs) && npx tsx scripts/db-reset.ts; \
	else \
		npx tsx scripts/db-reset.ts; \
	fi

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
	@echo "  make db-reset       - Reset completo (migrations + seed com test users)"
	@echo "  make clean          - Limpar cache e builds"

db-local:
	@bash scripts/workflow/supabase-worktree.sh provision

db-local-stop:
	@bash scripts/workflow/supabase-worktree.sh teardown
