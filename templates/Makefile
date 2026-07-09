.PHONY: help setup test lint check run-check review

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

run-check: ## Confirm the app still runs (keep this current as the app evolves)
	PYTHONPATH={{code-dir}} uv run python -c "import {{package_name}}"
# Once the app has a real entry point, replace the import check above with a
# real run that exits non-zero on failure and finishes in under 30 seconds,
# without external services or credentials:
#   CLI:    uv run {{project-name}} --help   (or a --dry-run invocation)
#   Server: start it, probe the health endpoint, tear it down — e.g.
#           uv run python -m {{package_name}} & pid=$$!; sleep 2; \
#           curl -fsS localhost:8080/healthz; rc=$$?; kill $$pid; exit $$rc

review: ## Run the two-pass agentic code review (also runs on git push)
	bash scripts/code-review.sh

# deploy: ## Deploy to GCP
# 	terraform -chdir=infra apply
# 	gcloud run deploy {{project-name}} --region us-central1
