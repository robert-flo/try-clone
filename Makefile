.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash

TEST_EXCLUDE ?=

# Collect all shell scripts: try-clone and tests/*.sh
SHELL_FILES := try-clone $(wildcard tests/*.sh)

.PHONY: help format lint test verify

help: ## Show repository lifecycle targets
	@printf "Usage: make [target]\n\n"
	@printf "Targets:\n"
	@printf "  help     Show repository lifecycle targets\n"
	@printf "  format   Apply repository formatting rules (shfmt); may modify files\n"
	@printf "  lint     Audit shell scripts with shellcheck and shfmt; does not modify files\n"
	@printf "  test     Run repository behavior tests in tests/; does not modify files\n"
	@printf "  verify   Run lint and test; does not modify files\n"

format: ## Apply repository formatting rules; may modify files
	@printf "==> Formatting shell files with shfmt...\n"
	@shfmt -i 2 -sr -kp -ci -w $(SHELL_FILES)
	@printf "✓ Formatting complete.\n"

lint: ## Check shell scripts without modifying files
	@printf "==> Auditing shell scripts with shellcheck...\n"
	@shellcheck $(SHELL_FILES)
	@printf "==> Checking shell script formatting with shfmt...\n"
	@shfmt -i 2 -sr -kp -ci -d $(SHELL_FILES)
	@printf "==> Validating bash syntax...\n"
	@for file in $(SHELL_FILES); do \
		bash -n "$$file" || exit 1; \
	done
	@printf "✓ Lint passed.\n"

test: ## Run repository behavior tests without modifying files
	@printf "==> Running behavior tests...\n"
	@set -euo pipefail; \
	for test_script in tests/*.sh; do \
		[[ -e "$$test_script" ]] || continue; \
		skip=0; \
		for excluded in $(TEST_EXCLUDE); do \
			if [[ "$$test_script" == "$$excluded" ]]; then \
				skip=1; \
				break; \
			fi; \
		done; \
		if (( skip == 1 )); then \
			continue; \
		fi; \
		printf "Running %s...\n" "$$test_script"; \
		bash "$$test_script"; \
	done
	@printf "✓ All tests passed.\n"

verify: lint test ## Run all non-mutating quality checks
	@printf "✓ Full verification passed.\n"
