#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
hook_src="$repo_root/.githooks/pre-push"

if [[ ! -x "$hook_src" ]]; then
	eprint "Missing hook or not executable: $hook_src"
	exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-prepush-discovery)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

write_validator() {
	local path="$1"
	mkdir -p "$(dirname "$path")"
	cat >"$path" <<'PY'
#!/usr/bin/env python3
import os
import sys

marker = os.environ.get("PREPUSH_MARKER", "")
if marker:
    with open(marker, "a", encoding="utf-8") as fh:
        fh.write(sys.argv[0] + "\n")
PY
	chmod +x "$path"
}

setup_repo() {
	local dir="$1"
	git -C "$dir" init -q
	git -C "$dir" config user.email "test@example.com"
	git -C "$dir" config user.name "Test"

	mkdir -p "$dir/.githooks" "$dir/scripts"
	cp -p "$hook_src" "$dir/.githooks/pre-push"
	chmod +x "$dir/.githooks/pre-push"

	printf 'seed\n' >"$dir/README.md"
	git -C "$dir" add README.md
	git -C "$dir" commit -m "test: seed" -q
}

run_case() {
	local name="$1"
	local expected_rc="$2"
	local expected_err="$3"
	local expected_marker_substr="$4"

	local dir="$tmpdir/$name"
	local marker="$dir/marker.log"
	local stderr_file="$dir/stderr.log"

	mkdir -p "$dir"
	setup_repo "$dir"

	case "$name" in
	nested_pair)
		write_validator "$dir/scripts/agentic-sdd/validate-worktree.py"
		write_validator "$dir/scripts/agentic-sdd/validate-approval.py"
		;;
	legacy_pair)
		write_validator "$dir/scripts/validate-worktree.py"
		write_validator "$dir/scripts/validate-approval.py"
		;;
	one_missing)
		write_validator "$dir/scripts/validate-approval.py"
		;;
	both_missing)
		# intentionally do nothing when both validators are missing
		;;
	*)
		eprint "Unknown case: $name"
		exit 1
		;;
	esac

	set +e
	(cd "$dir" && PREPUSH_MARKER="$marker" ./.githooks/pre-push </dev/null) >/dev/null 2>"$stderr_file"
	rc=$?
	set -e

	if [[ "$rc" -ne "$expected_rc" ]]; then
		eprint "Case '$name': expected rc=$expected_rc, got rc=$rc"
		cat "$stderr_file" >&2
		exit 1
	fi

	if [[ -n "$expected_err" ]]; then
		if ! grep -Fq "$expected_err" "$stderr_file"; then
			eprint "Case '$name': expected stderr to contain: $expected_err"
			cat "$stderr_file" >&2
			exit 1
		fi
	elif [[ -s "$stderr_file" ]]; then
		eprint "Case '$name': expected empty stderr"
		cat "$stderr_file" >&2
		exit 1
	fi

	if [[ -n "$expected_marker_substr" ]]; then
		if [[ ! -f "$marker" ]] || ! grep -Fq "$expected_marker_substr" "$marker"; then
			eprint "Case '$name': expected marker to include '$expected_marker_substr'"
			[[ -f "$marker" ]] && cat "$marker" >&2
			exit 1
		fi
	fi
}

run_case "nested_pair" 0 "" "scripts/agentic-sdd/validate-worktree.py"
run_case "legacy_pair" 0 "" "scripts/validate-worktree.py"
run_case "one_missing" 1 "[agentic-sdd gate] BLOCKED: validate-worktree.py is missing. Reinstall/upgrade Agentic-SDD." ""
run_case "both_missing" 1 "[agentic-sdd gate] BLOCKED: validator pair is missing. Reinstall/upgrade Agentic-SDD." ""

printf '%s\n' "OK: scripts/tests/test-pre-push-validator-discovery.sh"
