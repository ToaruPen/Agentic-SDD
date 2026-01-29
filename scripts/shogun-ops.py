#!/usr/bin/env python3

import argparse
import datetime
import os
import subprocess
import sys
import tempfile
from typing import Any, Dict, List, Optional, Tuple

import yaml


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def run_git(args: List[str]) -> str:
    try:
        out = subprocess.check_output(["git", *args], stderr=subprocess.STDOUT)
    except FileNotFoundError:
        raise RuntimeError("git not found")
    except subprocess.CalledProcessError as exc:
        msg = exc.output.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"git command failed: git {' '.join(args)}\n{msg}")
    return out.decode("utf-8", errors="replace").strip()


def utc_now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def resolve_git_dirs() -> Tuple[str, str, str]:
    abs_git_dir = run_git(["rev-parse", "--absolute-git-dir"])
    toplevel = run_git(["rev-parse", "--show-toplevel"])

    common_abs = ""
    try:
        common_abs = run_git(["rev-parse", "--path-format=absolute", "--git-common-dir"])
    except RuntimeError:
        common_abs = ""

    if not common_abs:
        common_dir = run_git(["rev-parse", "--git-common-dir"])
        if common_dir in {".git", "./.git"}:
            common_abs = abs_git_dir
        elif os.path.isabs(common_dir):
            common_abs = os.path.realpath(common_dir)
        else:
            common_abs = os.path.realpath(os.path.join(abs_git_dir, common_dir))
    else:
        common_abs = os.path.realpath(common_abs)

    return abs_git_dir, common_abs, toplevel


def ops_root_from_common_dir(common_abs: str) -> str:
    return os.path.join(common_abs, "agentic-sdd-ops")


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def read_yaml_file(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    if not isinstance(data, dict):
        raise RuntimeError(f"YAML must be a mapping: {path}")
    return data


def atomic_write_bytes(path: str, data: bytes) -> None:
    parent = os.path.dirname(path)
    ensure_dir(parent)
    fd, tmp_path = tempfile.mkstemp(prefix=".tmp.", dir=parent)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp_path, path)
    finally:
        try:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
        except OSError:
            pass


def atomic_write_text(path: str, text: str) -> None:
    atomic_write_bytes(path, text.encode("utf-8"))


def atomic_write_yaml(path: str, obj: Dict[str, Any]) -> None:
    data = yaml.safe_dump(
        obj,
        allow_unicode=True,
        sort_keys=True,
        default_flow_style=False,
        width=120,
    )
    atomic_write_text(path, data)


def default_config_yaml() -> Dict[str, Any]:
    return {
        "version": 1,
        "policy": {
            "parallel": {"enabled": True, "max_workers": 3, "require_parallel_ok_label": True},
            "impl_mode": {"default": "impl", "force_tdd_labels": ["tdd", "bug", "high-risk"]},
            "checkin": {"required_on_phase_change": True},
        },
        "workers": [{"id": "ashigaru1"}, {"id": "ashigaru2"}, {"id": "ashigaru3"}],
    }


def default_state_yaml() -> Dict[str, Any]:
    return {
        "version": 1,
        "updated_at": utc_now_iso(),
        "sot": {"prd": None, "epic": None},
        "issues": {},
        "blocked": [],
        "recent_checkins": [],
    }


