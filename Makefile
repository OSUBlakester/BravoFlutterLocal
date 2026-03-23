# Bravo AAC Flutter Environment Management
# Usage: make [command]

.PHONY: help env-dev env-test env-prod status build-dev-web build-test-web build-prod-web run clean

# Default target
help:
	@echo "🎯 Bravo AAC Flutter Environment Commands"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Environment Management:"
	@echo "  make env-dev      - Switch to development environment"
	@echo "  make env-test     - Switch to test environment" 
	@echo "  make env-prod     - Switch to production environment"
	@echo "  make status       - Show current environment status"
	@echo ""
	@echo "Building:"
	@echo "  make build-dev-web    - Build dev for web"
	@echo "  make build-test-web   - Build test for web"
	@echo "  make build-prod-web   - Build prod for web"
	@echo ""
	@echo "iPad Deployment:"
	@echo "  make deploy-dev-ipad  - Deploy dev to iPad"
	@echo "  make deploy-test-ipad - Deploy test to iPad"
	@echo "  make deploy-prod-ipad - Deploy prod to iPad"
	@echo ""
	@echo "Development:"
	@echo "  make run          - Run with current environment"
	@echo "  make clean        - Clean Flutter build cache"
	@echo ""
	@echo "Quick Workflows:"
	@echo "  make dev-run      - Switch to dev and run"
	@echo "  make test-run     - Switch to test and run"

# Environment switching
env-dev:
	@./scripts/switch_env.sh dev

env-test:
	@./scripts/switch_env.sh test

env-prod:
	@./scripts/switch_env.sh prod

# Show current environment
status:
	@./scripts/show_env.sh

# Building
build-dev-web:
	@./scripts/build_environment.sh dev web

build-test-web:
	@./scripts/build_environment.sh test web

build-prod-web:
	@./scripts/build_environment.sh prod web

# iPad Deployment
deploy-dev-ipad:
	@./scripts/deploy_to_ipad.sh dev

deploy-test-ipad:
	@./scripts/deploy_to_ipad.sh test

deploy-prod-ipad:
	@./scripts/deploy_to_ipad.sh prod

# Development
run:
	@flutter run -d chrome

clean:
	@flutter clean
	@flutter pub get

# Quick workflows
dev-run: env-dev run

test-run: env-test run

prod-run: env-prod run
