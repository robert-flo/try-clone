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

test_default_try_path() {
  printf "Testing default TRY_PATH is \$HOME/Work/tries...\n"
  local detected_try_path
  detected_try_path="$(HOME="/custom/home" bash -c '
    unset TRY_PATH
    source <(grep -E "^TRY_PATH=" "'"${TRY_CLONE}"'")
    printf "%s" "$TRY_PATH"
  ')"
  assert_equals "/custom/home/Work/tries" "$detected_try_path" "Default TRY_PATH should be \$HOME/Work/tries"
}

test_slug_logic() {
  printf 'Testing canonical slug generation logic...\n'
  local slug_func
  slug_func="$(sed -n '/slug_for() {/,/^}/p' "${TRY_CLONE}")"
  eval "$slug_func"

  local slug1 slug2 slug3 slug4
  slug1="$(slug_for "robert-flo/try-clone" "false")"
  assert_equals "rf-try-clone" "$slug1" "Non-fork repo uses rf- prefix"

  slug2="$(slug_for "25asab015-forks/my-repo" "true")"
  assert_equals "fo-my-repo" "$slug2" "Fork repo uses fo- prefix"

  slug3="$(slug_for "robert-flo/omarchy" "true")"
  assert_equals "fo-omarchy" "$slug3" "Forked omarchy repo uses fo- prefix"

  slug4="$(slug_for "robert-flo/omarchy-personal-repo" "false")"
  assert_equals "rf-omarchy-personal-repo" "$slug4" "Non-fork omarchy-personal-repo uses rf- prefix"
}

test_load_projects_config() {
  printf 'Testing load_projects_config parsing...\n'
  local temp_dir config_file
  temp_dir="$(make_temp_dir)"
  config_file="${temp_dir}/projects.conf"

  cat << 'EOF' > "$config_file"
# Projects test config
  # Empty lines and comments should be ignored

pj-omarchy = omarchy, omarchy-pkgs, robert-flo/scratchpad
pj-fleet = skills, ceo, sura
EOF

  declare -A PROJECT_MAP=()
  local parse_code
  parse_code="$(sed -n '/load_projects_config() {/,/^}/p' "${TRY_CLONE}")"
  eval "$parse_code"
  load_projects_config "$config_file"

  assert_equals "pj-omarchy" "${PROJECT_MAP["omarchy"]:-}" "omarchy mapped to pj-omarchy"
  assert_equals "pj-omarchy" "${PROJECT_MAP["omarchy-pkgs"]:-}" "omarchy-pkgs mapped to pj-omarchy"
  assert_equals "pj-omarchy" "${PROJECT_MAP["scratchpad"]:-}" "scratchpad mapped to pj-omarchy"
  assert_equals "pj-fleet" "${PROJECT_MAP["skills"]:-}" "skills mapped to pj-fleet"
  assert_equals "pj-fleet" "${PROJECT_MAP["ceo"]:-}" "ceo mapped to pj-fleet"
  assert_equals "pj-fleet" "${PROJECT_MAP["sura"]:-}" "sura mapped to pj-fleet"
  assert_equals "" "${PROJECT_MAP["try-clone"]:-}" "unassigned repo is empty"
}

test_default_projects_config_fallback() {
  printf 'Testing fallback to default projects.conf...\n'
  local temp_dir detected_project
  temp_dir="$(make_temp_dir)"
  detected_project="$(
    HOME="$temp_dir" bash -c '
      unset TRY_CLONE_CONFIG
      declare -A PROJECT_MAP=()
      source <(sed -n "/load_projects_config() {/,/^}/p; /init_projects_config() {/,/^}/p" "'"${TRY_CLONE}"'")
      SCRIPT_DIR="'"${REPO_ROOT}"'"
      init_projects_config
      printf "%s" "${PROJECT_MAP["omarchy"]:-}"
    '
  )"
  assert_equals "pj-omarchy" "$detected_project" "Default config should resolve omarchy to pj-omarchy"
}

