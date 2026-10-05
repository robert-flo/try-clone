# AGENTS.md — try-clone

Operational guidelines, conventions, and agent workflow for `robert-flo/try-clone`.

## Table of Contents

1. [Agent Skills](#agent-skills)
2. [Repository Structure & Purpose](#repository-structure--purpose)
3. [Style](#style)
4. [Error Handling](#error-handling)
5. [ShellCheck & Scripting Safety](#shellcheck--scripting-safety)
6. [Verification](#verification)
7. [Git Worktree Workflow (Development)](#git-worktree-workflow-development)
8. [Branching & Integration Policy](#branching--integration-policy)
9. [Task Planning & Skills Workflow (Matt Pocock Skills)](#task-planning--skills-workflow-matt-pocock-skills)
10. [Task Execution Workflow](#task-execution-workflow)

---

## Agent Skills

### Issue Tracker

GitHub Issues via `gh` CLI. See `docs/agents/issue-tracker.md`.
Prefix issue titles with the issue number and a separator: `<number> - <descriptive title>` (for example, `1 - Setup base de agentes, Makefile y pruebas`).

### Triage Labels

Canonical five-role triage vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-to-merge`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain Docs

Single-context repo layout (`GLOSSARY.md` + `docs/adr/` at repo root). See `docs/agents/domain.md`.

---

## Repository Structure & Purpose

`try-clone` is a bash CLI utility that clones GitHub repositories belonging to specified owners into a [`try`](https://github.com/tobi/try) workspace (defaulting to `$HOME/Dropbox/Work/tries` or configurable via `TRY_PATH`).

- `try-clone` — Main executable Bash script.
- `Makefile` — Standard repository lifecycle targets (`help`, `lint`, `test`, `verify`, `format`).
- `tests/` — Automated behavioral and contract test suite running without external network dependencies.
- `docs/agents/` — Configuration for Matt Pocock engineering skills and agent triage:
  - `issue-tracker.md` — GitHub Issues integration via `gh`.
  - `triage-labels.md` — Canonical label vocabulary mapping.
  - `domain.md` — Single-context domain layout and ADR policy.
- `README.md` — User-facing documentation and usage instructions.

---

## Style

- Two spaces for indentation, no tabs.
- Bash 5 conditionals: use `[[ ]]` for string/file tests and `(( ))` for numeric tests.
- In `[[ ]]`, don't quote variables, but do quote string literals when comparing values (e.g. `[[ $is_fork == "true" ]]`).
  > Note: outside `[[ ]]`, always quote variable expansions to prevent word splitting (SC2086).
- Prefer `(( ))` over numeric operators inside `[[ ]]` (e.g., `(( fail > 0 ))`, not `[[ $fail -gt 0 ]]`).
- For strings and paths with spaces, quote them: `"$TRY_PATH/$slug"`.
- Shebang:
  - Use `#!/usr/bin/env bash` consistently.
- Strict error handling:
  - Scripts must start with `set -euo pipefail`.
- **`local` in functions**: every function-scoped variable must be declared with `local`. When the value comes from a command, declare the empty variable first and assign it on a separate line — never `local var=$(cmd)` on a single line, since it masks the command's exit code (SC2155). Correct example:

  ```bash
  local slug=""
  slug=$(slug_for "$full_name" "$is_fork")
  ```

- **Naming**:
  - Variables and functions: `snake_case`.
  - Read-only constants / configuration defaults: `UPPER_SNAKE_CASE` + `readonly`.
  - Functions: prefixed by verb/action (e.g., `slug_for`, `list_repos`, `assert_contains`).

---

## Error Handling

- For scripts with `set -euo pipefail`, protect pipelines or command substitutions in variable assignments that might return a non-zero exit status (such as queries returning empty results) by appending `|| true` or `|| echo ""` to prevent premature termination.
- Fatal errors should terminate execution with a clear diagnostic message printed to `stderr` and a non-zero exit status via a `die` helper:

  ```bash
  die() {
    printf '%s\n' "$*" >&2
    exit 1
  }
  ```

---

## ShellCheck & Scripting Safety

- **Zero-Warning Policy**: All shell scripts must pass `shellcheck` with zero warnings or errors before committing.
- **Formatting Policy**: All shell scripts must conform to `shfmt -i 2 -sr -kp -ci`.
- **Direct Command Checks (SC2181/SC2319)**: Avoid checking `$?` indirectly. Check commands directly (`if try clone "$uri" "$slug"; then`).
- **Quote Variable Expansions (SC2086)**: Always double-quote variable expansions when used as command arguments (`"$TRY_PATH"`).
- **Built-in Parameter Expansion (SC2001)**: Avoid external tools for simple string manipulations; prefer Bash parameter expansions (`${full_name//\//-}`).
- **Localizing Exceptions**: Do not disable warnings file-wide. Use inline `# shellcheck disable=SCxxxx` directives only on the specific line where an unavoidable exception exists.

---

## Verification

The repository enforces quality through `make` targets. All verification targets are deterministic and safe to run in any clone or worktree.

### Quality Targets

| Target        | Command       | Description                                                          | Mutates Files? |
| :------------ | :------------ | :------------------------------------------------------------------- | :------------- |
| `help`        | `make help`   | Displays the catalog of available repository targets.                | No             |
| `format`      | `make format` | Formats all shell files using `shfmt -i 2 -sr -kp -ci -w`.           | **Yes**        |
| `lint`        | `make lint`   | Runs `shellcheck`, `shfmt -d`, and `bash -n` syntax checks.          | No             |
| `test`        | `make test`   | Runs all automated test scripts under `tests/*.sh`.                  | No             |
| **`verify`**  | `make verify` | **Aggregate acceptance gate**: runs `lint` and `test` sequentially.  | No             |

> [!IMPORTANT]
> `make verify` is the non-negotiable acceptance gate before every commit and PR. It must pass cleanly and leave `git status` untouched.

---

## Git Worktree Workflow (Development)

To isolate development tasks, prevent cross-contamination, and preserve a clean main clone:

- **Isolated Development**: All feature and bugfix work is conducted in dedicated worktrees outside the main clone:
  ```bash
  git worktree add ../.wt-rf-try-clone-<number> -b <number>-<slug> master
  ```
- **Never Commit Directly to `master`**: Never develop or commit directly in the base worktree.
- **Cleanup**: After a PR is confirmed merged into `master`, remove the topic branch and delete the worktree:
  ```bash
  git worktree remove ../.wt-rf-try-clone-<number>
  git branch -d <number>-<slug>
  ```

---

## Branching & Integration Policy

- **Integration Branch**: `master` is the default integration branch. Direct pushes to `master` are forbidden; all changes land via Pull Requests.
- **Draft PRs**: Open PRs early in draft mode (`gh pr create --draft`, with `Closes #N`).
- **Rebase Before Merge**: Keep topic branches clean and linear. Rebase onto `origin/master` when needed and push with `--force-with-lease`. Never merge the base into your topic branch.
- **Ready for Review**: Move the PR out of draft (`gh pr ready`) only after:
  1. `make verify` passes cleanly.
  2. `code-review` is clean.
  3. Acceptance criteria proofs and validation steps are added to the PR body.

---

## Task Planning & Skills Workflow (Matt Pocock Skills)

This repository follows [Matt Pocock's engineering skills](https://github.com/mattpocock/skills).

### Task Sizing

1. **Trivial / Administrative Tasks** — configuration files (`.gitignore`), documentation typo fixes, minor script tweaks with unambiguous behavior.
   - **Fast-Track**: skip straight to `/implement`, then close with `/code-review`.
2. **Engineering Tasks** — changes altering CLI behavior, argument parsing, error handling, cloning logic, or testing contracts.
   - **Full Pipeline**: `/grill-with-docs` → `/to-spec` → `/to-tickets` → `/implement` → `/code-review`.

> [!IMPORTANT]
> **Classify out loud**: Always announce the task sizing and path before writing code. If in doubt, default to the Full Pipeline.

### Main Build Chain

```text
/grill-with-docs → /to-spec → /to-tickets → /implement → /code-review
```

### Standard Review Framing

Every `/code-review` run in this repository must use this literal framing:

```text
Review this repository as if you are blocking or approving a production PR.
```

---

## Task Execution Workflow

For every implementation task, execute these phases in sequence:

### Phase 1 — Environment & Task Setup
1. Verify `origin/master` is up to date.
2. Create an isolated worktree under `../.wt-rf-try-clone-<number>`.
3. Switch into the worktree.

### Phase 2 — Implementation & TDD
1. Apply changes adhering to Bash 5 standards, strict variable quoting, and pure helper functions.
2. For bugfixes or new features, write behavioral tests in `tests/` first (`/tdd`).
3. Format all touched shell files with `make format`.

### Phase 3 — Verification
1. Run `make lint` to verify zero warnings from `shellcheck` and clean `shfmt`.
2. Run `make test` to verify all contracts pass.
3. Run `make verify` to ensure the aggregate gate passes without modifying the working tree.

### Phase 4 — Review & Pull Request
1. Run `/code-review` with the mandatory framing. Fix any findings.
2. Commit changes with Conventional Commits.
3. Push to `origin` and open a Pull Request with `Closes #N`.
4. Provide clear manual validation instructions for the reviewer.