def render_dashboard_md(state: Dict[str, Any]) -> str:
    updated = state.get("updated_at") or utc_now_iso()
    issues = state.get("issues") or {}
    if not isinstance(issues, dict):
        issues = {}

    total = len(issues)
    counts = {"done": 0, "in_progress": 0, "blocked": 0, "backlog": 0}
    for _k, v in issues.items():
        if not isinstance(v, dict):
            continue
        phase = str(v.get("phase") or "backlog")
        if phase == "done":
            counts["done"] += 1
        elif phase == "blocked":
            counts["blocked"] += 1
        elif phase in {"implementing", "reviewing", "estimating"}:
            counts["in_progress"] += 1
        else:
            counts["backlog"] += 1

    blocked_list = state.get("blocked") or []
    if not isinstance(blocked_list, list):
        blocked_list = []

    recent = state.get("recent_checkins") or []
    if not isinstance(recent, list):
        recent = []

    lines: List[str] = []
    lines.append("# Agentic-SDD Ops Dashboard")
    lines.append(f"Updated: {updated}")
    lines.append("")
    lines.append("## Summary")
    lines.append(
        f"- Issues: {total} (Done {counts['done']} / In Progress {counts['in_progress']} / Blocked {counts['blocked']} / Backlog {counts['backlog']})"
    )
    lines.append("")
    lines.append("## Blocked / Needs Decision")
    if blocked_list:
        for item in blocked_list[:20]:
            if not isinstance(item, dict):
                continue
            issue = item.get("issue")
            reason = item.get("reason") or ""
            lines.append(f"- #{issue} {reason}".rstrip())
    else:
        lines.append("- (none)")
    lines.append("")
    lines.append("## Recent Check-ins")
    if recent:
        for item in recent[:20]:
            if not isinstance(item, dict):
                continue
            at = item.get("timestamp") or item.get("at") or ""
            worker = item.get("worker") or ""
            issue = item.get("issue") or ""
            summary = item.get("summary") or ""
            lines.append(f"- {at} {worker} #{issue}: {summary}".rstrip())
    else:
        lines.append("- (none)")
    lines.append("")
    return "\n".join(lines)


def ensure_ops_layout(common_abs: str) -> Tuple[str, str, str]:
    root = ops_root_from_common_dir(common_abs)
    ensure_dir(root)
    ensure_dir(os.path.join(root, "queue", "orders"))
    ensure_dir(os.path.join(root, "queue", "checkins"))
    ensure_dir(os.path.join(root, "queue", "decisions"))
    ensure_dir(os.path.join(root, "archive", "checkins"))
    ensure_dir(os.path.join(root, "locks"))

    config_path = os.path.join(root, "config.yaml")
    state_path = os.path.join(root, "state.yaml")
    dashboard_path = os.path.join(root, "dashboard.md")

    if not os.path.exists(config_path):
        atomic_write_yaml(config_path, default_config_yaml())
    if not os.path.exists(state_path):
        atomic_write_yaml(state_path, default_state_yaml())

    state = read_yaml_file(state_path)
    if "updated_at" not in state:
        state["updated_at"] = utc_now_iso()
    dash = render_dashboard_md(state)
    atomic_write_text(dashboard_path, dash)

    return root, state_path, dashboard_path


class LockFile:
    def __init__(self, path: str, fd: int):
        self.path = path
        self.fd = fd

    def close(self) -> None:
        try:
            os.close(self.fd)
        finally:
            self.fd = -1

    def release(self) -> None:
        try:
            self.close()
        finally:
            try:
                os.unlink(self.path)
            except FileNotFoundError:
                pass


def acquire_lock(lock_path: str) -> LockFile:
    ensure_dir(os.path.dirname(lock_path))
    try:
        fd = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
    except FileExistsError:
        raise RuntimeError(f"lock already exists (single-writer): {lock_path}")
    payload = f"pid={os.getpid()}\ncreated_at={utc_now_iso()}\n"
    os.write(fd, payload.encode("utf-8"))
    return LockFile(lock_path, fd)


def list_checkin_paths(ops_root: str) -> List[str]:
    base = os.path.join(ops_root, "queue", "checkins")
    out: List[str] = []
    if not os.path.isdir(base):
        return out
    for worker in sorted(os.listdir(base)):
        worker_dir = os.path.join(base, worker)
        if not os.path.isdir(worker_dir):
            continue
        for name in sorted(os.listdir(worker_dir)):
            if not name.endswith(".yaml"):
                continue
            out.append(os.path.join(worker_dir, name))
    return out


def ensure_issue_entry(state: Dict[str, Any], issue: int) -> Dict[str, Any]:
    issues = state.setdefault("issues", {})
    if not isinstance(issues, dict):
        issues = {}
        state["issues"] = issues
    key = str(issue)
    entry = issues.get(key)
    if not isinstance(entry, dict):
        entry = {}
        issues[key] = entry
    return entry


def record_recent_checkin(state: Dict[str, Any], checkin: Dict[str, Any]) -> None:
    recent = state.get("recent_checkins")
    if not isinstance(recent, list):
        recent = []
        state["recent_checkins"] = recent
    recent.insert(
        0,
        {
            "timestamp": checkin.get("timestamp") or "",
            "worker": checkin.get("worker") or "",
            "issue": checkin.get("issue") or "",
            "summary": checkin.get("summary") or "",
        },
    )
    # trim
    del recent[20:]

