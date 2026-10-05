#!/usr/bin/env bash
# Behavioral test suite for try-clone
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRY_CLONE="${REPO_ROOT}/try-clone"

CLEANUP_DIRS=()
cleanup() {
  for dir in "${CLEANUP_DIRS[@]}"; do
    rm -rf "$dir"
  done
}
trap cleanup EXIT

make_temp_dir() {
  local dir
  dir="$(mktemp -d)"
  CLEANUP_DIRS+=("$dir")
  printf '%s' "$dir"
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="${3:-}"

  if [[ "$expected" != "$actual" ]]; then
    printf 'Assertion failed: expected "%s", got "%s" (%s)\n' "$expected" "$actual" "$message" >&2
    exit 1
  fi
}

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

test_missing_gh() {
  printf 'Testing missing gh check...\n'
  local temp_dir
  temp_dir="$(make_temp_dir)"
  ln -s "$(command -v bash)" "${temp_dir}/bash"

  local err_output
  err_output="$(PATH="$temp_dir" "${TRY_CLONE}" 2>&1 || true)"
  assert_contains "$err_output" "Missing gh." "Should fail when gh is not on PATH"
}

test_missing_try() {
  printf 'Testing missing try check...\n'
  local temp_dir
  temp_dir="$(make_temp_dir)"
  ln -s "$(command -v bash)" "${temp_dir}/bash"

  # Mock gh so need gh succeeds
  cat << 'EOF' > "${temp_dir}/gh"
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${temp_dir}/gh"

  local err_output
  err_output="$(PATH="${temp_dir}" "${TRY_CLONE}" 2>&1 || true)"
  assert_contains "$err_output" "Missing try." "Should fail when try is not on PATH"
}

test_gh_not_logged_in() {
  printf 'Testing gh not logged in check...\n'
  local temp_dir
  temp_dir="$(make_temp_dir)"

  cat << 'EOF' > "${temp_dir}/gh"
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then
  exit 1
fi
exit 0
EOF
  chmod +x "${temp_dir}/gh"

  cat << 'EOF' > "${temp_dir}/try"
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${temp_dir}/try"

  local err_output
  err_output="$(PATH="${temp_dir}:/usr/bin:/bin" "${TRY_CLONE}" 2>&1 || true)"
  assert_contains "$err_output" "gh is not logged in. Run: gh auth login" "Should fail when gh auth status fails"
}

test_slug_logic() {
  printf 'Testing slug generation logic...\n'
  local slug_func
  slug_func="$(sed -n '/slug_for() {/,/^}/p' "${TRY_CLONE}")"
  eval "$slug_func"

  local slug1 slug2
  slug1="$(slug_for "robert-flo/try-clone" "false")"
  assert_equals "robert-flo-try-clone" "$slug1" "Standard repo slug"

  slug2="$(slug_for "25asab015-forks/my-repo" "true")"
  assert_equals "fork-25asab015-forks-my-repo" "$slug2" "Fork repo slug"
}

test_e2e_clone_and_skip() {
  printf 'Testing end-to-end mock clone and skip...\n'
  local temp_dir mock_bin try_path
  temp_dir="$(make_temp_dir)"

  mock_bin="${temp_dir}/bin"
  try_path="${temp_dir}/tries"
  mkdir -p "$mock_bin" "$try_path"

  cat << 'EOF' > "${mock_bin}/gh"
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then
  exit 0
fi
if [[ "$1" == "repo" && "$2" == "list" ]]; then
  owner="$3"
  if [[ "$owner" == "robert-flo" ]]; then
    printf 'robert-flo/repo-a\tfalse\tfalse\n'
    printf 'robert-flo/repo-b\ttrue\tfalse\n'
  fi
  exit 0
fi
exit 0
EOF
  chmod +x "${mock_bin}/gh"

  cat << 'EOF' > "${mock_bin}/try"
#!/usr/bin/env bash
if [[ "$1" == "init" ]]; then
  cat <<'INNER'
try() {
  if [[ "$1" == "clone" ]]; then
    local uri="$2"
    local slug="$3"
    mkdir -p "${TRY_PATH}/${slug}/.git"
    return 0
  fi
}
INNER
  exit 0
fi
exit 0
EOF
  chmod +x "${mock_bin}/try"

  # First run: should clone both repos
  local output1
  output1="$(TRY_PATH="$try_path" PATH="${mock_bin}:/usr/bin:/bin" "${TRY_CLONE}")"
  assert_contains "$output1" "TRY   robert-flo/repo-a" "Should clone repo-a"
  assert_contains "$output1" "TRY   robert-flo/repo-b" "Should clone repo-b"
  assert_contains "$output1" "Done. listed=2 cloned=2 skipped=0 failed=0" "Summary of first run"

  # Verify directories created
  if [[ ! -d "${try_path}/robert-flo-repo-a/.git" ]]; then
    printf 'Expected .git directory for repo-a was not created\n' >&2
    exit 1
  fi
  if [[ ! -d "${try_path}/fork-robert-flo-repo-b/.git" ]]; then
    printf 'Expected .git directory for fork-repo-b was not created\n' >&2
    exit 1
  fi

  # Second run: should skip both repos because .git exists
  local output2
  output2="$(TRY_PATH="$try_path" PATH="${mock_bin}:/usr/bin:/bin" "${TRY_CLONE}")"
  assert_contains "$output2" "SKIP  robert-flo/repo-a" "Should skip repo-a on rerun"
  assert_contains "$output2" "SKIP  robert-flo/repo-b" "Should skip repo-b on rerun"
  assert_contains "$output2" "Done. listed=2 cloned=0 skipped=2 failed=0" "Summary of second run"
}

main() {
  test_missing_gh
  test_missing_try
  test_gh_not_logged_in
  test_slug_logic
  test_e2e_clone_and_skip
  printf 'All try-clone behavioral tests passed!\n'
}

main "$@"
