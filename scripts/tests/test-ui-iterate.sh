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

# node and curl shims for exercising builtin capture path.
mkdir -p "$tmpdir/bin"
cat > "$tmpdir/bin/node" <<'NODE'
#!/usr/bin/env bash
set -euo pipefail

scenario="${UI_ITERATE_NODE_SCENARIO:-ok}"
if [[ -n "${UI_ITERATE_NODE_MARKER:-}" ]]; then
  mkdir -p "$(dirname "$UI_ITERATE_NODE_MARKER")"
  printf 'node-ran' > "$UI_ITERATE_NODE_MARKER"
fi
case "$scenario" in
ok)
  mkdir -p "$(dirname "$3")"
  mkdir -p "$(dirname "$4")"
  printf 'desktop' > "$3"
  printf 'mobile' > "$4"
  exit 0
  ;;
toint)
  echo "invalid desktopW: abc" >&2
  exit 1
  ;;
nav-fail)
  echo "failed to load $2 (404)" >&2
  exit 1
  ;;
timeout)
  echo "networkidle: Timeout 10000ms exceeded." >&2
  exit 1
  ;;
*)
  echo "unknown node scenario: $scenario" >&2
  exit 1
  ;;
esac
NODE
chmod +x "$tmpdir/bin/node"

cat > "$tmpdir/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail

scenario="${UI_ITERATE_CURL_SCENARIO:-ok}"
if [[ "$scenario" == "unreachable" ]]; then
  echo "curl: (22) The requested URL returned error: 000" >&2
  exit 7
fi
exit 0
CURL
chmod +x "$tmpdir/bin/curl"

# 7) main builtin capture path should run through and create assets.
set +e
(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" UI_ITERATE_NODE_SCENARIO=ok UI_ITERATE_CURL_SCENARIO=ok ./scripts/ui-iterate.sh 99 round-06 --route /kiosk --skip-checks) >/dev/null 2>"$tmpdir/builtin-success-stderr"
code=$?
set -e

if [[ "$code" -ne 0 ]]; then
  eprint "Expected builtin capture path to succeed"
  cat "$tmpdir/builtin-success-stderr" >&2
  exit 1
fi
if [[ ! -f "$tmpdir/var/screenshot/issue-99/round-06/kiosk-desktop.png" ]]; then
  eprint "Expected desktop screenshot in round-06"
  exit 1
fi
if [[ ! -f "$tmpdir/var/screenshot/issue-99/round-06/kiosk-mobile.png" ]]; then
  eprint "Expected mobile screenshot in round-06"
  exit 1
fi

# 8) invalid dimensions should fail early with size validation message.
set +e
(cd "$tmpdir" && ./scripts/ui-iterate.sh 99 round-07 --route /kiosk --skip-checks --desktop-size 10x10) >/dev/null 2>"$tmpdir/invalid-size-stderr"
code_invalid_dim=$?
set -e

if [[ "$code_invalid_dim" -ne 2 ]]; then
  eprint "Expected invalid --desktop-size to fail with code 2"
  cat "$tmpdir/invalid-size-stderr" >&2
  exit 1
fi
if ! grep -q "Invalid --desktop-size" "$tmpdir/invalid-size-stderr"; then
  eprint "Expected invalid size validation message"
  cat "$tmpdir/invalid-size-stderr" >&2
  exit 1
fi

# 9) node toInt conversion failure should propagate through builtin capture error path.
set +e
(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" UI_ITERATE_NODE_SCENARIO=toint UI_ITERATE_CURL_SCENARIO=ok ./scripts/ui-iterate.sh 99 round-08 --route /kiosk --skip-checks) >/dev/null 2>"$tmpdir/toint-stderr"
code_toint=$?
set -e

if [[ "$code_toint" -ne 1 ]]; then
  eprint "Expected toInt failure to return code 1"
  cat "$tmpdir/toint-stderr" >&2
  exit 1
fi
if ! grep -q "invalid desktopW" "$tmpdir/toint-stderr"; then
  eprint "Expected toInt error in stderr"
  cat "$tmpdir/toint-stderr" >&2
  exit 1
fi
if ! grep -q "Builtin capture failed" "$tmpdir/toint-stderr"; then
  eprint "Expected wrapper builtin-capture failure message"
  cat "$tmpdir/toint-stderr" >&2
  exit 1
fi

# 10) navigation failure in node capture should fail with clear stderr.
set +e
(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" UI_ITERATE_NODE_SCENARIO=nav-fail UI_ITERATE_CURL_SCENARIO=ok ./scripts/ui-iterate.sh 99 round-09 --route /kiosk --skip-checks) >/dev/null 2>"$tmpdir/nav-fail-stderr"
code_nav_fail=$?
set -e

if [[ "$code_nav_fail" -ne 1 ]]; then
  eprint "Expected navigation failure to return code 1"
  cat "$tmpdir/nav-fail-stderr" >&2
  exit 1
fi
if ! grep -q "failed to load" "$tmpdir/nav-fail-stderr"; then
  eprint "Expected navigation failure message"
  cat "$tmpdir/nav-fail-stderr" >&2
  exit 1
fi

# 11) networkidle timeout should fail and expose timeout text in stderr.
set +e
(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" UI_ITERATE_NODE_SCENARIO=timeout UI_ITERATE_CURL_SCENARIO=ok ./scripts/ui-iterate.sh 99 round-10 --route /kiosk --skip-checks) >/dev/null 2>"$tmpdir/timeout-stderr"
code_timeout=$?
set -e

if [[ "$code_timeout" -ne 1 ]]; then
  eprint "Expected networkidle timeout path to return code 1"
  cat "$tmpdir/timeout-stderr" >&2
  exit 1
fi
if ! grep -q "networkidle" "$tmpdir/timeout-stderr"; then
  eprint "Expected timeout message in stderr"
  cat "$tmpdir/timeout-stderr" >&2
  exit 1
fi

# 12) unreachable URL check in builtin capture should fail before node runs.
node_marker="$tmpdir/node-marker-unreachable"
rm -f "$node_marker"
set +e
(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" UI_ITERATE_NODE_MARKER="$node_marker" UI_ITERATE_NODE_SCENARIO=ok UI_ITERATE_CURL_SCENARIO=unreachable ./scripts/ui-iterate.sh 99 round-11 --route /kiosk --skip-checks) >/dev/null 2>"$tmpdir/unreachable-stderr"
code_unreachable=$?
set -e

if [[ "$code_unreachable" -ne 1 ]]; then
  eprint "Expected unreachable URL to return code 1"
  cat "$tmpdir/unreachable-stderr" >&2
  exit 1
fi
if ! grep -q "Target URL is unreachable" "$tmpdir/unreachable-stderr"; then
  eprint "Expected unreachable URL message"
  cat "$tmpdir/unreachable-stderr" >&2
  exit 1
fi
if [[ -f "$node_marker" ]]; then
  eprint "Expected node shim not to run when URL reachability check fails"
  exit 1
fi

eprint "OK: scripts/tests/test-ui-iterate.sh"
