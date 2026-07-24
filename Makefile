.DEFAULT_GOAL := help
.PHONY: help up down logs ps test lint build monitoring-up monitoring-down tf-init tf-plan clean

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

up: ## Build and start all services in the background
	docker compose up --build -d

down: ## Stop and remove services, networks, and volumes
	docker compose down -v

logs: ## Follow logs from all services
	docker compose logs -f

ps: ## List running services
	docker compose ps

test: ## Install API dependencies and run the API test suite
	cd api && npm ci && npm test

lint: ## Run lint checks in api and frontend
	cd api && npm run lint
	cd frontend && npm run lint

build: ## Build all service images without starting them
	docker compose build

monitoring-up: ## Start the monitoring profile services
	docker compose --profile monitoring up -d

monitoring-down: ## Stop the monitoring profile services
	docker compose --profile monitoring down

tf-init: ## Initialize Terraform in infra/terraform
	cd infra/terraform && terraform init

tf-plan: ## Show the Terraform plan for the dev environment
	cd infra/terraform && terraform plan -var-file="environments/dev.tfvars"

clean: ## Remove local build artifacts and dependency caches
	rm -rf api/node_modules api/coverage frontend/node_modules frontend/dist
