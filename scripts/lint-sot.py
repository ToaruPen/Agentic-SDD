#!/usr/bin/env python3

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from typing import Iterable, List, Optional


@dataclass(frozen=True)
class LintError:
    path: str
    message: str


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def repo_root() -> str:
    try:
        p = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except Exception:
        return os.path.realpath(os.getcwd())

    root = (p.stdout or "").strip()
    if not root:
        return os.path.realpath(os.getcwd())
    return os.path.realpath(root)


def iter_markdown_files(root: str) -> Iterable[str]:
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in {".git", ".agentic-sdd"}]
        dirnames.sort()
        filenames.sort()
        for name in filenames:
            if not name.endswith(".md"):
                continue
            yield os.path.join(dirpath, name)


def is_safe_repo_relative_root(root: str) -> bool:
    if not root:
        return False
    if os.path.isabs(root):
        return False
    p = root.replace("\\", "/").strip()
    if p.startswith("./"):
        p = p[2:]
    if p in {".", ".."}:
        return False
    parts = [x for x in p.split("/") if x]
    if not parts:
        return False
    if ".." in parts:
        return False
    return True


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


_STATUS_APPROVED_RE = re.compile(r"^\s*-\s*ステータス\s*:\s*Approved\s*$", re.MULTILINE)
_ALLOW_HTML_COMMENTS_RE = re.compile(r"<!--\s*lint-sot:\s*allow-html-comments\s*-->")


def is_approved_prd_or_epic(rel_path: str, text: str) -> bool:
    if rel_path.startswith("docs/prd/") or rel_path.startswith("docs/epics/"):
        if os.path.basename(rel_path) == "_template.md":
            return False
        return _STATUS_APPROVED_RE.search(text) is not None
    return False


def lint_placeholders(repo: str, rel_path: str, text: str) -> List[LintError]:
    errs: List[LintError] = []
    if is_approved_prd_or_epic(rel_path, text):
        scrubbed = strip_inline_code_spans(strip_fenced_code_blocks(text))
        if "<!--" in scrubbed and not _ALLOW_HTML_COMMENTS_RE.search(scrubbed):
            errs.append(
                LintError(
                    path=rel_path,
                    message=(
                        "Approved doc contains HTML comments ('<!--'). Remove placeholders, set status Draft/Review, "
                        "or add allow marker: <!-- lint-sot: allow-html-comments -->"
                    ),
                )
            )
    return errs


_MD_LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
_MD_REF_DEF_RE = re.compile(r"^[ \t]{0,3}\[[^\]]+\]:\s*(\S+)", re.MULTILINE)


_FENCE_OPEN_RE = re.compile(r"^[ \t]{0,3}((?:`{3,})|(?:~{3,}))")
_FENCE_CLOSE_RE = re.compile(r"^[ \t]{0,3}((?:`{3,})|(?:~{3,}))[ \t]*$")


def strip_fenced_code_blocks(text: str) -> str:
    out_lines: List[str] = []
    in_fence = False
    fence_char = ""
    fence_len = 0

    for line in text.splitlines(keepends=True):
        if not in_fence:
            m_open = _FENCE_OPEN_RE.match(line)
            if m_open:
                seq = m_open.group(1)
                in_fence = True
                fence_char = seq[0]
                fence_len = len(seq)
                continue
        else:
            m_close = _FENCE_CLOSE_RE.match(line)
            if m_close:
                seq = m_close.group(1)
                if seq[0] == fence_char and len(seq) >= fence_len:
                    in_fence = False
                    fence_char = ""
                    fence_len = 0
                    continue

        if not in_fence:
            out_lines.append(line)

    return "".join(out_lines)


def strip_inline_code_spans(text: str) -> str:
    out: List[str] = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch != "`":
            out.append(ch)
            i += 1
            continue

        j = i
        while j < n and text[j] == "`":
            j += 1
        delim = text[i:j]

        k = text.find(delim, j)
        if k == -1:
            out.append(delim)
            i = j
            continue

        i = k + len(delim)

    return "".join(out)


