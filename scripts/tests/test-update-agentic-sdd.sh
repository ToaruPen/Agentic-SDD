#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
updater="$repo_root/scripts/update-agentic-sdd.sh"

if [[ ! -x "$updater" ]]; then
  eprint "Missing script or not executable: $updater"
  exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-subtree-update-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

set +e
(cd "$tmpdir" && "$updater" --ref v0.2.39) >/dev/null 2>"$tmpdir/stderr-not-git"
code=$?
set -e
if [[ "$code" -eq 0 ]]; then
  eprint "Expected failure outside a git repository"
  exit 1
fi

repo="$tmpdir/repo"
mkdir -p "$repo"
git -C "$repo" init -q
mkdir -p "$repo/.agentic-sdd-upstream"

repo_no_prefix="$tmpdir/repo-no-prefix"
mkdir -p "$repo_no_prefix"
git -C "$repo_no_prefix" init -q

set +e
(cd "$repo" && "$updater") >/dev/null 2>"$tmpdir/stderr-missing-ref"
code=$?
set -e
if [[ "$code" -ne 1 ]]; then
  eprint "Expected exit code 1 when --ref is missing, got: $code"
  cat "$tmpdir/stderr-missing-ref" >&2
  exit 1
fi

if ! grep -Fq -- "--ref is required" "$tmpdir/stderr-missing-ref"; then
  eprint "Expected missing --ref error message"
  cat "$tmpdir/stderr-missing-ref" >&2
  exit 1
fi

set +e
(cd "$repo_no_prefix" && "$updater" --ref v0.2.39) >/dev/null 2>"$tmpdir/stderr-no-prefix"
code=$?
set -e
if [[ "$code" -eq 0 ]]; then
  eprint "Expected failure when prefix directory does not exist"
  exit 1
fi

if ! grep -Fq "Prefix directory does not exist" "$tmpdir/stderr-no-prefix"; then
  eprint "Expected prefix directory error message"
  cat "$tmpdir/stderr-no-prefix" >&2
  exit 1
fi

set +e
(cd "$repo" && "$updater" --prefix --ref v0.2.39) >/dev/null 2>"$tmpdir/stderr-missing-prefix-value"
code=$?
set -e
if [[ "$code" -ne 1 ]]; then
  eprint "Expected exit code 1 when --prefix value is missing, got: $code"
  cat "$tmpdir/stderr-missing-prefix-value" >&2
  exit 1
fi

if ! grep -Fq "Missing value for --prefix" "$tmpdir/stderr-missing-prefix-value"; then
  eprint "Expected missing --prefix value error message"
  cat "$tmpdir/stderr-missing-prefix-value" >&2
  exit 1
fi

set +e
(cd "$repo" && "$updater" --repo --ref v0.2.39) >/dev/null 2>"$tmpdir/stderr-missing-repo-value"
code=$?
set -e
if [[ "$code" -ne 1 ]]; then
  eprint "Expected exit code 1 when --repo value is missing, got: $code"
  cat "$tmpdir/stderr-missing-repo-value" >&2
  exit 1
fi

if ! grep -Fq "Missing value for --repo" "$tmpdir/stderr-missing-repo-value"; then
  eprint "Expected missing --repo value error message"
  cat "$tmpdir/stderr-missing-repo-value" >&2
  exit 1
fi

set +e
(cd "$repo" && "$updater" --ref) >/dev/null 2>"$tmpdir/stderr-missing-ref-value"
code=$?
set -e
if [[ "$code" -ne 1 ]]; then
  eprint "Expected exit code 1 when --ref value is missing, got: $code"
  cat "$tmpdir/stderr-missing-ref-value" >&2
  exit 1
fi

if ! grep -Fq "Missing value for --ref" "$tmpdir/stderr-missing-ref-value"; then
  eprint "Expected missing --ref value error message"
  cat "$tmpdir/stderr-missing-ref-value" >&2
  exit 1
fi

out_file="$tmpdir/stdout-dry-run"
(cd "$repo" && "$updater" --ref v0.2.39 --dry-run >"$out_file")

if ! grep -Fq "git subtree pull --prefix .agentic-sdd-upstream https://github.com/ToaruPen/Agentic-SDD.git v0.2.39 --squash" "$out_file"; then
  eprint "Expected dry-run subtree command output"
  cat "$out_file" >&2
  exit 1
fi

mkdir -p "$repo/subdir/nested"
out_nested="$tmpdir/stdout-dry-run-subdir"
(cd "$repo/subdir/nested" && "$updater" --ref v0.2.39 --dry-run >"$out_nested")

if ! grep -Fq "git subtree pull --prefix .agentic-sdd-upstream https://github.com/ToaruPen/Agentic-SDD.git v0.2.39 --squash" "$out_nested"; then
  eprint "Expected dry-run subtree command output from nested directory"
  cat "$out_nested" >&2
  exit 1
fi

eprint "OK: scripts/tests/test-update-agentic-sdd.sh"
