.PHONY: help setup test lint check

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'

setup: ## One-time post-clone setup (uv sync, pre-commit)
	uv sync
	uv run pre-commit install

test: ## Run tests
	uv run pytest

lint: ## Run all pre-commit hooks
	uv run pre-commit run --all-files

check: ## Lint + type check
	uv run ruff check .
	uv run ty check

# deploy: ## Deploy to GCP
# 	terraform -chdir=infra apply
# 	gcloud run deploy {{project-name}} --region us-central1
