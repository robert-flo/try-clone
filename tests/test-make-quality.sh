#!/usr/bin/env bash
# Behavioral test suite for repository Makefile quality targets
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF_TEST="tests/test-make-quality.sh"

assert_contains() {
  local output="$1"
  local expected="$2"
  local message="${3:-}"

  if [[ "$output" != *"$expected"* ]]; then
    printf 'Assertion failed: output does not contain "%s" (%s)\n' "$expected" "$message" >&2
    printf 'Actual output:\n%s\n' "$output" >&2
    exit 1
  fi
}

test_make_help() {
  printf 'Testing make help output...\n'
  local help_output
  help_output="$(make -C "$REPO_ROOT" help)"

  assert_contains "$help_output" "format" "make help lists format target"
  assert_contains "$help_output" "lint" "make help lists lint target"
  assert_contains "$help_output" "test" "make help lists test target"
  assert_contains "$help_output" "verify" "make help lists verify target"
}

test_make_lint() {
  printf 'Testing make lint passes cleanly...\n'
  make -C "$REPO_ROOT" lint > /dev/null
}

test_non_mutating_verify() {
  printf 'Testing that make verify does not modify files...\n'
  # Run make verify excluding this self-test to prevent recursion
  make -C "$REPO_ROOT" verify TEST_EXCLUDE="$SELF_TEST" > /dev/null
}

main() {
  test_make_help
  test_make_lint
  test_non_mutating_verify
  printf 'All make quality tests passed!\n'
}

main "$@"
