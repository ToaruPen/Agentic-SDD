#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
script_path="$repo_root/scripts/watch-codex-review.sh"

if [[ ! -x "$script_path" ]]; then
  eprint "Missing script or not executable: $script_path"
  exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t watch-codex-review-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

mkdir -p "$tmpdir/bin"
cat > "$tmpdir/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$tmpdir/bin/gh"

unset CODEX_BOT_LOGINS
unset CODEX_REVIEW_HOOK

out="$tmpdir/out.txt"
set +e
PATH="$tmpdir/bin:$PATH" bash "$script_path" --pr 110 --repo o/r --once >"$out" 2>&1
rc=$?
set -e

if [[ "$rc" -ne 2 ]]; then
  eprint "Expected exit code 2 when CODEX_BOT_LOGINS is missing (got: $rc)"
  exit 1
fi

if ! grep -Fq "CODEX_BOT_LOGINS is required" "$out"; then
  eprint "Expected missing CODEX_BOT_LOGINS error message"
  exit 1
fi

eprint "test-watch-codex-review: ok"
