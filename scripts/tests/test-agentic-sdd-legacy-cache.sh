#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cli="$repo_root/scripts/agentic-sdd"

if [[ ! -x "$cli" ]]; then
	eprint "Missing script or not executable: $cli"
	exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-legacy-cache-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

remote="$tmpdir/remote"
mkdir -p "$remote/scripts"
git -C "$remote" init -q

cat >"$remote/scripts/install-agentic-sdd.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$remote/scripts/install-agentic-sdd.sh"

git -C "$remote" add scripts/install-agentic-sdd.sh
git -C "$remote" -c user.name=test -c user.email=test@example.com commit -m "legacy installer" -q
sha="$(git -C "$remote" rev-parse HEAD)"

target="$tmpdir/target"
cache="$tmpdir/cache"
mkdir -p "$target" "$cache"

real_git="$(command -v git)"
log="$tmpdir/git.log"
mkdir -p "$tmpdir/bin"
cat >"$tmpdir/bin/git" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$log"
exec "$real_git" "\$@"
EOF
chmod +x "$tmpdir/bin/git"

run_cli() {
	PATH="$tmpdir/bin:$PATH" "$cli" \
		--repo "$remote" \
		--ref "$sha" \
		--target "$target" \
		--tool none \
		--mode minimal \
		--cache-dir "$cache" \
		--dry-run \
		>/dev/null 2>&1
}

run_cli

fetch_count_after_first="$(grep -c ' fetch ' "$log" || true)"
if [[ "$fetch_count_after_first" -lt 1 ]]; then
	eprint "Expected at least one git fetch on first run"
	cat "$log" >&2
	exit 1
fi

run_cli

fetch_count_after_second="$(grep -c ' fetch ' "$log" || true)"
if [[ "$fetch_count_after_second" -ne "$fetch_count_after_first" ]]; then
	eprint "Expected second run to reuse cache for legacy installer layout (no additional fetch)"
	cat "$log" >&2
	exit 1
fi

eprint "OK: scripts/tests/test-agentic-sdd-legacy-cache.sh"
