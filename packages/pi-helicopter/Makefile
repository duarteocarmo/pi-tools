.PHONY: help build run test clean

help: ## Show available commands
	@awk 'BEGIN {FS = ":.*## "; printf "Usage: make <command>\n\n"} /^[a-zA-Z_-]+:.*## / {printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build the app bundle
	./build_app.sh

run: build ## Build and open the app
	open "build/Pi Helicopter.app"

test: ## Run the tests
	swift test

clean: ## Remove build files
	rm -rf .build build