test_resolve_rel_path() {
  printf 'Testing resolve_rel_path...\n'
  declare -A PROJECT_MAP=()
  local funcs
  funcs="$(sed -n '/slug_for() {/,/^}/p; /project_for() {/,/^}/p; /resolve_rel_path() {/,/^}/p' "${TRY_CLONE}")"
  eval "$funcs"

  # Populate dummy PROJECT_MAP
  PROJECT_MAP["omarchy"]="pj-omarchy"
  PROJECT_MAP["skills"]="pj-fleet"

  local path1 path2 path3
  path1="$(resolve_rel_path "robert-flo/omarchy" "true")"
  assert_equals "pj-omarchy/fo-omarchy" "$path1" "Fork in pj-omarchy"

  path2="$(resolve_rel_path "robert-flo/skills" "true")"
  assert_equals "pj-fleet/fo-skills" "$path2" "Fork in pj-fleet"

  path3="$(resolve_rel_path "robert-flo/try-clone" "false")"
  assert_equals "rf-try-clone" "$path3" "Root non-fork repo"
}

test_e2e_clone_and_skip() {
  printf 'Testing end-to-end mock clone and skip...\n'
  local temp_dir mock_bin try_path config_file
  temp_dir="$(make_temp_dir)"

  mock_bin="${temp_dir}/bin"
  try_path="${temp_dir}/tries"
  config_file="${temp_dir}/projects.conf"
  mkdir -p "$mock_bin" "$try_path"

  cat << 'EOF' > "$config_file"
pj-sample=repo-b
EOF

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
    mkdir -p "${TRY_PATH}/${slug}"
    git -C "${TRY_PATH}/${slug}" init -b master > /dev/null 2>&1
    git -C "${TRY_PATH}/${slug}" config user.email "test@example.com"
    git -C "${TRY_PATH}/${slug}" config user.name "Test Runner"
    touch "${TRY_PATH}/${slug}/init"
    git -C "${TRY_PATH}/${slug}" add init
    git -C "${TRY_PATH}/${slug}" commit -m "init" > /dev/null 2>&1
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
  output1="$(TRY_CLONE_CONFIG="$config_file" TRY_PATH="$try_path" PATH="${mock_bin}:/usr/bin:/bin" "${TRY_CLONE}")"
  assert_contains "$output1" "TRY   robert-flo/repo-a" "Should clone repo-a"
  assert_contains "$output1" "TRY   robert-flo/repo-b" "Should clone repo-b"
  assert_contains "$output1" "Done. listed=2 cloned=2 synced=0 skipped=0 failed=0" "Summary of first run"

  # Verify directories created
  if [[ ! -d "${try_path}/rf-repo-a/.git" ]]; then
    printf 'Expected .git directory for repo-a (rf-repo-a) was not created\n' >&2
    exit 1
  fi
  if [[ ! -d "${try_path}/pj-sample/fo-repo-b/.git" ]]; then
    printf 'Expected .git directory for pj-sample/fo-repo-b was not created\n' >&2
    exit 1
  fi

  # Second run: should sync both repos because .git exists and trees are clean
  local output2
  output2="$(TRY_CLONE_CONFIG="$config_file" TRY_PATH="$try_path" PATH="${mock_bin}:/usr/bin:/bin" "${TRY_CLONE}")"
  assert_contains "$output2" "SYNC  robert-flo/repo-a" "Should sync repo-a on rerun"
  assert_contains "$output2" "SYNC  robert-flo/repo-b" "Should sync repo-b on rerun"
  assert_contains "$output2" "Done. listed=2 cloned=0 synced=2 skipped=0 failed=0" "Summary of second run"
}

test_tree_preview() {
  printf 'Testing terminal tree preview...\n'
  local temp_dir mock_bin try_path config_file
  temp_dir="$(make_temp_dir)"

  mock_bin="${temp_dir}/bin"
  try_path="${temp_dir}/tries"
  config_file="${temp_dir}/projects.conf"
  mkdir -p "$mock_bin" "$try_path"

  cat << 'EOF' > "$config_file"
pj-demo=repo-b
EOF

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
  return 0
}
INNER
  exit 0