def unique_path_with_suffix(path: str) -> str:
    if not os.path.exists(path):
        return path
    base, ext = os.path.splitext(path)
    suffix = 1
    while True:
        candidate = f"{base}-{suffix:03d}{ext}"
        if not os.path.exists(candidate):
            return candidate
        suffix += 1


def cmd_collect(_args: argparse.Namespace) -> int:
    _abs_git_dir, common_abs, _toplevel = resolve_git_dirs()
    ops_root, state_path, dashboard_path = ensure_ops_layout(common_abs)

    lock_path = os.path.join(ops_root, "locks", "collect.lock")
    lock = acquire_lock(lock_path)
    try:
        checkin_paths = list_checkin_paths(ops_root)
        if not checkin_paths:
            return 0

        state = read_yaml_file(state_path)
        processed = 0

        for path in checkin_paths:
            checkin = read_yaml_file(path)
            issue_raw = checkin.get("issue")
            try:
                issue = int(issue_raw)
            except Exception:
                raise RuntimeError(f"invalid checkin issue: {path}")

            entry = ensure_issue_entry(state, issue)
            entry["assigned_to"] = checkin.get("worker") or entry.get("assigned_to")
            entry["phase"] = checkin.get("phase") or entry.get("phase") or "backlog"
            progress = checkin.get("progress_percent")
            if progress is None:
                progress = entry.get("progress_percent")
            if progress is None:
                progress = 0
            entry["progress_percent"] = progress
            entry["last_checkin"] = {
                "at": checkin.get("timestamp") or "",
                "id": checkin.get("checkin_id") or "",
                "summary": checkin.get("summary") or "",
            }

            record_recent_checkin(state, checkin)

            # archive (append-only queue semantics; remove from queue after processing)
            worker = str(checkin.get("worker") or "unknown")
            archive_dir = os.path.join(ops_root, "archive", "checkins", worker)
            ensure_dir(archive_dir)
            archive_path = os.path.join(archive_dir, os.path.basename(path))
            archive_path = unique_path_with_suffix(archive_path)
            os.replace(path, archive_path)
            processed += 1

        state["updated_at"] = utc_now_iso()
        atomic_write_yaml(state_path, state)

        dash = render_dashboard_md(state)
        atomic_write_text(dashboard_path, dash)

        sys.stdout.write(f"processed={processed}\n")
        return 0
    finally:
        lock.release()


def slugify(s: str) -> str:
    out: List[str] = []
    prev_dash = False
    for ch in s.lower():
        ok = ("a" <= ch <= "z") or ("0" <= ch <= "9")
        if ok:
            out.append(ch)
            prev_dash = False
        else:
            if not prev_dash:
                out.append("-")
                prev_dash = True
    slug = "".join(out).strip("-")
    slug = "-".join([p for p in slug.split("-") if p])
    return slug or "issue"


def detect_gh_repo_from_origin(toplevel: str) -> str:
    try:
        url = subprocess.check_output(
            ["git", "-C", toplevel, "remote", "get-url", "origin"], stderr=subprocess.STDOUT
        ).decode("utf-8", errors="replace").strip()
    except subprocess.CalledProcessError as exc:
        msg = exc.output.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"failed to get origin remote URL (set --gh-repo): {msg}")

    if url.startswith("https://github.com/") or url.startswith("http://github.com/"):
        path = url.split("github.com/", 1)[1]
        if path.endswith(".git"):
            path = path[: -len(".git")]
        parts = [p for p in path.split("/") if p]
        if len(parts) >= 2:
            return f"{parts[0]}/{parts[1]}"
    if url.startswith("git@github.com:"):
        path = url.split("git@github.com:", 1)[1]
        if path.endswith(".git"):
            path = path[: -len(".git")]
        parts = [p for p in path.split("/") if p]
        if len(parts) >= 2:
            return f"{parts[0]}/{parts[1]}"
    raise RuntimeError(f"unsupported origin URL format (set --gh-repo): {url}")


