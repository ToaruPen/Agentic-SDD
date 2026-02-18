#!/usr/bin/env python3

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

from sot_refs import find_issue_ref, resolve_ref_to_repo_path


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def run(
    cmd: List[str],
    cwd: Optional[str] = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(  # noqa: S603
        cmd,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
    )


def git_repo_root() -> str:
    git_bin = shutil.which("git")
    if not git_bin:
        raise RuntimeError("git not found on PATH")
    try:
        p = run([git_bin, "rev-parse", "--show-toplevel"], check=True)
    except subprocess.CalledProcessError:
        raise RuntimeError("Not in a git repository; cannot locate repo root.")
    root = p.stdout.strip()
    if not root:
        raise RuntimeError("Failed to locate repo root via git.")
    return os.path.realpath(root)


def current_branch(repo_root: str) -> str:
    git_bin = shutil.which("git")
    if not git_bin:
        return ""
    try:
        p = run([git_bin, "branch", "--show-current"], cwd=repo_root)
    except subprocess.CalledProcessError:
        return ""
    return p.stdout.strip()


def extract_issue_number_from_branch(branch: str) -> Optional[str]:
    m = re.search(r"\bissue-(\d+)\b", branch)
    if not m:
        return None
    return m.group(1)


def is_placeholder_ref(ref: str) -> bool:
    r = ref.strip()
    if not r:
        return True
    if "<!--" in r:
        return True
    return False


def parse_issue_body_for_refs(body: str) -> Tuple[str, str]:
    prd_ref = find_issue_ref(body, "PRD")
    epic_ref = find_issue_ref(body, "Epic")

    if prd_ref is None or is_placeholder_ref(prd_ref):
        raise RuntimeError(
            "PRD reference is required in the Issue body (line like '- PRD: docs/prd/xxx.md')."
        )
    if epic_ref is None or is_placeholder_ref(epic_ref):
        raise RuntimeError(
            "Epic reference is required in the Issue body (line like '- Epic: docs/epics/xxx.md')."
        )
    return prd_ref.strip(), epic_ref.strip()


def resolve_issue_refs(
    repo_root: str,
    issue_number: Optional[str],
    gh_repo: str,
    issue_body_file: str,
) -> Tuple[str, str, Optional[str]]:
    # Returns: prd_path, epic_path, issue_url
    if issue_body_file:
        body = read_text(issue_body_file)
        prd_ref, epic_ref = parse_issue_body_for_refs(body)
        prd_path = resolve_ref_to_repo_path(repo_root, prd_ref)
        epic_path = resolve_ref_to_repo_path(repo_root, epic_ref)
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
        p = run(cmd, cwd=repo_root, check=True)
    except subprocess.CalledProcessError as exc:
        msg = exc.stderr.strip() or exc.stdout.strip() or str(exc)
        raise RuntimeError(f"Failed to fetch Issue via gh: {msg}")

    try:
        data = json.loads(p.stdout)
    except Exception as exc:  # noqa: BLE001
        raise RuntimeError(f"Invalid JSON from gh issue view: {exc}")

    body = str(data.get("body") or "")
    issue_url = str(data.get("url") or "")

    prd_ref, epic_ref = parse_issue_body_for_refs(body)
    prd_path = resolve_ref_to_repo_path(repo_root, prd_ref)
    epic_path = resolve_ref_to_repo_path(repo_root, epic_ref)
    return prd_path, epic_path, issue_url or None


def find_epic_by_prd(repo_root: str, prd_path: str) -> str:
    epics_root = os.path.join(repo_root, "docs", "epics")
    candidates: List[str] = []

    if not os.path.isdir(epics_root):
        raise RuntimeError("docs/epics/ not found; cannot auto-resolve Epic.")

    for root, _dirs, files in os.walk(epics_root):
        for name in files:
            if not name.endswith(".md"):
                continue
            rel = os.path.relpath(os.path.join(root, name), repo_root).replace(
                os.sep, "/"
            )
            text = read_text(os.path.join(repo_root, rel))
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
    abs_path = os.path.join(repo_root, rel_path)
    if not os.path.isfile(abs_path):
        raise RuntimeError(f"{label} file not found: {rel_path}")


def detect_pr_number(repo_root: str, gh_repo: str) -> Optional[str]:
    if not shutil_which("gh"):
        return None
    cmd = ["gh"]
    if gh_repo:
        cmd += ["-R", gh_repo]
    cmd += ["pr", "view", "--json", "number"]
    try:
        p = run(cmd, cwd=repo_root, check=True)
    except subprocess.CalledProcessError:
        return None
    try:
        data = json.loads(p.stdout)
    except Exception:
        return None
    n = data.get("number")
    if isinstance(n, int) and n > 0:
        return str(n)
    return None


def shutil_which(cmd: str) -> Optional[str]:
    path = os.environ.get("PATH", "")
    for d in path.split(os.pathsep):
        p = os.path.join(d, cmd)
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def git_has_diff(repo_root: str, args: List[str]) -> bool:
    git_bin = shutil.which("git")
    if not git_bin:
        raise RuntimeError("git not found on PATH")
    cp = run(
        [git_bin, "diff", "--quiet"] + args,
        cwd=repo_root,
        check=False,
    )
    return cp.returncode != 0


def git_diff_text(repo_root: str, args: List[str]) -> str:
    git_bin = shutil.which("git")
    if not git_bin:
        raise RuntimeError("git not found on PATH")
    p = run([git_bin, "diff", "--no-color"] + args, cwd=repo_root, check=True)
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
    pr_number: Optional[str],
    diff_mode: str,
    base_ref: str,
) -> Tuple[str, str, Optional[str]]:
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
            p = run(cmd, cwd=repo_root, check=True)
        except subprocess.CalledProcessError as exc:
            msg = exc.stderr.strip() or exc.stdout.strip() or str(exc)
            raise RuntimeError(f"Failed to fetch PR diff via gh: {msg}")
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
            os.path.realpath(args.repo_root) if args.repo_root else git_repo_root()
        )
    except Exception as exc:  # noqa: BLE001
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

    prd_path = ""
    epic_path = ""
    issue_url: Optional[str] = None

    try:
        if args.prd:
            prd_path = resolve_ref_to_repo_path(repo_root, args.prd)
        if args.epic:
            epic_path = resolve_ref_to_repo_path(repo_root, args.epic)

        if not prd_path or not epic_path:
            # Prefer Issue refs when available.
            if issue_number or issue_body_file:
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
            prd_root = os.path.join(repo_root, "docs", "prd")
            prds = []
            if os.path.isdir(prd_root):
                for name in os.listdir(prd_root):
                    if name.endswith(".md"):
                        prds.append(f"docs/prd/{name}")
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
            os.path.realpath(args.output_root)
            if args.output_root
            else os.path.join(repo_root, ".agentic-sdd", "sync-docs")
        )
        out_dir = os.path.join(output_root, scope_id, run_id)
        out_diff = os.path.join(out_dir, "diff.patch")
        out_json = os.path.join(out_dir, "inputs.json")

        out: Dict[str, Any] = {
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
            "diff_path": os.path.relpath(out_diff, repo_root).replace(os.sep, "/"),
            "inputs_path": os.path.relpath(out_json, repo_root).replace(os.sep, "/"),
        }

        if not args.dry_run:
            os.makedirs(out_dir, exist_ok=True)
            with open(out_diff, "w", encoding="utf-8") as fh:
                fh.write(diff_text)
                if not diff_text.endswith("\n"):
                    fh.write("\n")
            with open(out_json, "w", encoding="utf-8") as fh:
                json.dump(out, fh, ensure_ascii=True, indent=2)
                fh.write("\n")

        json.dump(out, sys.stdout, ensure_ascii=True, indent=2)
        sys.stdout.write("\n")
        return 0
    except Exception as exc:  # noqa: BLE001
        eprint(str(exc))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
