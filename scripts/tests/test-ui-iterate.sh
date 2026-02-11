#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
script_src="$repo_root/scripts/ui-iterate.sh"

if [[ ! -x "$script_src" ]]; then
  eprint "Missing script or not executable: $script_src"
  exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-ui-iterate-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

git -C "$tmpdir" init -q

mkdir -p "$tmpdir/scripts"
cp -p "$script_src" "$tmpdir/scripts/ui-iterate.sh"
chmod +x "$tmpdir/scripts/ui-iterate.sh"

cat > "$tmpdir/README.md" <<'EOF'
# Temp Repo
EOF

git -C "$tmpdir" add README.md
git -C "$tmpdir" -c user.name=test -c user.email=test@example.com commit -m "init" -q

# 1) dry-run should resolve to round-01 for first run.
dry_out="$tmpdir/dry-run.txt"
(cd "$tmpdir" && ./scripts/ui-iterate.sh 99 --dry-run --route /kiosk >"$dry_out" 2>&1)
if ! grep -q "round: round-01" "$dry_out"; then
  eprint "Expected dry-run to use round-01"
  cat "$dry_out" >&2
  exit 1
fi

# 2) capture-only with custom capture command should create screenshot files.
cap_cmd='mkdir -p "$(dirname "$UI_ITERATE_DESKTOP_FILE")" && printf desktop > "$UI_ITERATE_DESKTOP_FILE" && printf mobile > "$UI_ITERATE_MOBILE_FILE"'
(cd "$tmpdir" && ./scripts/ui-iterate.sh 99 round-01 --route /kiosk --skip-checks --capture-cmd "$cap_cmd") >/dev/null

if [[ ! -f "$tmpdir/var/screenshot/issue-99/round-01/kiosk-desktop.png" ]]; then
  eprint "Expected desktop screenshot in round-01"
  exit 1
fi
if [[ ! -f "$tmpdir/var/screenshot/issue-99/round-01/kiosk-mobile.png" ]]; then
  eprint "Expected mobile screenshot in round-01"
  exit 1
fi
if [[ ! -f "$tmpdir/var/screenshot/issue-99/round-01/meta.txt" ]]; then
  eprint "Expected meta.txt in round-01"
  exit 1
fi

# 3) auto-round increment should produce round-02.
(cd "$tmpdir" && ./scripts/ui-iterate.sh 99 --route /kiosk --skip-checks --capture-cmd "$cap_cmd") >/dev/null
if [[ ! -f "$tmpdir/var/screenshot/issue-99/round-02/kiosk-desktop.png" ]]; then
  eprint "Expected desktop screenshot in auto round-02"
  exit 1
fi

# 4) checks should run and write commands manifest.
(cd "$tmpdir" && ./scripts/ui-iterate.sh 99 round-03 --route /staff --skip-capture \
  --check-cmd "printf typecheck-ok" \
  --check-cmd "printf lint-ok") >/dev/null

manifest="$tmpdir/var/screenshot/issue-99/round-03/checks/commands.txt"
if [[ ! -f "$manifest" ]]; then
  eprint "Expected check manifest: $manifest"
  exit 1
fi
if ! grep -q $'^ok\tprintf typecheck-ok\t' "$manifest"; then
  eprint "Expected first check result in manifest"
  cat "$manifest" >&2
  exit 1
fi

# 5) failing check should return non-zero and write fail status.
set +e
(cd "$tmpdir" && ./scripts/ui-iterate.sh 99 round-04 --route /staff --skip-capture --check-cmd "exit 7") >/dev/null 2>"$tmpdir/fail-stderr"
code=$?
set -e

if [[ "$code" -eq 0 ]]; then
  eprint "Expected non-zero exit when check command fails"
  exit 1
fi

fail_manifest="$tmpdir/var/screenshot/issue-99/round-04/checks/commands.txt"
if [[ ! -f "$fail_manifest" ]]; then
  eprint "Expected fail manifest: $fail_manifest"
  exit 1
fi
if ! grep -q $'^fail\texit 7\t' "$fail_manifest"; then
  eprint "Expected fail status in manifest"
  cat "$fail_manifest" >&2
  exit 1
fi

# 6) checks enabled with no commands should fail-fast.
set +e
(cd "$tmpdir" && ./scripts/ui-iterate.sh 99 round-05 --route /kiosk --skip-capture) >/dev/null 2>"$tmpdir/no-checks-stderr"
code_no_checks=$?
set -e

if [[ "$code_no_checks" -eq 0 ]]; then
  eprint "Expected failure when checks are enabled but no check command is configured"
  exit 1
fi

if ! grep -q "No check commands configured" "$tmpdir/no-checks-stderr"; then
  eprint "Expected no-checks error message"
  cat "$tmpdir/no-checks-stderr" >&2
  exit 1
fi

eprint "OK: scripts/tests/test-ui-iterate.sh"
