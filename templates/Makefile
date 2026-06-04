.PHONY: help setup test lint check

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'

setup: ## One-time post-clone setup (uv sync, pre-commit, skills)
	uv sync
	uv run pre-commit install
	@git clone --depth 1 https://github.com/blader/humanizer .claude/skills/humanizer 2>/dev/null || true

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