def gh_json(cmd: List[str]) -> Any:
    try:
        out = subprocess.check_output(["gh", *cmd], stderr=subprocess.STDOUT)
    except FileNotFoundError:
        raise RuntimeError("gh not found")
    except subprocess.CalledProcessError as exc:
        msg = exc.output.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"gh command failed: gh {' '.join(cmd)}\n{msg}")
    try:
        # gh outputs JSON; yaml.safe_load can parse JSON too.
        return yaml.safe_load(out.decode("utf-8", errors="replace"))
    except Exception:
        raise RuntimeError("failed to parse gh JSON output")


def read_ops_config(ops_root: str) -> Dict[str, Any]:
    cfg_path = os.path.join(ops_root, "config.yaml")
    if not os.path.exists(cfg_path):
        return default_config_yaml()
    return read_yaml_file(cfg_path)


def select_targets(gh_repo: str, config: Dict[str, Any], targets: List[int]) -> List[Dict[str, Any]]:
    if targets:
        selected: List[Dict[str, Any]] = []
        for n in targets:
            obj = gh_json(["-R", gh_repo, "issue", "view", str(n), "--json", "number,title,labels"])
            if not isinstance(obj, dict):
                raise RuntimeError("gh issue view must return an object")
            selected.append(obj)
        return selected

    policy = (config.get("policy") or {}).get("parallel") or {}
    require_label = bool(policy.get("require_parallel_ok_label", True))

    items = gh_json(["-R", gh_repo, "issue", "list", "--state", "open", "--limit", "100", "--json", "number,title,labels"])
    if not isinstance(items, list):
        raise RuntimeError("gh issue list must return an array")

    out: List[Dict[str, Any]] = []
    for it in items:
        if not isinstance(it, dict):
            continue
        labels = it.get("labels") or []
        label_names = set()
        if isinstance(labels, list):
            for l in labels:
                if isinstance(l, dict):
                    name = l.get("name")
                    if name:
                        label_names.add(str(name))
        if require_label and "parallel-ok" not in label_names:
            continue
        out.append(it)
    return out


def run_worktree_check(toplevel: str, gh_repo: str, issues: List[int]) -> Tuple[int, str]:
    cmd = [os.path.join(toplevel, "scripts", "worktree.sh"), "check", "--gh-repo", gh_repo]
    for n in issues:
        cmd.extend(["--issue", str(n)])
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
        return 0, out.decode("utf-8", errors="replace")
    except subprocess.CalledProcessError as exc:
        msg = exc.output.decode("utf-8", errors="replace")
        return int(exc.returncode), msg


def extract_allowed_files(toplevel: str, gh_repo: str, issue: int) -> List[str]:
    extractor = os.path.join(toplevel, "scripts", "extract-issue-files.py")
    cmd = ["python3", extractor, "--repo-root", toplevel, "--issue", str(issue), "--gh-repo", gh_repo, "--mode", "section"]
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode("utf-8", errors="replace")
    except subprocess.CalledProcessError as exc:
        msg = exc.output.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"failed to extract allowed_files for issue {issue}:\n{msg}")
    files = [ln.strip() for ln in out.splitlines() if ln.strip()]
    return files


def write_decision(ops_root: str, decision: Dict[str, Any]) -> str:
    global _DECISION_SEQ
    decisions_dir = os.path.join(ops_root, "queue", "decisions")
    ensure_dir(decisions_dir)
    ts = utc_now_compact().replace("Z", "")
    issue_part = str(decision.get("issue") or "global")
    base_id = decision.get("decision_id") or f"DEC-{ts}-{issue_part}"
    while True:
        _DECISION_SEQ += 1
        decision_id = base_id if decision.get("decision_id") else f"{base_id}-{_DECISION_SEQ:03d}"
        path = os.path.join(decisions_dir, f"{decision_id}.yaml")
        if not os.path.exists(path):
            decision["decision_id"] = decision_id
            atomic_write_yaml(path, decision)
            return path


_DECISION_SEQ = 0


