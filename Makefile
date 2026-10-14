.DEFAULT_GOAL := help
.PHONY: help require-svc db-up db-down db-reset db-psql \
	migrate-create migrate-up migrate-down migrate-status migrate-redo migrate-validate

help: ## Show available targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-18s %s\n", $$1, $$2}'
	@echo ""
	@echo "  Targets that act on one service need SVC, e.g. make migrate-up SVC=catalog"

require-svc:
	@test -n "$(SVC)" || (echo "SVC is required, e.g. make $(MAKECMDGOALS) SVC=catalog"; exit 1)

# --- Local database ---------------------------------------------------------

db-up: ## Start local Postgres
	docker compose up -d

db-down: ## Stop local Postgres (keeps data)
	docker compose down

db-reset: ## Delete local Postgres data and re-run init scripts
	docker compose down -v
	docker compose up -d

db-psql: require-svc ## Open psql as superuser on the SVC database
	docker exec -it -e PGOPTIONS="-c search_path=$(SVC)" localdb psql -U user -d $(SVC)

# --- Migrations (goose via mise task <SVC>:migrate) -------------------------

migrate-create: require-svc ## Create a SQL migration, e.g. make migrate-create SVC=catalog NAME=create_venues
	@test -n "$(NAME)" || (echo "usage: make migrate-create SVC=$(SVC) NAME=<snake_case_name>"; exit 1)
	mise run $(SVC):migrate create -s $(NAME) sql

migrate-up: require-svc ## Apply all pending migrations
	mise run $(SVC):migrate up

migrate-down: require-svc ## Roll back the latest migration
	mise run $(SVC):migrate down

migrate-status: require-svc ## Show applied and pending migrations
	mise run $(SVC):migrate status

migrate-redo: require-svc ## Roll back and re-apply the latest migration (unmerged files only)
	mise run $(SVC):migrate redo

migrate-validate: require-svc ## Check migration files without connecting to the database
	mise run $(SVC):migrate validate
