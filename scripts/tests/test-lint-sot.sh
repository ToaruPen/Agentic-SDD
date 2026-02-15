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

r6b="$(new_repo case-marker-in-inline-code)"
write_base_docs "$r6b"
cat > "$r6b/docs/prd/prd.md" <<'EOF'
# PRD: Test

## メタ情報

- 作成日: 2026-02-14
- 作成者: @test
- ステータス: Approved
- バージョン: 1.0

This is inline code, not an allow marker: `<!-- lint-sot: allow-html-comments -->`

<!-- placeholder -->
EOF

set +e
(cd "$r6b" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r6b/stderr5"
code5=$?
set -e

if [[ "$code5" -eq 0 ]]; then
  eprint "Expected lint-sot failure when marker appears only inside inline code"
  cat "$r6b/stderr5" >&2 || true
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

r8="$(new_repo case-unmatched-backtick)"
write_base_docs "$r8"
cat > "$r8/docs/sot/unmatched.md" <<'EOF'
# Unmatched backtick

This is a stray backtick: `

- bad: [x](./missing.md)
EOF

set +e
(cd "$r8" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r8/stderr"
code_bt=$?
set -e

if [[ "$code_bt" -eq 0 ]]; then
  eprint "Expected lint-sot failure when broken link appears after an unmatched backtick"
  cat "$r8/stderr" >&2 || true
  exit 1
fi

r9="$(new_repo case-research-valid)"
write_base_docs "$r9"
mkdir -p "$r9/docs/research"
cat > "$r9/docs/research/README.md" <<'EOF'
# Research Index

This is a helper doc. It should not be forced to include 候補-1.. or 止め時.
EOF
mkdir -p "$r9/docs/research/prd/proj"
cat > "$r9/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

## 隣接領域探索

隣接領域探索: N/A（理由）

## 止め時

タイムボックス: 30min
打ち切り条件:
- ok
EOF

if ! (cd "$r9" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
  eprint "Expected lint-sot OK for valid research doc"
  exit 1
fi

r9a="$(new_repo case-research-codeblock-bypass)"
write_base_docs "$r9a"
mkdir -p "$r9a/docs/research/prd/proj"
cat > "$r9a/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

```md
## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

## 隣接領域探索

隣接領域探索: N/A（理由）

## 止め時

タイムボックス: 30min
打ち切り条件:
- ok
```
EOF

set +e
(cd "$r9a" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r9a/stderr"
code_research_codeblock=$?
set -e

if [[ "$code_research_codeblock" -eq 0 ]]; then
  eprint "Expected lint-sot failure when contract markers appear only in code blocks"
  cat "$r9a/stderr" >&2 || true
  exit 1
fi

if ! grep -q "候補（候補-1..）を 5件以上" "$r9a/stderr"; then
  eprint "Expected codeblock bypass to fail candidate count, got:"
  cat "$r9a/stderr" >&2 || true
  exit 1
fi

r9aa="$(new_repo case-research-indented-codeblock-bypass)"
write_base_docs "$r9aa"
mkdir -p "$r9aa/docs/research/prd/proj"
cat > "$r9aa/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

    ## 2. 新規性判定（発火条件）

    - 直接の先行事例が2件未満: No
    - PRD Q6 に Unknown が残る: No
    - Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

    ## 候補（必須: >= 5）

    候補-1
    概要: a
    適用可否: Yes
    根拠リンク:
    - https://example.com
    捨て条件:
    - x
    リスク/検証:
    - y

    候補-2
    概要: a
    適用可否: Yes
    根拠リンク:
    - https://example.com
    捨て条件:
    - x
    リスク/検証:
    - y

    候補-3
    概要: a
    適用可否: Yes
    根拠リンク:
    - https://example.com
    捨て条件:
    - x
    リスク/検証:
    - y

    候補-4
    概要: a
    適用可否: Yes
    根拠リンク:
    - https://example.com
    捨て条件:
    - x
    リスク/検証:
    - y

    候補-5
    概要: a
    適用可否: Yes
    根拠リンク:
    - https://example.com
    捨て条件:
    - x
    リスク/検証:
    - y

    ## 隣接領域探索

    隣接領域探索: N/A（理由）

    ## 止め時

    タイムボックス: 30min
    打ち切り条件:
    - ok
EOF

set +e
(cd "$r9aa" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r9aa/stderr"
code_research_indented_codeblock=$?
set -e

if [[ "$code_research_indented_codeblock" -eq 0 ]]; then
  eprint "Expected lint-sot failure when contract markers appear only in indented code blocks"
  cat "$r9aa/stderr" >&2 || true
  exit 1
fi

if ! grep -q "候補（候補-1..）を 5件以上" "$r9aa/stderr"; then
  eprint "Expected indented codeblock bypass to fail candidate count, got:"
  cat "$r9aa/stderr" >&2 || true
  exit 1
fi

r9ab="$(new_repo case-research-html-comment-bypass)"
write_base_docs "$r9ab"
mkdir -p "$r9ab/docs/research/prd/proj"
cat > "$r9ab/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

<!--
## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

## 隣接領域探索

隣接領域探索: N/A（理由）

## 止め時

タイムボックス: 30min
打ち切り条件:
- ok
-->
EOF

set +e
(cd "$r9ab" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r9ab/stderr"
code_research_html_comment=$?
set -e

if [[ "$code_research_html_comment" -eq 0 ]]; then
  eprint "Expected lint-sot failure when contract markers appear only in HTML comments"
  cat "$r9ab/stderr" >&2 || true
  exit 1
fi

if ! grep -q "候補（候補-1..）を 5件以上" "$r9ab/stderr"; then
  eprint "Expected HTML comment bypass to fail candidate count, got:"
  cat "$r9ab/stderr" >&2 || true
  exit 1
fi

r9ac="$(new_repo case-research-dangling-html-comment-bypass)"
write_base_docs "$r9ac"
mkdir -p "$r9ac/docs/research/prd/proj"
cat > "$r9ac/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

<!--
## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

## 隣接領域探索

隣接領域探索: N/A（理由）

## 止め時

タイムボックス: 30min
打ち切り条件:
- ok
EOF

set +e
(cd "$r9ac" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r9ac/stderr"
code_research_dangling_comment=$?
set -e

if [[ "$code_research_dangling_comment" -eq 0 ]]; then
  eprint "Expected lint-sot failure when contract markers appear after a dangling HTML comment opener"
  cat "$r9ac/stderr" >&2 || true
  exit 1
fi

if ! grep -q "候補（候補-1..）を 5件以上" "$r9ac/stderr"; then
  eprint "Expected dangling HTML comment bypass to fail candidate count, got:"
  cat "$r9ac/stderr" >&2 || true
  exit 1
fi

r9b="$(new_repo case-research-non-date-filename)"
write_base_docs "$r9b"
mkdir -p "$r9b/docs/research/prd/proj"
cat > "$r9b/docs/research/prd/proj/latest.md" <<'EOF'
# Research

This should be rejected because research artifacts must be date-based.
EOF

set +e
(cd "$r9b" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r9b/stderr"
code_research_name=$?
set -e

if [[ "$code_research_name" -eq 0 ]]; then
  eprint "Expected lint-sot failure for non-date research artifact filename"
  cat "$r9b/stderr" >&2 || true
  exit 1
fi

if ! grep -q "日付ファイル（YYYY-MM-DD.md）" "$r9b/stderr"; then
  eprint "Expected filename constraint message, got:"
  cat "$r9b/stderr" >&2 || true
  exit 1
fi

r9d="$(new_repo case-research-misplaced-template)"
write_base_docs "$r9d"
mkdir -p "$r9d/docs/research/prd/proj"
cat > "$r9d/docs/research/prd/proj/_template.md" <<'EOF'
# Research

This file should be rejected; only canonical templates are allowed.
EOF

set +e
(cd "$r9d" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r9d/stderr"
code_research_misplaced_tpl=$?
set -e

if [[ "$code_research_misplaced_tpl" -eq 0 ]]; then
  eprint "Expected lint-sot failure for misplaced research template"
  cat "$r9d/stderr" >&2 || true
  exit 1
fi

if ! grep -q "テンプレートは次の3つのみ許可します" "$r9d/stderr"; then
  eprint "Expected canonical template guidance message, got:"
  cat "$r9d/stderr" >&2 || true
  exit 1
fi

r9c="$(new_repo case-research-missing-novelty-trigger)"
write_base_docs "$r9c"
mkdir -p "$r9c/docs/research/prd/proj"
cat > "$r9c/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No

## 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

## 隣接領域探索

隣接領域探索: N/A（理由）

## 止め時

タイムボックス: 30min
打ち切り条件:
- ok
EOF

set +e
(cd "$r9c" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r9c/stderr"
code_research_trigger=$?
set -e

if [[ "$code_research_trigger" -eq 0 ]]; then
  eprint "Expected lint-sot failure for research doc missing a required novelty trigger"
  cat "$r9c/stderr" >&2 || true
  exit 1
fi

if ! grep -q "必須トリガ" "$r9c/stderr"; then
  eprint "Expected missing novelty trigger message, got:"
  cat "$r9c/stderr" >&2 || true
  exit 1
fi

if ! grep -q "Q6-5" "$r9c/stderr"; then
  eprint "Expected missing novelty trigger to mention Q6-5, got:"
  cat "$r9c/stderr" >&2 || true
  exit 1
fi

r10="$(new_repo case-research-missing-stop)"
write_base_docs "$r10"
mkdir -p "$r10/docs/research/prd/proj"
cat > "$r10/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

## 隣接領域探索

隣接領域探索: N/A（理由）
EOF

set +e
(cd "$r10" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r10/stderr"
code_research=$?
set -e

if [[ "$code_research" -eq 0 ]]; then
  eprint "Expected lint-sot failure for research doc missing stop conditions"
  cat "$r10/stderr" >&2 || true
  exit 1
fi

if ! grep -q "タイムボックス" "$r10/stderr"; then
  eprint "Expected missing timebox message, got:"
  cat "$r10/stderr" >&2 || true
  exit 1
fi

r11="$(new_repo case-research-missing-field-per-candidate)"
write_base_docs "$r11"
mkdir -p "$r11/docs/research/prd/proj"
cat > "$r11/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

## 隣接領域探索

隣接領域探索: N/A（理由）

## 止め時

タイムボックス: 30min
捨て条件: (this is not a candidate field)
打ち切り条件:
- ok
EOF

set +e
(cd "$r11" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r11/stderr"
code_research_field=$?
set -e

if [[ "$code_research_field" -eq 0 ]]; then
  eprint "Expected lint-sot failure when a candidate is missing a required field"
  cat "$r11/stderr" >&2 || true
  exit 1
fi

if ! grep -q "候補-1 に '捨て条件:' がありません" "$r11/stderr"; then
  eprint "Expected per-candidate missing field message, got:"
  cat "$r11/stderr" >&2 || true
  exit 1
fi

r11b="$(new_repo case-research-field-label-not-anchored)"
write_base_docs "$r11b"
mkdir -p "$r11b/docs/research/prd/proj"
cat > "$r11b/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 候補（必須: >= 5）

候補-1
メモ: 概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

## 隣接領域探索

隣接領域探索: N/A（理由）

## 止め時

タイムボックス: 30min
打ち切り条件:
- ok
EOF

set +e
(cd "$r11b" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r11b/stderr"
code_research_anchored=$?
set -e

if [[ "$code_research_anchored" -eq 0 ]]; then
  eprint "Expected lint-sot failure when a candidate label is present only in free text"
  cat "$r11b/stderr" >&2 || true
  exit 1
fi

if ! grep -q "候補-1 に '概要:' がありません" "$r11b/stderr"; then
  eprint "Expected anchored label missing message, got:"
  cat "$r11b/stderr" >&2 || true
  exit 1
fi

r14="$(new_repo case-research-missing-evidence-url)"
write_base_docs "$r14"
mkdir -p "$r14/docs/research/prd/proj"
cat > "$r14/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
根拠リンク:
- not-a-url
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
根拠リンク:
- not-a-url
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
根拠リンク:
- not-a-url
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
根拠リンク:
- not-a-url
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
根拠リンク:
- not-a-url
捨て条件:
- x
リスク/検証:
- y

## 4. 隣接領域探索

隣接領域探索: N/A（理由）

## 5. 止め時

タイムボックス: 30min
打ち切り条件:
- ok
EOF

set +e
(cd "$r14" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r14/stderr"
code_evidence=$?
set -e

if [[ "$code_evidence" -eq 0 ]]; then
  eprint "Expected lint-sot failure for research doc missing evidence URL"
  cat "$r14/stderr" >&2 || true
  exit 1
fi

if ! grep -q "'根拠リンク:' 配下に URL" "$r14/stderr"; then
  eprint "Expected missing evidence URL message, got:"
  cat "$r14/stderr" >&2 || true
  exit 1
fi

r16="$(new_repo case-research-evidence-url-with-description)"
write_base_docs "$r16"
mkdir -p "$r16/docs/research/prd/proj"
cat > "$r16/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
根拠リンク:
- https://example.com (docs)
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
根拠リンク:
- https://example.com (docs)
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
根拠リンク:
- https://example.com (docs)
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
根拠リンク:
- https://example.com (docs)
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
根拠リンク:
- https://example.com (docs)
捨て条件:
- x
リスク/検証:
- y

## 4. 隣接領域探索

隣接領域探索: N/A（理由）

## 5. 止め時

タイムボックス: 30min
打ち切り条件:
- ok
EOF

if ! (cd "$r16" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
  eprint "Expected lint-sot OK for evidence URL with description"
  exit 1
fi

r15="$(new_repo case-research-novelty-scope)"
write_base_docs "$r15"
mkdir -p "$r15/docs/research/epic/proj"
cat > "$r15/docs/research/epic/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

## 4. 隣接領域探索

隣接領域探索: N/A（理由）

## 5. 止め時

タイムボックス: 30min
打ち切り条件:
- ok

## Notes

- Unknown: Yes
EOF

if ! (cd "$r15" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
  eprint "Expected lint-sot OK when novelty Yes bullets appear outside novelty section"
  exit 1
fi

r12="$(new_repo case-research-novelty-yes-requires-adjacent)"
write_base_docs "$r12"
mkdir -p "$r12/docs/research/prd/proj"
cat > "$r12/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: Yes
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

## 4. 隣接領域探索（新規性が高い場合は必須）

隣接領域探索: N/A（理由）

## 5. 止め時（必須）

タイムボックス: 30min
打ち切り条件:
- ok
EOF

set +e
(cd "$r12" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r12/stderr"
code_novelty_yes=$?
set -e

if [[ "$code_novelty_yes" -eq 0 ]]; then
  eprint "Expected lint-sot failure when novelty trigger is Yes but adjacent exploration is marked N/A"
  cat "$r12/stderr" >&2 || true
  exit 1
fi

if ! grep -q "隣接領域探索が必須" "$r12/stderr"; then
  eprint "Expected adjacent-required message, got:"
  cat "$r12/stderr" >&2 || true
  exit 1
fi

r13="$(new_repo case-research-novelty-yes-with-adjacent)"
write_base_docs "$r13"
mkdir -p "$r13/docs/research/prd/proj"
cat > "$r13/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: Yes
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

## 4. 隣接領域探索（新規性が高い場合は必須）

隣接領域-1
概要: a
根拠リンク:
- https://example.com

隣接領域-2
概要: a
根拠リンク:
- https://example.com

抽象化-1
原理/パターン: x

適用マッピング
- PRD: a
- Epic: a
- Estimation: a

## 5. 止め時（必須）

タイムボックス: 30min
打ち切り条件:
- ok
EOF

if ! (cd "$r13" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
  eprint "Expected lint-sot OK when novelty triggers are Yes and adjacent exploration is filled"
  exit 1
fi

r13b="$(new_repo case-research-adjacent-outside-section)"
write_base_docs "$r13b"
mkdir -p "$r13b/docs/research/prd/proj"
cat > "$r13b/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: Yes
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

## 4. 隣接領域探索（新規性が高い場合は必須）

(intentionally empty)

## 5. 止め時（必須）

タイムボックス: 30min
打ち切り条件:
- ok

## Notes

隣接領域-1
概要: a
根拠リンク:
- https://example.com

隣接領域-2
概要: a
根拠リンク:
- https://example.com

適用マッピング
- PRD: a
- Epic: a
- Estimation: a
EOF

set +e
(cd "$r13b" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r13b/stderr"
code_adjacent_scope=$?
set -e

if [[ "$code_adjacent_scope" -eq 0 ]]; then
  eprint "Expected lint-sot failure when adjacent domains appear outside adjacent section"
  cat "$r13b/stderr" >&2 || true
  exit 1
fi

if ! grep -q "隣接領域（隣接領域-1..）を 2件以上" "$r13b/stderr"; then
  eprint "Expected adjacent scope failure message, got:"
  cat "$r13b/stderr" >&2 || true
  exit 1
fi

printf '%s\n' "OK"