def cmd_supervise(args: argparse.Namespace) -> int:
    if not args.once:
        raise RuntimeError("--once is required (only once-mode is implemented)")

    _abs_git_dir, common_abs, toplevel = resolve_git_dirs()
    ops_root, state_path, dashboard_path = ensure_ops_layout(common_abs)
    config = read_ops_config(ops_root)

    gh_repo = args.gh_repo or detect_gh_repo_from_origin(toplevel)
    candidates = select_targets(gh_repo, config, args.targets or [])
    if not candidates:
        sys.stdout.write("no_targets\n")
        return 0

    policy = (config.get("policy") or {}).get("parallel") or {}
    max_workers = int(policy.get("max_workers") or 1)
    if max_workers < 1:
        max_workers = 1

    workers = config.get("workers") or []
    worker_ids: List[str] = []
    if isinstance(workers, list):
        for w in workers:
            if isinstance(w, dict) and w.get("id"):
                worker_ids.append(str(w["id"]))
            elif isinstance(w, str):
                worker_ids.append(w)
    if not worker_ids:
        decision_path = write_decision(
            ops_root,
            {
                "version": 1,
                "created_at": utc_now_iso(),
                "type": "config_missing_workers",
                "request": {"reason": "config.yaml に workers が未設定"},
            },
        )
        state = read_yaml_file(state_path)
        blocked = state.get("blocked")
        if not isinstance(blocked, list):
            blocked = []
            state["blocked"] = blocked
        blocked.append({"issue": None, "reason": "config_missing_workers"})
        state["updated_at"] = utc_now_iso()
        atomic_write_yaml(state_path, state)
        atomic_write_text(dashboard_path, render_dashboard_md(state))
        sys.stdout.write(f"decision={decision_path}\n")
        return 0

    targets = candidates[: max_workers]
    state = read_yaml_file(state_path)
    forbidden = [".agent/**", "docs/prd/**", "docs/epics/**"]
    issued = 0

    orders_dir = os.path.join(ops_root, "queue", "orders")
    ensure_dir(orders_dir)

    # Pre-extract change targets to:
    # - Emit per-issue decisions for missing/invalid targets
    # - Avoid `worktree.sh check` failing early with rc=2 for missing targets
    assignable: List[Tuple[Dict[str, Any], List[str]]] = []
    for item in targets:
        n = int(item.get("number"))
        try:
            allowed_files = extract_allowed_files(toplevel, gh_repo, n)
        except RuntimeError as exc:
            decision_path = write_decision(
                ops_root,
                {
                    "version": 1,
                    "created_at": utc_now_iso(),
                    "issue": n,
                    "type": "missing_change_targets",
                    "request": {"reason": "Issue本文から変更対象ファイル（推定）を抽出できない", "details": str(exc)},
                },
            )
            blocked = state.get("blocked")
            if not isinstance(blocked, list):
                blocked = []
                state["blocked"] = blocked
            blocked.append({"issue": str(n), "reason": "missing_change_targets"})
            sys.stdout.write(f"decision={decision_path}\n")
            continue
        if not allowed_files:
            decision_path = write_decision(
                ops_root,
                {
                    "version": 1,
                    "created_at": utc_now_iso(),
                    "issue": n,
                    "type": "missing_change_targets",
                    "request": {"reason": "Issue本文から変更対象ファイル（推定）を抽出できない"},
                },
            )
            blocked = state.get("blocked")
            if not isinstance(blocked, list):
                blocked = []
                state["blocked"] = blocked
            blocked.append({"issue": str(n), "reason": "missing_change_targets"})
            sys.stdout.write(f"decision={decision_path}\n")
            continue
        assignable.append((item, allowed_files))

    # Overlap check only for issues that have deterministic change targets.
    issue_numbers = [int(item.get("number")) for (item, _files) in assignable]
    if len(issue_numbers) >= 2:
        rc, check_out = run_worktree_check(toplevel, gh_repo, issue_numbers)
        if rc == 3:
            decision_path = write_decision(
                ops_root,
                {
                    "version": 1,
                    "created_at": utc_now_iso(),
                    "type": "overlap_detected",
                    "request": {"issues": issue_numbers, "details": check_out.strip()},
                },
            )
            blocked = state.get("blocked")
            if not isinstance(blocked, list):
                blocked = []
                state["blocked"] = blocked
            for n in issue_numbers:
                blocked.append({"issue": str(n), "reason": "overlap_detected"})
            state["updated_at"] = utc_now_iso()
            atomic_write_yaml(state_path, state)
            atomic_write_text(dashboard_path, render_dashboard_md(state))
            sys.stdout.write(f"decision={decision_path}\n")
            return 0
        if rc != 0:
            raise RuntimeError(f"worktree.sh check failed (rc={rc}):\n{check_out.strip()}")

    for idx, item in enumerate(targets):
        n = int(item.get("number"))
        title = str(item.get("title") or "")
        worker = worker_ids[idx % len(worker_ids)]
        found = None
        for (it, files) in assignable:
            if int(it.get("number")) == n:
                found = files
                break
        if found is None:
            continue
        allowed_files = found

        entry = ensure_issue_entry(state, n)
        entry["title"] = title
        entry["labels"] = [l.get("name") for l in (item.get("labels") or []) if isinstance(l, dict) and l.get("name")]
        entry["assigned_to"] = worker
        entry["phase"] = "estimating"
        entry["impl_mode"] = ((config.get("policy") or {}).get("impl_mode") or {}).get("default") or "impl"
        entry["progress_percent"] = entry.get("progress_percent") or 0
        entry["contract"] = {"allowed_files": allowed_files, "forbidden_files": forbidden}

        slug = slugify(title)[:50]
        worktree_path = f".worktrees/issue-{n}-{slug}"
        entry["worktree"] = {"path": worktree_path}

        order_id = f"ORD-{utc_now_compact().replace('Z','')}-{worker}-{n}"
        order = {
            "version": 1,
            "order_id": order_id,
            "issued_at": utc_now_iso(),
            "worker": worker,
            "issue": n,
            "intent": f"Issue #{n} を完了（/review通過まで）",
            "impl_mode": entry["impl_mode"],
            "worktree": {"path": worktree_path},
            "contract": {"allowed_files": allowed_files, "forbidden_files": forbidden},
            "required_steps": ["/estimation (if not approved)", "/impl", "/review-cycle (loop until ready)", "/review"],
        }
        worker_dir = os.path.join(orders_dir, worker)
        ensure_dir(worker_dir)
        order_path = os.path.join(worker_dir, f"{order_id}.yaml")
        suffix = 1
        while os.path.exists(order_path):
            order_path = os.path.join(worker_dir, f"{order_id}-{suffix:03d}.yaml")
            suffix += 1
        atomic_write_yaml(order_path, order)
        issued += 1

    state["updated_at"] = utc_now_iso()
    atomic_write_yaml(state_path, state)
    atomic_write_text(dashboard_path, render_dashboard_md(state))
    sys.stdout.write(f"orders={issued}\n")
    return 0