def parse_md_link_targets(text: str) -> List[str]:
    out: List[str] = []
    scrubbed = strip_inline_code_spans(strip_fenced_code_blocks(text))
    for m in _MD_LINK_RE.finditer(scrubbed):
        target = (m.group(1) or "").strip()
        if not target:
            continue
        out.append(target)
    for m in _MD_REF_DEF_RE.finditer(scrubbed):
        target = (m.group(1) or "").strip()
        if not target:
            continue
        out.append(target)
    return out


def is_external_or_fragment(target: str) -> bool:
    t = target.strip()
    if not t:
        return True
    if t.startswith("#"):
        return True
    if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", t):
        return True
    if t.startswith("mailto:"):
        return True
    return False


def normalize_target(target: str) -> str:
    t = target.strip()
    if t.startswith("<") and t.endswith(">"):
        t = t[1:-1].strip()
    if (t.startswith('"') and t.endswith('"')) or (
        t.startswith("'") and t.endswith("'")
    ):
        t = t[1:-1].strip()
    if " " in t or "\t" in t or "\n" in t:
        t = t.split()[0]
    t = t.split("#", 1)[0].split("?", 1)[0].strip()
    return t


def resolve_to_repo_relative(repo: str, file_abs: str, target: str) -> Optional[str]:
    t = normalize_target(target)
    if not t:
        return None

    if t.startswith("/"):
        abs_candidate = os.path.realpath(os.path.join(repo, t[1:]))
    else:
        file_dir = os.path.dirname(file_abs)
        abs_candidate = os.path.realpath(os.path.join(file_dir, t))
    repo_abs = os.path.realpath(repo)
    if not abs_candidate.startswith(repo_abs + os.sep) and abs_candidate != repo_abs:
        return None

    rel = os.path.relpath(abs_candidate, repo_abs).replace(os.sep, "/")
    return rel


def lint_relative_links(repo: str, rel_path: str, text: str) -> List[LintError]:
    errs: List[LintError] = []

    file_abs = os.path.join(repo, rel_path)
    for raw in parse_md_link_targets(text):
        if is_external_or_fragment(raw):
            continue
        rel = resolve_to_repo_relative(repo, file_abs, raw)
        if not rel:
            errs.append(
                LintError(
                    path=rel_path,
                    message=f"Unsafe or out-of-repo relative link target: {raw}",
                )
            )
            continue
        if not os.path.exists(os.path.join(repo, rel)):
            errs.append(
                LintError(
                    path=rel_path,
                    message=f"Broken relative link target (not found): {raw} -> {rel}",
                )
            )
    return errs


def lint_paths(repo: str, roots: List[str]) -> List[LintError]:
    errs: List[LintError] = []
    for root in roots:
        if not is_safe_repo_relative_root(root):
            errs.append(
                LintError(
                    path=str(root),
                    message="Root path must be repo-relative (no abs path, no '..')",
                )
            )
            continue
        root_abs = os.path.realpath(os.path.join(repo, root))
        repo_abs = os.path.realpath(repo)
        if not root_abs.startswith(repo_abs + os.sep) and root_abs != repo_abs:
            errs.append(
                LintError(
                    path=str(root),
                    message="Root path resolves outside repo",
                )
            )
            continue
        if not os.path.exists(root_abs):
            errs.append(LintError(path=root, message="Path does not exist"))
            continue
        for path_abs in iter_markdown_files(root_abs):
            rel_path = os.path.relpath(path_abs, repo).replace(os.sep, "/")
            text = read_text(path_abs)
            errs.extend(lint_placeholders(repo, rel_path, text))
            errs.extend(lint_relative_links(repo, rel_path, text))
    return errs


def main(argv: List[str]) -> int:
    ap = argparse.ArgumentParser(
        description="Lint Agentic-SDD SoT/docs for determinism and link integrity"
    )
    ap.add_argument(
        "paths",
        nargs="*",
        default=["docs"],
        help="Root paths to lint (repo-relative). Default: docs",
    )
    args = ap.parse_args(argv)

    repo = repo_root()
    errs = lint_paths(repo, list(args.paths))
    if errs:
        eprint("[lint-sot] BLOCKED")
        for err in errs:
            eprint(f"- {err.path}: {err.message}")
        eprint("\nNext actions:")
        eprint(
            "- Remove placeholders in Approved PRD/Epic, or change status to Draft/Review"
        )
        eprint("- Fix broken relative links (or switch to an https:// URL)")
        return 1
    print("[lint-sot] OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
