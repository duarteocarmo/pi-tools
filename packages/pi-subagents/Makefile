default: help

.PHONY: help
help: # Show help for each Makefile command.
	@grep -E '^[a-zA-Z0-9 -]+:.*#' Makefile | sort | while read -r line; do printf "\033[1;32m$$(echo $$line | cut -f 1 -d':')\033[00m:$$(echo $$line | cut -f 2- -d'#')\n"; done

.PHONY: format
format: # Format files with Biome
	bunx biome format --write .

.PHONY: lint
lint: # Lint files with Biome
	bunx biome lint --error-on-warnings .