def parse_timestamp_for_id(value: str) -> str:
    v = value.strip()
    if not v:
        raise RuntimeError("timestamp must be non-empty")
    # Accept ISO8601 with Z, or compact YYYYMMDDTHHMMSSZ.
    if v.endswith("Z") and "T" in v and "-" in v:
        return v.replace(":", "").replace("-", "").replace("T", "T")
    if v.endswith("Z") and len(v) == 16 and v[8] == "T":
        return v
    raise RuntimeError(f"invalid timestamp format (expected YYYYMMDDTHHMMSSZ or ISO8601Z): {value}")


def utc_now_compact() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def detect_worker_id(explicit: Optional[str]) -> str:
    if explicit:
        return explicit.strip()
    env = os.environ.get("AGENTIC_SDD_WORKER") or os.environ.get("USER") or ""
    env = env.strip()
    if not env:
        raise RuntimeError("worker id is required (set --worker or AGENTIC_SDD_WORKER)")
    return env


def git_changed_files(include_staged: bool) -> List[str]:
    files: List[str] = []
    try:
        out = run_git(["diff", "--name-only"])
        files.extend([ln.strip() for ln in out.splitlines() if ln.strip()])
        if include_staged:
            out2 = run_git(["diff", "--name-only", "--staged"])
            files.extend([ln.strip() for ln in out2.splitlines() if ln.strip()])
    except RuntimeError:
        return []
    # de-dup preserving order
    seen = set()
    uniq: List[str] = []
    for f in files:
        if f not in seen:
            seen.add(f)
            uniq.append(f)
    return uniq


