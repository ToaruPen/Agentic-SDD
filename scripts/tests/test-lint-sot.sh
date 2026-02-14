#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
lint_py_src="$repo_root/scripts/lint-sot.py"

if [[ ! -f "$lint_py_src" ]]; then
  eprint "Missing lint script: $lint_py_src"
  exit 1
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentic-sdd-lint-sot-test)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

new_repo() {
  local name="$1"
  local r="$tmpdir/$name"
  mkdir -p "$r"
  git -C "$r" init -q
  mkdir -p "$r/scripts" "$r/docs/prd" "$r/docs/sot" "$r/docs"
  cp -p "$lint_py_src" "$r/scripts/lint-sot.py"
  chmod +x "$r/scripts/lint-sot.py"
  printf '%s\n' "$r"
}

write_base_docs() {
  local r="$1"
  cat > "$r/docs/glossary.md" <<'EOF'
# Glossary
EOF

  cat > "$r/docs/sot/README.md" <<'EOF'
# SoT

- ok-title: [g](../glossary.md "title")
- ok-root: [g](/docs/glossary.md)
EOF
}

r1="$(new_repo case-valid)"
write_base_docs "$r1"
if ! (cd "$r1" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
  eprint "Expected lint-sot OK for valid links"
  exit 1
fi

r2="$(new_repo case-codefence)"
write_base_docs "$r2"
cat > "$r2/docs/sot/codefence.md" <<'EOF'
# Codefence

```md
- inner fence-like line should not close:
```python
- this link should be ignored by the linter: [x](./missing-in-codefence.md)
```

Inline code span should also be ignored: `[x](./missing-inline.md)`
EOF

if ! (cd "$r2" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
  eprint "Expected lint-sot OK when broken links only exist inside fenced code blocks"
  exit 1
fi

r2b="$(new_repo case-inline-code)"
write_base_docs "$r2b"
cat > "$r2b/docs/sot/inline-code.md" <<'EOF'
# Inline code

This should not be linted as a link target: `[x](./missing.md)`
EOF

if ! (cd "$r2b" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
  eprint "Expected lint-sot OK when broken links only exist inside inline code spans"
  exit 1
fi

r3="$(new_repo case-broken-link)"
write_base_docs "$r3"
cat > "$r3/docs/sot/broken.md" <<'EOF'
# Broken

- bad: [x](./missing.md)
EOF

set +e
(cd "$r3" && python3 ./scripts/lint-sot.py docs) >"$r3/stdout" 2>"$r3/stderr"
code=$?
set -e

if [[ "$code" -eq 0 ]]; then
  eprint "Expected lint-sot failure for broken relative link"
  cat "$r3/stderr" >&2 || true
  exit 1
fi

if ! grep -q "Broken relative link target" "$r3/stderr"; then
  eprint "Expected broken link message, got:"
  cat "$r3/stderr" >&2 || true
  exit 1
fi

r3b="$(new_repo case-ref-def-broken)"
write_base_docs "$r3b"
cat > "$r3b/docs/sot/ref.md" <<'EOF'
# Reference def

[x][id]

[id]: ./missing.md
EOF

set +e
(cd "$r3b" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r3b/stderr"
code_ref=$?
set -e

if [[ "$code_ref" -eq 0 ]]; then
  eprint "Expected lint-sot failure for broken reference-style link definition"
  cat "$r3b/stderr" >&2 || true
  exit 1
fi

r4="$(new_repo case-placeholder)"
write_base_docs "$r4"
cat > "$r4/docs/prd/prd.md" <<'EOF'
# PRD: Test

## メタ情報

- 作成日: 2026-02-14
- 作成者: @test
- ステータス: Approved
- バージョン: 1.0

<!-- placeholder -->
EOF

set +e
(cd "$r4" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r4/stderr2"
code2=$?
set -e

if [[ "$code2" -eq 0 ]]; then
  eprint "Expected lint-sot failure for HTML comment in Approved PRD"
  cat "$r4/stderr2" >&2 || true
  exit 1
fi

if ! grep -q "Approved doc contains HTML comment" "$r4/stderr2"; then
  eprint "Expected HTML comment message, got:"
  cat "$r4/stderr2" >&2 || true
  exit 1
fi

r5="$(new_repo case-allow-comments)"
write_base_docs "$r5"
cat > "$r5/docs/prd/prd.md" <<'EOF'
# PRD: Test

## メタ情報

- 作成日: 2026-02-14
- 作成者: @test
- ステータス: Approved
- バージョン: 1.0

<!-- lint-sot: allow-html-comments -->

<!-- generated-by: tool -->
EOF

if ! (cd "$r5" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
  eprint "Expected lint-sot OK when allow marker is present"
  exit 1
fi

r6="$(new_repo case-marker-in-codefence)"
write_base_docs "$r6"
cat > "$r6/docs/prd/prd.md" <<'EOF'
# PRD: Test

## メタ情報

- 作成日: 2026-02-14
- 作成者: @test
- ステータス: Approved
- バージョン: 1.0

```txt
lint-sot: allow-html-comments
```

<!-- placeholder -->
EOF

set +e
(cd "$r6" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r6/stderr4"
code4=$?
set -e

if [[ "$code4" -eq 0 ]]; then
  eprint "Expected lint-sot failure when marker appears only inside a code fence"
  cat "$r6/stderr4" >&2 || true
  exit 1
fi

r7="$(new_repo case-unsafe-root)"
write_base_docs "$r7"
set +e
(cd "$r7" && python3 ./scripts/lint-sot.py ..) >/dev/null 2>"$r7/stderr3"
code3=$?
set -e

if [[ "$code3" -eq 0 ]]; then
  eprint "Expected lint-sot failure for unsafe root path"
  cat "$r7/stderr3" >&2 || true
  exit 1
fi

if ! grep -q "Root path must be repo-relative" "$r7/stderr3"; then
  eprint "Expected repo-relative root error message, got:"
  cat "$r7/stderr3" >&2 || true
  exit 1
fi

printf '%s\n' "OK"
