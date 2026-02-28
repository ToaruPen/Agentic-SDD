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
	cp -p "$repo_root/scripts/md_sanitize.py" "$r/scripts/md_sanitize.py"
	chmod +x "$r/scripts/lint-sot.py"
	printf '%s\n' "$r"
}



write_base_docs() {
	local r="$1"
	cat >"$r/docs/glossary.md" <<'EOF'
# Glossary
EOF

	cat >"$r/docs/sot/README.md" <<'EOF'
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
cat >"$r2/docs/sot/codefence.md" <<'EOF'
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
cat >"$r2b/docs/sot/inline-code.md" <<'EOF'
# Inline code

This should not be linted as a link target: `[x](./missing.md)`
EOF

if ! (cd "$r2b" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
	eprint "Expected lint-sot OK when broken links only exist inside inline code spans"
	exit 1
fi

r3="$(new_repo case-broken-link)"
write_base_docs "$r3"
cat >"$r3/docs/sot/broken.md" <<'EOF'
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
cat >"$r3b/docs/sot/ref.md" <<'EOF'
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
cat >"$r4/docs/prd/prd.md" <<'EOF'
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
cat >"$r5/docs/prd/prd.md" <<'EOF'
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
cat >"$r6/docs/prd/prd.md" <<'EOF'
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
cat >"$r6b/docs/prd/prd.md" <<'EOF'
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
cat >"$r8/docs/sot/unmatched.md" <<'EOF'
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
cat >"$r9/docs/research/README.md" <<'EOF'
# Research Index

This is a helper doc. It should not be forced to include 候補-1.. or 止め時.
EOF
mkdir -p "$r9/docs/research/prd/proj"
cat >"$r9/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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
cat >"$r9a/docs/research/prd/proj/2026-02-15.md" <<'EOF'
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
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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
cat >"$r9aa/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

    ## 2. 新規性判定（発火条件）

    - 直接の先行事例が2件未満: No
    - PRD Q6 に Unknown が残る: No
    - Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

    ## 候補（必須: >= 5）

    候補-1
    概要: a
    適用可否: Yes
    仮説: h
    反証: f
    採否理由: r
    根拠リンク:
    - https://example.com
    捨て条件:
    - x
    リスク/検証:
    - y

    候補-2
    概要: a
    適用可否: Yes
    仮説: h
    反証: f
    採否理由: r
    根拠リンク:
    - https://example.com
    捨て条件:
    - x
    リスク/検証:
    - y

    候補-3
    概要: a
    適用可否: Yes
    仮説: h
    反証: f
    採否理由: r
    根拠リンク:
    - https://example.com
    捨て条件:
    - x
    リスク/検証:
    - y

    候補-4
    概要: a
    適用可否: Yes
    仮説: h
    反証: f
    採否理由: r
    根拠リンク:
    - https://example.com
    捨て条件:
    - x
    リスク/検証:
    - y

    候補-5
    概要: a
    適用可否: Yes
    仮説: h
    反証: f
    採否理由: r
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
cat >"$r9ab/docs/research/prd/proj/2026-02-15.md" <<'EOF'
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
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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
cat >"$r9ac/docs/research/prd/proj/2026-02-15.md" <<'EOF'
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
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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
cat >"$r9b/docs/research/prd/proj/latest.md" <<'EOF'
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
cat >"$r9d/docs/research/prd/proj/_template.md" <<'EOF'
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
cat >"$r9c/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No

## 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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
cat >"$r10/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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
cat >"$r11/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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
cat >"$r11b/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 候補（必須: >= 5）

候補-1
メモ: 概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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
cat >"$r14/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- not-a-url
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- not-a-url
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- not-a-url
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- not-a-url
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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

r14b="$(new_repo case-research-evidence-url-outside-evidence-section)"
write_base_docs "$r14b"
mkdir -p "$r14b/docs/research/prd/proj"
cat >"$r14b/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- not-a-url
仮説:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- not-a-url
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- not-a-url
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- not-a-url
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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
(cd "$r14b" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r14b/stderr"
code_evidence_scope=$?
set -e

if [[ "$code_evidence_scope" -eq 0 ]]; then
	eprint "Expected lint-sot failure when URL appears outside 根拠リンク section"
	cat "$r14b/stderr" >&2 || true
	exit 1
fi

if ! grep -q "'根拠リンク:' 配下に URL" "$r14b/stderr"; then
	eprint "Expected evidence section scope message, got:"
	cat "$r14b/stderr" >&2 || true
	exit 1
fi

r16="$(new_repo case-research-evidence-url-with-description)"
write_base_docs "$r16"
mkdir -p "$r16/docs/research/prd/proj"
cat >"$r16/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com (docs)
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com (docs)
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com (docs)
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com (docs)
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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
cat >"$r15/docs/research/epic/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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

## 6. 外部サービス比較ゲート

外部サービス比較ゲート: Skip（理由）

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
cat >"$r12/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: Yes
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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
cat >"$r13/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: Yes
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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
cat >"$r13b/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: Yes
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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

r17="$(new_repo case-research-epic-comparison-valid)"
write_base_docs "$r17"
mkdir -p "$r17/docs/research/epic/proj"
cat >"$r17/docs/research/epic/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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

## 6. 外部サービス比較ゲート

外部サービス比較ゲート: Required

比較対象サービス:
- OpenAI API（OpenAI）
- Claude API（Anthropic）
- Gemini API（Google）

代替系統カバレッジ:
- SaaS API
- OSS self-host
- Managed BaaS

評価軸（重み）:
- 初期費用（30%）
- 可用性（40%）
- 運用負荷（30%）

定量比較表:
| サービス名 | ベンダー | 初期費用 | 月額費用 | レイテンシ | 可用性SLO | 運用負荷 | 適用判定 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| OpenAI API | OpenAI | 0 | 100 | 300ms | 99.9% | Low | Yes |
| Claude API | Anthropic | 0 | 120 | 350ms | 99.9% | Low | Partial |
| Gemini API | Google | 0 | 90 | 320ms | 99.9% | Med | Partial |

判定理由:
- 初期費用と運用負荷を重視し OpenAI API を採用
EOF

if ! (cd "$r17" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
	eprint "Expected lint-sot OK for epic research with valid external-service comparison gate"
	exit 1
fi

r18="$(new_repo case-research-epic-comparison-missing)"
write_base_docs "$r18"
mkdir -p "$r18/docs/research/epic/proj"
cat >"$r18/docs/research/epic/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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
EOF

set +e
(cd "$r18" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r18/stderr"
code_epic_comparison_missing=$?
set -e

if [[ "$code_epic_comparison_missing" -eq 0 ]]; then
	eprint "Expected lint-sot failure for epic research missing external-service comparison gate"
	cat "$r18/stderr" >&2 || true
	exit 1
fi

if ! grep -q "外部サービス比較ゲート" "$r18/stderr"; then
	eprint "Expected external-service comparison gate message, got:"
	cat "$r18/stderr" >&2 || true
	exit 1
fi

r19="$(new_repo case-research-epic-comparison-skip-with-reason)"
write_base_docs "$r19"
mkdir -p "$r19/docs/research/epic/proj"
cat >"$r19/docs/research/epic/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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

## 6. 外部サービス比較ゲート

外部サービス比較ゲート: Skip（コスト比較の対象外）
EOF

if ! (cd "$r19" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
	eprint "Expected lint-sot OK for epic research with Skip(reason)"
	exit 1
fi

r20="$(new_repo case-research-epic-comparison-required-and-skip)"
write_base_docs "$r20"
mkdir -p "$r20/docs/research/epic/proj"
cat >"$r20/docs/research/epic/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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

## 6. 外部サービス比較ゲート

外部サービス比較ゲート: Required
外部サービス比較ゲート: Skip（対象外）
EOF

set +e
(cd "$r20" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r20/stderr"
code_epic_required_and_skip=$?
set -e

if [[ "$code_epic_required_and_skip" -eq 0 ]]; then
	eprint "Expected lint-sot failure when Required and Skip are both set"
	cat "$r20/stderr" >&2 || true
	exit 1
fi

if ! grep -q "どちらか一方" "$r20/stderr"; then
	eprint "Expected mutually-exclusive gate message, got:"
	cat "$r20/stderr" >&2 || true
	exit 1
fi

r21="$(new_repo case-research-epic-comparison-required-empty-reason)"
write_base_docs "$r21"
mkdir -p "$r21/docs/research/epic/proj"
cat >"$r21/docs/research/epic/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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

## 6. 外部サービス比較ゲート

外部サービス比較ゲート: Required

比較対象サービス:
- OpenAI API（OpenAI）
- Claude API（Anthropic）
- Gemini API（Google）

代替系統カバレッジ:
- SaaS API
- OSS self-host
- Managed BaaS

評価軸（重み）:
- 初期費用（30%）
- 可用性（40%）
- 運用負荷（30%）

定量比較表:
| サービス名 | ベンダー | 初期費用 | 月額費用 | レイテンシ | 可用性SLO | 運用負荷 | 適用判定 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| OpenAI API | OpenAI | 0 | 100 | 300ms | 99.9% | Low | Yes |
| Claude API | Anthropic | 0 | 120 | 350ms | 99.9% | Low | Partial |
| Gemini API | Google | 0 | 90 | 320ms | 99.9% | Med | Partial |

判定理由:
EOF

set +e
(cd "$r21" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r21/stderr"
code_epic_required_empty_reason=$?
set -e

if [[ "$code_epic_required_empty_reason" -eq 0 ]]; then
	eprint "Expected lint-sot failure when Required has empty 判定理由"
	cat "$r21/stderr" >&2 || true
	exit 1
fi

if ! grep -q "判定理由" "$r21/stderr"; then
	eprint "Expected 判定理由 requirement message, got:"
	cat "$r21/stderr" >&2 || true
	exit 1
fi

r22="$(new_repo case-research-applicability-enum-invalid)"
write_base_docs "$r22"
mkdir -p "$r22/docs/research/prd/proj"
cat >"$r22/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Maybe
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Partial
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: No
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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
EOF

set +e
(cd "$r22" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r22/stderr"
code_applicability_enum=$?
set -e

if [[ "$code_applicability_enum" -eq 0 ]]; then
	eprint "Expected lint-sot failure for invalid 適用可否 value"
	cat "$r22/stderr" >&2 || true
	exit 1
fi

if ! grep -q "Yes / Partial / No" "$r22/stderr"; then
	eprint "Expected 適用可否 enum requirement message, got:"
	cat "$r22/stderr" >&2 || true
	exit 1
fi

r23="$(new_repo case-research-applicability-duplicate-lines)"
write_base_docs "$r23"
mkdir -p "$r23/docs/research/prd/proj"
cat >"$r23/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Maybe
仮説: h
反証: f
採否理由: r
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Partial
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: No
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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
EOF

set +e
(cd "$r23" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r23/stderr"
code_applicability_duplicate=$?
set -e

if [[ "$code_applicability_duplicate" -eq 0 ]]; then
	eprint "Expected lint-sot failure for duplicate 適用可否 lines"
	cat "$r23/stderr" >&2 || true
	exit 1
fi

if ! grep -q "1件のみ" "$r23/stderr"; then
	eprint "Expected 適用可否 single-line requirement message, got:"
	cat "$r23/stderr" >&2 || true
	exit 1
fi

r24="$(new_repo case-research-applicability-empty-and-valid-lines)"
write_base_docs "$r24"
mkdir -p "$r24/docs/research/prd/proj"
cat >"$r24/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否:
仮説: h
反証: f
採否理由: r
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Partial
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: No
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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
EOF

set +e
(cd "$r24" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r24/stderr"
code_applicability_empty_and_valid=$?
set -e

if [[ "$code_applicability_empty_and_valid" -eq 0 ]]; then
	eprint "Expected lint-sot failure for empty and valid duplicate 適用可否 lines"
	cat "$r24/stderr" >&2 || true
	exit 1
fi

if ! grep -q "1件のみ" "$r24/stderr"; then
	eprint "Expected 適用可否 single-line requirement message for empty+valid case, got:"
	cat "$r24/stderr" >&2 || true
	exit 1
fi

r25="$(new_repo case-research-epic-comparison-header-single-cell)"
write_base_docs "$r25"
mkdir -p "$r25/docs/research/epic/proj"
cat >"$r25/docs/research/epic/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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

## 6. 外部サービス比較ゲート

外部サービス比較ゲート: Required

比較対象サービス:
- OpenAI API（OpenAI）
- Claude API（Anthropic）
- Gemini API（Google）

代替系統カバレッジ:
- SaaS API
- OSS self-host
- Managed BaaS

評価軸（重み）:
- 初期費用（30%）
- 可用性（40%）
- 運用負荷（30%）

定量比較表:
| サービス名 ベンダー 初期費用 月額費用 レイテンシ 可用性SLO 運用負荷 適用判定 |
| --- |
| OpenAI API OpenAI 0 100 300ms 99.9% Low Yes |
| Claude API Anthropic 0 120 350ms 99.9% Low Partial |
| Gemini API Google 0 90 320ms 99.9% Med Partial |

判定理由:
- 比較表に基づいて選定
EOF

set +e
(cd "$r25" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r25/stderr"
code_epic_single_cell_header=$?
set -e

if [[ "$code_epic_single_cell_header" -eq 0 ]]; then
	eprint "Expected lint-sot failure for single-cell comparison header"
	cat "$r25/stderr" >&2 || true
	exit 1
fi

if ! grep -q "必須列" "$r25/stderr"; then
	eprint "Expected required columns message for malformed header, got:"
	cat "$r25/stderr" >&2 || true
	exit 1
fi

r26="$(new_repo case-research-missing-hypothesis-counterevidence-reason)"
write_base_docs "$r26"
mkdir -p "$r26/docs/research/prd/proj"
cat >"$r26/docs/research/prd/proj/2026-02-15.md" <<'EOF'
# Research

## 2. 新規性判定（発火条件）

- 直接の先行事例が2件未満: No
- PRD Q6 に Unknown が残る: No
- Q6-5〜8（PII/監査/性能/可用性）のいずれかが Yes: No

## 3. 候補（必須: >= 5）

候補-1
概要: a
適用可否: Yes
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-2
概要: a
適用可否: Yes
仮説: h
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-3
概要: a
適用可否: Yes
仮説: h
反証: f
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-4
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
根拠リンク:
- https://example.com
捨て条件:
- x
リスク/検証:
- y

候補-5
概要: a
適用可否: Yes
仮説: h
反証: f
採否理由: r
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
EOF

set +e
(cd "$r26" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r26/stderr"
code_missing_reasoning_fields=$?
set -e

if [[ "$code_missing_reasoning_fields" -eq 0 ]]; then
	eprint "Expected lint-sot failure when 仮説/反証/採否理由 are missing"
	cat "$r26/stderr" >&2 || true
	exit 1
fi

if ! grep -q "候補-1 に '仮説:' がありません" "$r26/stderr"; then
	eprint "Expected missing 仮説 field message, got:"
	cat "$r26/stderr" >&2 || true
	exit 1
fi

if ! grep -q "候補-2 に '反証:' がありません" "$r26/stderr"; then
	eprint "Expected missing 反証 field message, got:"
	cat "$r26/stderr" >&2 || true
	exit 1
fi

if ! grep -q "候補-3 に '採否理由:' がありません" "$r26/stderr"; then
	eprint "Expected missing 採否理由 field message, got:"
	cat "$r26/stderr" >&2 || true
	exit 1
fi

r27="$(new_repo case-sot-ref-valid)"
write_base_docs "$r27"
mkdir -p "$r27/docs/epics" "$r27/docs/prd"
cat >"$r27/docs/prd/test.md" <<'EOF'
# PRD: Test

- ステータス: Approved
EOF

cat >"$r27/docs/epics/test.md" <<'EOF'
# Epic: Test

- ステータス: Approved
- 参照PRD: `docs/prd/test.md`
EOF

if ! (cd "$r27" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
	eprint "Expected lint-sot OK for Approved Epic with valid 参照PRD"
	exit 1
fi

r28="$(new_repo case-sot-ref-empty)"
write_base_docs "$r28"
mkdir -p "$r28/docs/epics"
cat >"$r28/docs/epics/test.md" <<'EOF'
# Epic: Test

- ステータス: Approved
- 参照PRD:
EOF

set +e
(cd "$r28" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r28/stderr"
code_sot_ref_empty=$?
set -e

if [[ "$code_sot_ref_empty" -eq 0 ]]; then
	eprint "Expected lint-sot failure for empty 参照PRD"
	cat "$r28/stderr" >&2 || true
	exit 1
fi

if ! grep -q "参照PRD:' が空です\|参照PRD:' フィールドがありません" "$r28/stderr"; then
	eprint "Expected empty/missing 参照PRD message, got:"
	cat "$r28/stderr" >&2 || true
	exit 1
fi

r29="$(new_repo case-sot-ref-not-prd-path)"
write_base_docs "$r29"
mkdir -p "$r29/docs/epics"
cat >"$r29/docs/epics/test.md" <<'EOF'
# Epic: Test

- ステータス: Approved
- 参照PRD: docs/epics/other.md
EOF

set +e
(cd "$r29" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r29/stderr"
code_sot_ref_not_prd=$?
set -e

if [[ "$code_sot_ref_not_prd" -eq 0 ]]; then
	eprint "Expected lint-sot failure for 参照PRD outside docs/prd/"
	cat "$r29/stderr" >&2 || true
	exit 1
fi

if ! grep -q "docs/prd/ 配下" "$r29/stderr"; then
	eprint "Expected docs/prd/ path requirement message, got:"
	cat "$r29/stderr" >&2 || true
	exit 1
fi

r29b="$(new_repo case-sot-ref-traversal)"
write_base_docs "$r29b"
mkdir -p "$r29b/docs/epics" "$r29b/docs/prd"
cat >"$r29b/docs/epics/target.md" <<'EOF'
# Epic: Target
EOF

cat >"$r29b/docs/epics/test.md" <<'EOF'
# Epic: Test

- ステータス: Approved
- 参照PRD: docs/prd/../epics/target.md
EOF

set +e
(cd "$r29b" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r29b/stderr"
code_sot_ref_traversal=$?
set -e

if [[ "$code_sot_ref_traversal" -eq 0 ]]; then
	eprint "Expected lint-sot failure for path traversal in 参照PRD"
	cat "$r29b/stderr" >&2 || true
	exit 1
fi

if ! grep -q "docs/prd/ 配下" "$r29b/stderr"; then
	eprint "Expected docs/prd/ path requirement message for traversal, got:"
	cat "$r29b/stderr" >&2 || true
	exit 1
fi

r29c="$(new_repo case-sot-ref-directory)"
write_base_docs "$r29c"
mkdir -p "$r29c/docs/epics" "$r29c/docs/prd/subdir"
cat >"$r29c/docs/epics/test.md" <<'EOF'
# Epic: Test

- ステータス: Approved
- 参照PRD: docs/prd/subdir
EOF

set +e
(cd "$r29c" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r29c/stderr"
code_sot_ref_directory=$?
set -e

if [[ "$code_sot_ref_directory" -eq 0 ]]; then
	eprint "Expected lint-sot failure for directory path in 参照PRD"
	cat "$r29c/stderr" >&2 || true
	exit 1
fi

if ! grep -q "見つかりません" "$r29c/stderr"; then
	eprint "Expected missing file message for directory 参照PRD, got:"
	cat "$r29c/stderr" >&2 || true
	exit 1
fi

r29d="$(new_repo case-sot-ref-symlink)"
write_base_docs "$r29d"
mkdir -p "$r29d/docs/epics" "$r29d/docs/prd" "$r29d/outside"
cat >"$r29d/outside/secret.md" <<'EOF'
# Not a PRD
EOF
ln -s "$r29d/outside/secret.md" "$r29d/docs/prd/symlinked.md"
cat >"$r29d/docs/epics/test.md" <<'EOF'
# Epic: Test

- ステータス: Approved
- 参照PRD: docs/prd/symlinked.md
EOF

set +e
(cd "$r29d" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r29d/stderr"
code_sot_ref_symlink=$?
set -e

if [[ "$code_sot_ref_symlink" -eq 0 ]]; then
	eprint "Expected lint-sot failure for symlink escaping docs/prd/"
	cat "$r29d/stderr" >&2 || true
	exit 1
fi

if ! grep -q "見つかりません" "$r29d/stderr"; then
	eprint "Expected missing file message for symlink 参照PRD, got:"
	cat "$r29d/stderr" >&2 || true
	exit 1
fi

r30="$(new_repo case-sot-ref-multiple)"
write_base_docs "$r30"
mkdir -p "$r30/docs/epics" "$r30/docs/prd"
cat >"$r30/docs/prd/a.md" <<'EOF'
# PRD A
EOF

cat >"$r30/docs/prd/b.md" <<'EOF'
# PRD B
EOF

cat >"$r30/docs/epics/test.md" <<'EOF'
# Epic: Test

- ステータス: Approved
- 参照PRD: docs/prd/a.md
- 参照PRD: docs/prd/b.md
EOF

set +e
(cd "$r30" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r30/stderr"
code_sot_ref_multiple=$?
set -e

if [[ "$code_sot_ref_multiple" -eq 0 ]]; then
	eprint "Expected lint-sot failure for multiple 参照PRD lines"
	cat "$r30/stderr" >&2 || true
	exit 1
fi

if ! grep -q "複数" "$r30/stderr"; then
	eprint "Expected multiple 参照PRD message, got:"
	cat "$r30/stderr" >&2 || true
	exit 1
fi

r31="$(new_repo case-sot-ref-not-found)"
write_base_docs "$r31"
mkdir -p "$r31/docs/epics"
cat >"$r31/docs/epics/test.md" <<'EOF'
# Epic: Test

- ステータス: Approved
- 参照PRD: docs/prd/nonexistent.md
EOF

set +e
(cd "$r31" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r31/stderr"
code_sot_ref_not_found=$?
set -e

if [[ "$code_sot_ref_not_found" -eq 0 ]]; then
	eprint "Expected lint-sot failure for nonexistent 参照PRD target"
	cat "$r31/stderr" >&2 || true
	exit 1
fi

if ! grep -q "見つかりません" "$r31/stderr"; then
	eprint "Expected missing 参照PRD target message, got:"
	cat "$r31/stderr" >&2 || true
	exit 1
fi

r33="$(new_repo case-approved-in-fenced-code-draft-epic)"
write_base_docs "$r33"
mkdir -p "$r33/docs/epics"
cat >"$r33/docs/epics/test.md" <<'EOF'
# Epic: Test

- ステータス: Draft

```md
- ステータス: Approved
```
EOF

if ! (cd "$r33" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
	eprint "Expected lint-sot OK for Draft Epic with Approved status only inside fenced code"
	exit 1
fi

r34="$(new_repo case-approved-in-html-comment-draft-epic)"
write_base_docs "$r34"
mkdir -p "$r34/docs/epics"
cat >"$r34/docs/epics/test.md" <<'EOF'
# Epic: Test

- ステータス: Draft

<!--
- ステータス: Approved
-->
EOF

if ! (cd "$r34" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
	eprint "Expected lint-sot OK for Draft Epic with Approved status only inside HTML comment"
	exit 1
fi

r35="$(new_repo case-approved-in-indented-code-draft-epic)"
write_base_docs "$r35"
mkdir -p "$r35/docs/epics"
cat >"$r35/docs/epics/test.md" <<'EOF'
# Epic: Test

- ステータス: Draft

    - ステータス: Approved
EOF

if ! (cd "$r35" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
	eprint "Expected lint-sot OK for Draft Epic with Approved status only inside indented code"
	exit 1
fi

r36="$(new_repo case-real-approved-status-epic)"
write_base_docs "$r36"
mkdir -p "$r36/docs/epics"
cat >"$r36/docs/epics/test.md" <<'EOF'
# Epic: Test

- ステータス: Approved
EOF

set +e
(cd "$r36" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r36/stderr"
code_real_approved=$?
set -e

if [[ "$code_real_approved" -eq 0 ]]; then
	eprint "Expected lint-sot failure for real Approved Epic without 参照PRD"
	cat "$r36/stderr" >&2 || true
	exit 1
fi

if ! grep -q "参照PRD" "$r36/stderr"; then
	eprint "Expected 参照PRD message for real Approved Epic, got:"
	cat "$r36/stderr" >&2 || true
	exit 1
fi

r32="$(new_repo case-sot-ref-draft-skip)"
write_base_docs "$r32"
mkdir -p "$r32/docs/epics"
cat >"$r32/docs/epics/test.md" <<'EOF'
# Epic: Test

- ステータス: Draft
- 参照PRD:
EOF

if ! (cd "$r32" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
	eprint "Expected lint-sot OK for Draft Epic without valid 参照PRD"
	exit 1
fi

real_repo_root="$repo_root"
set +e
(cd "$real_repo_root" && python3 scripts/lint-sot.py docs) >/dev/null 2>"$tmpdir/real-repo-stderr"
code_sot_ref_regression=$?
set -e

if [[ "$code_sot_ref_regression" -ne 0 ]]; then
	eprint "Expected lint-sot OK on real repo docs (false positive regression)"
	cat "$tmpdir/real-repo-stderr" >&2 || true
	exit 1
fi

# r37: Approved Epic with inline code `<!--` must still be detected as Approved
# (strip_html_comment_blocks must not truncate after unmatched <!--)
r37="$(new_repo case-inline-html-comment-approved)"
write_base_docs "$r37"
mkdir -p "$r37/docs/epics"
cat >"$r37/docs/epics/test.md" <<'EPICEOF'
# Epic: Test

HTMLコメントの例: `<!--` はインラインコードです。

- ステータス: Approved
- 参照PRD:
EPICEOF

# An Approved Epic without valid 参照PRD must fail lint
set +e
(cd "$r37" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r37/stderr"
code_inline_comment=$?
set -e

if [[ "$code_inline_comment" -eq 0 ]]; then
	eprint "Expected lint-sot failure for Approved Epic with inline <!--  and missing 参照PRD"
	cat "$r37/stderr" >&2 || true
	exit 1
fi

if ! grep -q "参照PRD" "$r37/stderr"; then
	eprint "Expected 参照PRD message for Approved Epic with inline <!-- , got:"
	cat "$r37/stderr" >&2 || true
	exit 1
fi

# r38: Approved Epic with `<!--` and `-->` in separate inline code spans
# strip_html_comment_blocks must not treat them as a matched pair
r38="$(new_repo case-inline-comment-pair-approved)"
write_base_docs "$r38"
mkdir -p "$r38/docs/epics"
cat >"$r38/docs/epics/test.md" <<'EPICEOF'
# Epic: Test

HTMLコメントは `<!--` で開始します。

- ステータス: Approved
- 参照PRD:

閉じる場合は `-->` を使います。
EPICEOF

set +e
(cd "$r38" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r38/stderr"
code_inline_pair=$?
set -e

if [[ "$code_inline_pair" -eq 0 ]]; then
	eprint "Expected lint-sot failure for Approved Epic with inline <!-- and --> pair and missing 参照PRD"
	cat "$r38/stderr" >&2 || true
	exit 1
fi

if ! grep -q "参照PRD" "$r38/stderr"; then
	eprint "Expected 参照PRD message for Approved Epic with inline <!-- and --> pair, got:"
	cat "$r38/stderr" >&2 || true
	exit 1
fi

# r39: Draft Epic with Approved status inside tilde-fenced code block (~~~)
r39="$(new_repo case-approved-in-tilde-fenced-code-draft-epic)"
write_base_docs "$r39"
mkdir -p "$r39/docs/epics"
cat >"$r39/docs/epics/test.md" <<'EOF'
# Epic: Test

- ステータス: Draft

~~~md
- ステータス: Approved
~~~
EOF

if ! (cd "$r39" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
	eprint "Expected lint-sot OK for Draft Epic with Approved status only inside tilde-fenced code"
	exit 1
fi

# r40: Epic with ONLY nested (4-space indented) status must fail with format error
# (fail-fast: status lost during indented code block stripping)
r40="$(new_repo case-nested-status-format-error)"
write_base_docs "$r40"
mkdir -p "$r40/docs/epics"
cat >"$r40/docs/epics/test.md" <<'EOF'
# Epic: Test

## メタ情報

- メタ:
    - ステータス: Approved
    - 参照PRD: docs/prd/test.md
EOF

set +e
(cd "$r40" && python3 ./scripts/lint-sot.py docs) >/dev/null 2>"$r40/stderr"
code_nested_status=$?
set -e

if [[ "$code_nested_status" -eq 0 ]]; then
	eprint "Expected lint-sot failure for Epic with nested (indented) status line"
	exit 1
fi

if ! grep -q "ステータス行がインデント" "$r40/stderr"; then
	eprint "Expected indented status format error message, got:"
	cat "$r40/stderr" >&2 || true
	exit 1
fi

# r41: Epic with escaped backtick (\`) around <!-- must still treat <!-- as real comment
# The \` is NOT a code span delimiter, so <!-- is a genuine HTML comment opener.
# The Approved status is inside the comment and should be stripped.
r41="$(new_repo case-escaped-backtick-html-comment)"
write_base_docs "$r41"
mkdir -p "$r41/docs/epics"
cat >"$r41/docs/epics/test.md" <<'EPICEOF'
# Epic: Test

- ステータス: Draft
- 参照PRD: docs/prd/test.md

Here is an escaped backtick \`<!-- and another \`

- ステータス: Approved
EPICEOF

if ! (cd "$r41" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
	eprint "Expected lint-sot OK: escaped backticks do not create inline code span, so <!-- starts a real comment that hides Approved status"
	exit 1
fi

# r42: Code span `\` closes at inner backtick; <!-- after it is a real comment
# In CommonMark, backslash is literal inside code spans, so `\` is a code span
# containing just a backslash.  The <!-- that follows is outside the code span
# and acts as a genuine HTML comment opener that hides the Approved status.
r42="$(new_repo case-code-span-backslash-html-comment)"
write_base_docs "$r42"
mkdir -p "$r42/docs/epics"
cat >"$r42/docs/epics/test.md" <<'EPICEOF'
# Epic: Test

- ステータス: Draft
- 参照PRD: docs/prd/test.md

Example: `\`<!--`

- ステータス: Approved
EPICEOF

if ! (cd "$r42" && python3 ./scripts/lint-sot.py docs) >/dev/null; then
	eprint "Expected lint-sot OK: code span closes at inner backtick, <!-- is a real comment that hides Approved status"
	exit 1
fi

printf '%s\n' "OK"