def cmd_checkin(args: argparse.Namespace) -> int:
    _abs_git_dir, common_abs, toplevel = resolve_git_dirs()
    root, _state_path, _dashboard_path = ensure_ops_layout(common_abs)
    repo_root = os.path.dirname(common_abs)
    worktree_root = os.path.relpath(toplevel, repo_root)

    worker = detect_worker_id(args.worker)
    issue = int(args.issue)
    phase = str(args.phase)
    progress_percent = int(args.percent)
    summary = " ".join(args.summary).strip()
    if not summary:
        raise RuntimeError("summary must be non-empty")

    ts_compact = parse_timestamp_for_id(args.timestamp) if args.timestamp else utc_now_compact()
    ts_iso = (
        args.timestamp
        if args.timestamp and args.timestamp.endswith("Z") and "-" in args.timestamp
        else datetime.datetime.strptime(ts_compact, "%Y%m%dT%H%M%SZ")
        .replace(tzinfo=datetime.timezone.utc)
        .isoformat()
        .replace("+00:00", "Z")
    )

    checkin_id = f"{worker}-{issue}-{ts_compact}"
    out_dir = os.path.join(root, "queue", "checkins", worker)
    out_path = os.path.join(out_dir, f"{ts_compact}.yaml")
    if os.path.exists(out_path):
        raise RuntimeError(f"checkin already exists (append-only): {out_path}")

    files_changed: List[str] = []
    if args.auto_files_changed:
        files_changed = git_changed_files(include_staged=bool(args.include_staged))
    if args.files_changed:
        for f in args.files_changed:
            f = f.strip()
            if f:
                files_changed.append(f)

    obj: Dict[str, Any] = {
        "version": 1,
        "checkin_id": checkin_id,
        "timestamp": ts_iso,
        "worker": worker,
        "issue": issue,
        "phase": phase,
        "progress_percent": progress_percent,
        "summary": summary,
        "repo": {
            "worktree_root": worktree_root,
            "toplevel": toplevel,
        },
        "changes": {"files_changed": files_changed},
        "tests": {"command": args.tests_command or "", "result": args.tests_result or ""},
        "needs": {"approval": False, "contract_expansion": {"requested_files": []}},
        "next": [],
    }

    ensure_dir(out_dir)
    atomic_write_yaml(out_path, obj)

    sys.stdout.write(out_path + "\n")
    return 0


def cmd_status(_args: argparse.Namespace) -> int:
    _abs_git_dir, common_abs, _toplevel = resolve_git_dirs()
    _root, _state_path, dashboard_path = ensure_ops_layout(common_abs)
    with open(dashboard_path, "r", encoding="utf-8") as fh:
        sys.stdout.write(fh.read())
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="shogun-ops.py", description="Agentic-SDD Shogun Ops helper")
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("checkin", help="Create an append-only checkin YAML")
    c.add_argument("issue", type=int, help="Issue number")
    c.add_argument("phase", help="backlog|estimating|implementing|reviewing|blocked|done")
    c.add_argument("percent", type=int, help="Progress percent (0-100)")
    c.add_argument("summary", nargs="+", help="Summary text (use `--` before summary if passing flags)")
    c.add_argument("--worker", help="Worker id (default: $AGENTIC_SDD_WORKER or $USER)")
    c.add_argument("--timestamp", help="Override timestamp (YYYYMMDDTHHMMSSZ or ISO8601Z)")
    c.add_argument("--no-auto-files-changed", dest="auto_files_changed", action="store_false")
    c.add_argument("--auto-files-changed", dest="auto_files_changed", action="store_true")
    c.set_defaults(auto_files_changed=True)
    c.add_argument("--include-staged", action="store_true", help="Include staged changes in files_changed")
    c.add_argument("--files-changed", action="append", help="Additional files_changed entry (repeatable)")
    c.add_argument("--tests-command", help="Test command to record (optional)")
    c.add_argument("--tests-result", choices=["pass", "fail", "skip"], help="Test result to record (optional)")
    c.set_defaults(func=cmd_checkin)

    col = sub.add_parser("collect", help="Collect checkins and update state/dashboard (single-writer)")
    col.set_defaults(func=cmd_collect)

    sup = sub.add_parser("supervise", help="Supervise issues and emit orders/decisions")
    sup.add_argument("--once", action="store_true", help="Run one cycle (required)")
    sup.add_argument("--gh-repo", help="OWNER/REPO (default: derived from origin)")
    sup.add_argument("--targets", type=int, action="append", help="Target Issue number (repeatable)")
    sup.set_defaults(func=cmd_supervise)

    s = sub.add_parser("status", help="Show ops dashboard (initializes if missing)")
    s.set_defaults(func=cmd_status)
    return p


def main(argv: List[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except RuntimeError as exc:
        eprint(str(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