fi
exit 0
EOF
  chmod +x "${mock_bin}/try"

  local output
  output="$(TRY_CLONE_CONFIG="$config_file" TRY_PATH="$try_path" PATH="${mock_bin}:/usr/bin:/bin" "${TRY_CLONE}")"

  assert_contains "$output" "--- pj-demo" "Tree header for pj-demo"
  assert_contains "$output" "      fo-repo-b" "Indented repo fo-repo-b under pj-demo"
  assert_contains "$output" "--- [raíz]" "Tree header for root repos"
  assert_contains "$output" "      rf-repo-a" "Indented repo rf-repo-a under root"

  # Ensure preview appears before operations
  local tree_pos first_op_pos
  tree_pos="${output%%--- pj-demo*}"
  first_op_pos="${output%%TRY   *}"
  if ((${#tree_pos} >= ${#first_op_pos})); then
    printf 'Assertion failed: tree preview must appear before clone/sync operations\n' >&2
    exit 1
  fi
}

test_sync_clean_and_dirty_repos() {
  printf 'Testing existing repo synchronization and dirty working tree protection...\n'
  local temp_dir mock_bin try_path clean_repo dirty_repo
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
    printf 'robert-flo/repo-clean\tfalse\tfalse\n'
    printf 'robert-flo/repo-dirty\tfalse\tfalse\n'
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
  return 0
}
INNER
  exit 0
fi
exit 0
EOF
  chmod +x "${mock_bin}/try"

  # Initialize repo-clean
  clean_repo="${try_path}/rf-repo-clean"
  mkdir -p "$clean_repo"
  git -C "$clean_repo" init -b main > /dev/null 2>&1
  git -C "$clean_repo" config user.email "test@example.com"
  git -C "$clean_repo" config user.name "Test Runner"
  echo "init" > "${clean_repo}/file.txt"
  git -C "$clean_repo" add file.txt
  git -C "$clean_repo" commit -m "initial commit" > /dev/null 2>&1
  git -C "$clean_repo" branch -m master
  # Add remote upstream
  git -C "$clean_repo" remote add upstream "${temp_dir}"
  # Switch to another branch
  git -C "$clean_repo" checkout -b feature > /dev/null 2>&1

  # Initialize repo-dirty
  dirty_repo="${try_path}/rf-repo-dirty"
  mkdir -p "$dirty_repo"
  git -C "$dirty_repo" init -b main > /dev/null 2>&1
  git -C "$dirty_repo" config user.email "test@example.com"
  git -C "$dirty_repo" config user.name "Test Runner"
  echo "init" > "${dirty_repo}/file.txt"
  git -C "$dirty_repo" add file.txt
  git -C "$dirty_repo" commit -m "initial commit" > /dev/null 2>&1
  git -C "$dirty_repo" branch -m master
  git -C "$dirty_repo" checkout -b work > /dev/null 2>&1
  # Dirty uncommitted changes
  echo "dirty modification" >> "${dirty_repo}/file.txt"

  local output err_output
  output="$(TRY_PATH="$try_path" PATH="${mock_bin}:/usr/bin:/bin" "${TRY_CLONE}" 2> "${temp_dir}/stderr.log")"
  err_output="$(cat "${temp_dir}/stderr.log")"

  # Clean repo assertions
  local upstream_skip
  upstream_skip="$(git -C "$clean_repo" config remote.upstream.skipFetchAll || true)"
  assert_equals "true" "$upstream_skip" "remote.upstream.skipFetchAll should be set to true on clean repo"

  local clean_current_branch
  clean_current_branch="$(git -C "$clean_repo" branch --show-current)"
  assert_equals "master" "$clean_current_branch" "Clean repo should be checked out to base branch master"
  assert_contains "$output" "SYNC  robert-flo/repo-clean" "Should report SYNC for clean repo"

  # Dirty repo assertions
  local dirty_current_branch
  dirty_current_branch="$(git -C "$dirty_repo" branch --show-current)"
  assert_equals "work" "$dirty_current_branch" "Dirty repo should remain on its active branch work"
  assert_contains "$err_output" "WARN  robert-flo/repo-dirty" "Should emit warning on stderr for dirty working tree"
  assert_contains "$output" "SKIP  robert-flo/repo-dirty" "Should report SKIP for dirty repo"

  # Summary assertion
  assert_contains "$output" "Done. listed=2 cloned=0 synced=1 skipped=1 failed=0" "Execution summary includes synced and skipped"
}

main() {
  test_missing_gh
  test_missing_try
  test_gh_not_logged_in
  test_default_try_path
  test_slug_logic
  test_load_projects_config
  test_default_projects_config_fallback
  test_resolve_rel_path
  test_tree_preview
  test_sync_clean_and_dirty_repos
  test_e2e_clone_and_skip
  printf 'All try-clone behavioral tests passed!\n'
}

main "$@"
