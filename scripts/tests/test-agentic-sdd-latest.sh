#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cli="$repo_root/scripts/agentic-sdd"

if [[ ! -x "$cli" ]]; then
  eprint "Missing script or not executable: $cli"
  exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-latest-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

remote="$tmpdir/remote"
mkdir -p "$remote"
git -C "$remote" init -q

mkcommit_tag() {
  local tag="$1"
  local marker="$2"

  mkdir -p "$remote/scripts"
  cat > "$remote/scripts/install-agentic-sdd.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
# marker: $marker
exit 0
EOF
  chmod +x "$remote/scripts/install-agentic-sdd.sh"

  git -C "$remote" add scripts/install-agentic-sdd.sh
  git -C "$remote" -c user.name=test -c user.email=test@example.com commit -m "release $tag" -q
  git -C "$remote" tag "$tag"
}

mkcommit_tag "0.2.10" "a"
mkcommit_tag "v0.2.11" "b"

expected_tag="v0.2.11"
expected_sha="$(git -C "$remote" rev-parse "${expected_tag}^{commit}")"

target="$tmpdir/target"
mkdir -p "$target"

out="$tmpdir/out"

set +e
"$cli" \
  --repo "$remote" \
  --ref latest \
  --target "$target" \
  --tool none \
  --mode minimal \
  --no-cache \
  --dry-run \
  >"$out" 2>&1
code=$?
set -e

if [[ "$code" -ne 0 ]]; then
  eprint "Expected exit code 0, got: $code"
  cat "$out" >&2
  exit 1
fi

if ! grep -Fqx "[INFO] Resolved latest tag: $expected_tag" "$out"; then
  eprint "Expected latest tag to be resolved to: $expected_tag"
  cat "$out" >&2
  exit 1
fi

if ! grep -Fqx "[INFO] Resolved sha: $expected_sha" "$out"; then
  eprint "Expected resolved sha to be: $expected_sha"
  cat "$out" >&2
  exit 1
fi

eprint "OK: scripts/tests/test-agentic-sdd-latest.sh"
