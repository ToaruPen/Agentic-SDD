#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }
die() { eprint "[CI] ERROR: $*"; exit 1; }

run_cmd() {
  local name="$1"
  local cmd="$2"

  eprint "[CI] $name: $cmd"
  bash -lc "$cmd"
}

test_cmd="${AGENTIC_SDD_CI_TEST_CMD:-}"
lint_cmd="${AGENTIC_SDD_CI_LINT_CMD:-}"
typecheck_cmd="${AGENTIC_SDD_CI_TYPECHECK_CMD:-}"
docs_cmd="${AGENTIC_SDD_CI_DOCS_CMD:-}"

# Recommended: configure tests with coverage output/threshold and use strict typecheck mode.

missing=()
[[ -n "$test_cmd" ]] || missing+=("AGENTIC_SDD_CI_TEST_CMD")
[[ -n "$lint_cmd" ]] || missing+=("AGENTIC_SDD_CI_LINT_CMD")
[[ -n "$typecheck_cmd" ]] || missing+=("AGENTIC_SDD_CI_TYPECHECK_CMD")

if [[ "${#missing[@]}" -gt 0 ]]; then
  eprint "[CI] Missing CI command configuration: ${missing[*]}"
  eprint ""
  eprint "This template is language/framework-agnostic."
  eprint "Set the following env vars in your workflow (.github/workflows/agentic-sdd-ci.yml):"
  eprint ""
  eprint "  AGENTIC_SDD_CI_TEST_CMD"
  eprint "  AGENTIC_SDD_CI_LINT_CMD"
  eprint "  AGENTIC_SDD_CI_TYPECHECK_CMD"
  eprint ""
  eprint "Example (Node.js):"
  eprint "  AGENTIC_SDD_CI_TEST_CMD=\"npm run test:coverage\""
  eprint "  AGENTIC_SDD_CI_LINT_CMD=\"npm run lint\""
  eprint "  AGENTIC_SDD_CI_TYPECHECK_CMD=\"tsc --noEmit --strict\""
  eprint ""
  eprint "Example (Python):"
  eprint "  AGENTIC_SDD_CI_TEST_CMD=\"pytest -q --cov=. --cov-report=term-missing --cov-fail-under=80\""
  eprint "  AGENTIC_SDD_CI_LINT_CMD=\"ruff check .\""
  eprint "  AGENTIC_SDD_CI_TYPECHECK_CMD=\"mypy --strict .\""
  exit 1
fi

run_cmd "tests" "$test_cmd"
run_cmd "lint" "$lint_cmd"
run_cmd "typecheck" "$typecheck_cmd"

if [[ -n "$docs_cmd" ]]; then
  run_cmd "docs" "$docs_cmd"
fi

eprint "[CI] OK"
