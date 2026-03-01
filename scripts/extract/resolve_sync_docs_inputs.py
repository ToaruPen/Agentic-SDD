#!/usr/bin/env python3

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


import argparse
import json
import os
import re
import shutil
import subprocess
from datetime import datetime
from typing import Any

from _lib.sot_refs import find_issue_ref, resolve_ref_to_repo_path
from _lib.subprocess_utils import run_cmd

GH_CMD_TIMEOUT = 30


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def read_text(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")


def run(
    cmd: list[str],
    cwd: str | None = None,
    check: bool = True,
    timeout: int | None = None,
) -> subprocess.CompletedProcess[str]:
    return run_cmd(cmd, cwd=cwd, check=check, timeout=timeout)


def _format_path(path: str, repo_root: str) -> str:
    try:
        return str(Path(path).relative_to(repo_root)).replace(os.sep, "/")
    except ValueError:
        return str(Path(path)).replace(os.sep, "/")


def git_repo_root() -> str:
    git_bin = shutil.which("git")
    if not git_bin:
        raise RuntimeError("git not found on PATH")
    try:
        p = run([git_bin, "rev-parse", "--show-toplevel"], check=True)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError("Not in a git repository; cannot locate repo root.") from exc
    root = p.stdout.strip()
    if not root:
        raise RuntimeError("Failed to locate repo root via git.")
    return str(Path(root).resolve())


def current_branch(repo_root: str) -> str:
    git_bin = shutil.which("git")
    if not git_bin:
        return ""
    try:
        p = run([git_bin, "branch", "--show-current"], cwd=repo_root)
    except subprocess.CalledProcessError:
        return ""
    return p.stdout.strip()


def extract_issue_number_from_branch(branch: str) -> str | None:
    m = re.search(r"\bissue-(\d+)\b", branch)
    if not m:
        return None
    return m.group(1)


def is_placeholder_ref(ref: str) -> bool:
    r = ref.strip()
    if not r:
        return True
    return "<!--" in r


def parse_issue_body_for_refs(body: str) -> tuple[str | None, str | None]:
    prd_ref = find_issue_ref(body, "PRD")
    epic_ref = find_issue_ref(body, "Epic")

    resolved_prd = None
    resolved_epic = None
    if prd_ref is not None and not is_placeholder_ref(prd_ref):
        resolved_prd = prd_ref.strip()
    if epic_ref is not None and not is_placeholder_ref(epic_ref):
        resolved_epic = epic_ref.strip()
    return resolved_prd, resolved_epic


def resolve_issue_refs(
    repo_root: str,
    issue_number: str | None,
    gh_repo: str,
    issue_body_file: str,
) -> tuple[str | None, str | None, str | None]:
    # Returns: prd_path, epic_path, issue_url
    if issue_body_file:
        body = read_text(issue_body_file)
        prd_ref, epic_ref = parse_issue_body_for_refs(body)
        prd_path = (
            resolve_ref_to_repo_path(repo_root, prd_ref)
            if prd_ref is not None
            else None
        )
        epic_path = (
            resolve_ref_to_repo_path(repo_root, epic_ref)
            if epic_ref is not None
            else None
        )
        return prd_path, epic_path, None

    if not issue_number:
        raise RuntimeError(
            "Issue number is required when GH_ISSUE_BODY_FILE is not set."
        )

    cmd = ["gh"]
    if gh_repo:
        cmd += ["-R", gh_repo]
    cmd += ["issue", "view", issue_number, "--json", "body,url"]
    try:
        p = run(cmd, cwd=repo_root, check=True, timeout=GH_CMD_TIMEOUT)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        stderr = getattr(exc, "stderr", "") or ""
        stdout = getattr(exc, "stdout", "") or ""
        msg = stderr.strip() or stdout.strip() or str(exc)
        raise RuntimeError(f"Failed to fetch Issue via gh: {msg}") from exc

    try:
        data = json.loads(p.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Invalid JSON from gh issue view: {exc}") from exc

    body = str(data.get("body") or "")
    issue_url = str(data.get("url") or "")

    prd_ref, epic_ref = parse_issue_body_for_refs(body)
    prd_path = (
        resolve_ref_to_repo_path(repo_root, prd_ref) if prd_ref is not None else None
    )
    epic_path = (
        resolve_ref_to_repo_path(repo_root, epic_ref) if epic_ref is not None else None
    )
    return prd_path, epic_path, issue_url or None


def find_epic_by_prd(repo_root: str, prd_path: str) -> str:
    epics_root = Path(repo_root) / "docs" / "epics"
    candidates: list[str] = []

    if not epics_root.is_dir():
        raise RuntimeError("docs/epics/ not found; cannot auto-resolve Epic.")

    for entry in epics_root.rglob("*.md"):
        rel = str(entry.relative_to(repo_root)).replace(os.sep, "/")
        text = read_text(str(Path(repo_root) / rel))
        for line in text.splitlines():
            if "参照PRD" not in line:
                continue
            m = re.search(r"参照PRD\s*:\s*(.+)$", line)
            if not m:
                continue
            ref = m.group(1).strip()
            if is_placeholder_ref(ref):
                continue
            resolved = None
            try:
                resolved = resolve_ref_to_repo_path(repo_root, ref)
            except ValueError:
                resolved = None
            if resolved is None:
                continue
            if resolved == prd_path:
                candidates.append(rel)
                break

    if len(candidates) == 1:
        return candidates[0]
    if len(candidates) == 0:
        raise RuntimeError(
            "Epic could not be resolved from PRD. Add '- Epic: ...' to the Issue body or set --epic."
        )
    raise RuntimeError(
        "Multiple Epics reference the same PRD; specify --epic explicitly: "
        + ", ".join(candidates)
    )


def ensure_file_exists(repo_root: str, rel_path: str, label: str) -> None:
    abs_path = Path(repo_root) / rel_path
    if not abs_path.is_file():
        raise RuntimeError(f"{label} file not found: {rel_path}")


def detect_pr_number(repo_root: str, gh_repo: str) -> str | None:
    if not shutil_which("gh"):
        return None
    cmd = ["gh"]
    if gh_repo:
        cmd += ["-R", gh_repo]
    cmd += ["pr", "view", "--json", "number"]
    try:
        p = run(cmd, cwd=repo_root, check=True, timeout=GH_CMD_TIMEOUT)
    except subprocess.CalledProcessError:
        return None
    try:
        data = json.loads(p.stdout)
    except json.JSONDecodeError:
        return None
    n = data.get("number")
    if isinstance(n, int) and n > 0:
        return str(n)
    return None


def shutil_which(cmd: str) -> str | None:
    path_env = os.environ.get("PATH", "")
    for d in path_env.split(os.pathsep):
        p = Path(d) / cmd
        if p.is_file() and os.access(str(p), os.X_OK):
            return str(p)
    return None


def git_has_diff(repo_root: str, args: list[str]) -> bool:
    git_bin = shutil.which("git")
    if not git_bin:
        raise RuntimeError("git not found on PATH")
    cp = run(
        [git_bin, "diff", "--quiet", *args],
        cwd=repo_root,
        check=False,
    )
    return cp.returncode != 0


def git_diff_text(repo_root: str, args: list[str]) -> str:
    git_bin = shutil.which("git")
    if not git_bin:
        raise RuntimeError("git not found on PATH")
    p = run([git_bin, "diff", "--no-color", *args], cwd=repo_root, check=True)
    return p.stdout


def git_ref_exists(repo_root: str, ref: str) -> bool:
    git_bin = shutil.which("git")
    if not git_bin:
        return False
    cp = run(
        [git_bin, "rev-parse", "--verify", ref],
        cwd=repo_root,
        check=False,
    )
    return cp.returncode == 0


def resolve_diff(
    repo_root: str,
    gh_repo: str,
    pr_number: str | None,
    diff_mode: str,
    base_ref: str,
) -> tuple[str, str, str | None]:
    # Returns: diff_source, diff_text, detail
    # detail: base ref for range or pr number for pr
    if diff_mode == "pr":
        if not pr_number:
            raise RuntimeError("diff_mode=pr requires a PR number.")
        if not shutil_which("gh"):
            raise RuntimeError("gh is required for PR diff but was not found on PATH.")
        cmd = ["gh"]
        if gh_repo:
            cmd += ["-R", gh_repo]
        cmd += ["pr", "diff", pr_number, "--patch"]
        try:
            p = run(cmd, cwd=repo_root, check=True, timeout=GH_CMD_TIMEOUT)
        except subprocess.CalledProcessError as exc:
            msg = exc.stderr.strip() or exc.stdout.strip() or str(exc)
            raise RuntimeError(f"Failed to fetch PR diff via gh: {msg}") from exc
        if not p.stdout.strip():
            raise RuntimeError("PR diff is empty.")
        return "pr", p.stdout, pr_number

    has_staged = git_has_diff(repo_root, ["--cached"])
    has_worktree = git_has_diff(repo_root, [])

    if diff_mode == "staged":
        if not has_staged:
            raise RuntimeError("Diff is empty (staged).")
        return "staged", git_diff_text(repo_root, ["--cached"]), None

    if diff_mode == "worktree":
        if not has_worktree:
            raise RuntimeError("Diff is empty (worktree).")
        return "worktree", git_diff_text(repo_root, []), None

    if diff_mode == "auto" or diff_mode == "":
        if has_staged and has_worktree:
            raise RuntimeError(
                "Both staged and worktree diffs are non-empty. Set --diff-mode staged or worktree."
            )
        if has_staged:
            return "staged", git_diff_text(repo_root, ["--cached"]), None
        if has_worktree:
            return "worktree", git_diff_text(repo_root, []), None
        # Fallback: range diff
        diff_mode = "range"

    if diff_mode != "range":
        raise RuntimeError("Invalid diff mode (use auto|staged|worktree|range|pr).")

    base = base_ref
    if not git_ref_exists(repo_root, base):
        if base == "origin/main" and git_ref_exists(repo_root, "main"):
            base = "main"
        else:
            raise RuntimeError(f"Base ref not found for range diff: {base}")

    text = git_diff_text(repo_root, [f"{base}...HEAD"])
    if not text.strip():
        raise RuntimeError(f"Diff is empty (range: {base}...HEAD).")
    return "range", text, base


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Resolve PRD/Epic and diff source deterministically for /sync-docs."
    )
    parser.add_argument("--repo-root", default="", help="Repo root (default: git root)")
    parser.add_argument("--prd", default="", help="PRD reference (path or GitHub URL)")
    parser.add_argument(
        "--epic", default="", help="Epic reference (path or GitHub URL)"
    )
    parser.add_argument("--issue", default="", help="Issue number (default: infer)")
    parser.add_argument("--pr", default="", help="PR number (default: detect)")
    parser.add_argument(
        "--diff-mode",
        default="auto",
        help="auto|staged|worktree|range|pr (default: auto; uses pr if detected)",
    )
    parser.add_argument(
        "--base-ref",
        default="origin/main",
        help="Base ref for range diff (default: origin/main; fallback: main)",
    )
    parser.add_argument(
        "--output-root",
        default="",
        help="Output root (default: <repo>/.agentic-sdd/sync-docs)",
    )
    parser.add_argument("--run-id", default="", help="Run id (default: timestamp)")
    parser.add_argument("--dry-run", action="store_true", help="Do not write files")
    args = parser.parse_args()

    try:
        repo_root = (
            str(Path(args.repo_root).resolve()) if args.repo_root else git_repo_root()
        )

    except RuntimeError as exc:
        eprint(str(exc))
        return 1

    gh_repo = os.environ.get("GH_REPO", "").strip()
    issue_body_file = os.environ.get("GH_ISSUE_BODY_FILE", "").strip()

    issue_number = (args.issue or os.environ.get("GH_ISSUE", "")).strip()
    if not issue_number:
        issue_number = (
            extract_issue_number_from_branch(current_branch(repo_root) or "") or ""
        )

    pr_number = (args.pr or os.environ.get("GH_PR", "")).strip() or None
    if pr_number is None:
        pr_number = detect_pr_number(repo_root, gh_repo)

    diff_mode = (args.diff_mode or "auto").strip()
    if pr_number is not None and diff_mode == "auto":
        diff_mode = "pr"

    prd_path: str | None = None
    epic_path: str | None = None
    issue_url: str | None = None

    try:
        if args.prd:
            prd_path = resolve_ref_to_repo_path(repo_root, args.prd)
        if args.epic:
            epic_path = resolve_ref_to_repo_path(repo_root, args.epic)

        if (not prd_path or not epic_path) and (issue_number or issue_body_file):
            # Prefer Issue refs when available.
            iprd, iepic, url = resolve_issue_refs(
                repo_root=repo_root,
                issue_number=issue_number or None,
                gh_repo=gh_repo,
                issue_body_file=issue_body_file,
            )
            issue_url = url
            if not prd_path:
                prd_path = iprd
            if not epic_path:
                epic_path = iepic

        if not prd_path:
            prd_root = Path(repo_root) / "docs" / "prd"
            prds: list[str] = []
            if prd_root.is_dir():
                prds.extend(
                    f"docs/prd/{entry.name}"
                    for entry in prd_root.iterdir()
                    if entry.name.endswith(".md") and entry.name != "_template.md"
                )

            if len(prds) == 1:
                prd_path = prds[0]
            elif len(prds) == 0:
                raise RuntimeError(
                    "PRD could not be resolved (docs/prd/*.md not found)."
                )
            else:
                raise RuntimeError(
                    "Multiple PRDs exist; specify --prd or add PRD/Epic references to the Issue: "
                    + ", ".join(sorted(prds))
                )

        if not epic_path:
            epic_path = find_epic_by_prd(repo_root, prd_path)

        if prd_path is None:
            raise RuntimeError("PRD could not be resolved.")
        if epic_path is None:
            raise RuntimeError("Epic could not be resolved.")

        ensure_file_exists(repo_root, prd_path, "PRD")
        ensure_file_exists(repo_root, epic_path, "Epic")

        diff_source, diff_text, diff_detail = resolve_diff(
            repo_root=repo_root,
            gh_repo=gh_repo,
            pr_number=pr_number,
            diff_mode=diff_mode,
            base_ref=args.base_ref,
        )

        scope_id = ""
        if issue_number:
            scope_id = f"issue-{issue_number}"
        elif pr_number:
            scope_id = f"pr-{pr_number}"
        else:
            b = current_branch(repo_root) or "unknown"
            safe = re.sub(r"[^A-Za-z0-9._-]+", "_", b).strip("_")
            scope_id = f"branch-{safe or 'unknown'}"

        run_id = args.run_id.strip() if args.run_id else ""
        if not run_id:
            run_id = datetime.now().strftime("%Y%m%d_%H%M%S")

        output_root = (
            str(Path(args.output_root).resolve())
            if args.output_root
            else str(Path(repo_root) / ".agentic-sdd" / "sync-docs")
        )
        out_dir_path = Path(output_root) / scope_id / run_id
        out_diff = str(out_dir_path / "diff.patch")
        out_json = str(out_dir_path / "inputs.json")

        out: dict[str, Any] = {
            "repo_root": repo_root,
            "scope_id": scope_id,
            "run_id": run_id,
            "prd_path": prd_path,
            "epic_path": epic_path,
            "issue_number": issue_number or None,
            "issue_url": issue_url,
            "pr_number": pr_number,
            "diff_source": diff_source,
            "diff_detail": diff_detail,
            "diff_path": _format_path(out_diff, repo_root),
            "inputs_path": _format_path(out_json, repo_root),
        }

        if not args.dry_run:
            out_dir_path.mkdir(parents=True, exist_ok=True)
            patch_text = diff_text if diff_text.endswith("\n") else diff_text + "\n"
            (out_dir_path / "diff.patch").write_text(patch_text, encoding="utf-8")
            (out_dir_path / "inputs.json").write_text(
                json.dumps(out, ensure_ascii=True, indent=2) + "\n", encoding="utf-8"
            )

        json.dump(out, sys.stdout, ensure_ascii=True, indent=2)
        sys.stdout.write("\n")
        return 0
    except (json.JSONDecodeError, OSError, RuntimeError, ValueError) as exc:
        eprint(str(exc))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
