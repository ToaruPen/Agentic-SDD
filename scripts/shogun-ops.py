#!/usr/bin/env python3

import argparse
import datetime
import fnmatch
import hashlib
import os
import re
import subprocess
import sys
import tempfile
from typing import Any, Dict, List, Optional, Tuple

import yaml


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def as_int(value: Any, *, context: str) -> int:
    if value is None:
        raise RuntimeError(f"missing integer value: {context}")
    try:
        return int(value)
    except (TypeError, ValueError):
        raise RuntimeError(f"invalid integer value: {context}={value!r}")


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
    return (
        datetime.datetime.now(datetime.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def resolve_git_dirs() -> Tuple[str, str, str]:
    abs_git_dir = run_git(["rev-parse", "--absolute-git-dir"])
    toplevel = run_git(["rev-parse", "--show-toplevel"])

    common_abs = ""
    try:
        common_abs = run_git(
            ["rev-parse", "--path-format=absolute", "--git-common-dir"]
        )
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
            "parallel": {
                "enabled": True,
                "max_workers": 3,
                "require_parallel_ok_label": True,
            },
            "impl_mode": {
                "default": "impl",
                "force_tdd_labels": ["tdd", "bug", "high-risk"],
            },
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
        "action_required": [],
        "skill_candidates_pending": [],
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

    action_required = state.get("action_required") or []
    if not isinstance(action_required, list):
        action_required = []

    skill_candidates = state.get("skill_candidates_pending") or []
    if not isinstance(skill_candidates, list):
        skill_candidates = []

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
    lines.append("## Action Required")
    if action_required:
        for item in action_required[:20]:
            if not isinstance(item, dict):
                continue
            decision_id = str(item.get("decision_id") or "").strip()
            created_at = str(item.get("created_at") or "").strip()
            issue = str(item.get("issue") or "").strip()
            worker = str(item.get("worker") or "").strip()
            kind = str(item.get("kind") or "").strip()
            summary = str(item.get("summary") or "").strip()
            prefix = f"- {created_at} #{issue}".rstrip()
            if worker:
                prefix += f" ({worker})"
            if kind:
                prefix += f" {kind}"
            if summary:
                prefix += f": {summary}"
            if decision_id:
                prefix += f" [{decision_id}]"
            lines.append(prefix.rstrip())
    else:
        lines.append("- (none)")
    lines.append("")
    lines.append("## Skill Candidates (Approval Pending)")
    if skill_candidates:
        for item in skill_candidates[:20]:
            if not isinstance(item, dict):
                continue
            name = str(item.get("name") or "").strip()
            summary = str(item.get("summary") or "").strip()
            if not name:
                name = "(missing name)"
            if summary:
                lines.append(f"- {name}: {summary}".rstrip())
            else:
                lines.append(f"- {name}".rstrip())
    else:
        lines.append("- (none)")
    lines.append("")
    lines.append("## Blocked / Needs Decision")
    if blocked_list:
        for item in blocked_list[:20]:
            if not isinstance(item, dict):
                continue
            issue = str(item.get("issue") or "").strip()
            reason = str(item.get("reason") or "")
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
    ensure_dir(os.path.join(root, "queue", "refactor-drafts"))
    ensure_dir(os.path.join(root, "archive", "checkins"))
    ensure_dir(os.path.join(root, "archive", "decisions"))
    ensure_dir(os.path.join(root, "archive", "refactor-drafts"))
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


def list_decision_paths(ops_root: str) -> List[str]:
    base = os.path.join(ops_root, "queue", "decisions")
    out: List[str] = []
    if not os.path.isdir(base):
        return out
    for name in sorted(os.listdir(base)):
        if not name.endswith(".yaml"):
            continue
        out.append(os.path.join(base, name))
    return out


def list_archived_decision_paths(ops_root: str) -> List[str]:
    base = os.path.join(ops_root, "archive", "decisions")
    out: List[str] = []
    if not os.path.isdir(base):
        return out
    for name in sorted(os.listdir(base)):
        if not name.endswith(".yaml"):
            continue
        out.append(os.path.join(base, name))
    return out


def decision_dedupe_key(kind: str, issue: int, worker: str, payload: str) -> str:
    raw = f"{kind}|issue={issue}|worker={worker}|{payload}".encode(
        "utf-8", errors="strict"
    )
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def skill_candidate_dedupe_key(issue: int, name: str, summary: str) -> str:
    raw = f"skill_candidate|issue={issue}|name={name}|summary={summary}".encode(
        "utf-8", errors="strict"
    )
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def existing_decision_dedupe_keys(ops_root: str) -> set:
    keys: set = set()
    for path in list_decision_paths(ops_root):
        obj = read_yaml_file(path)
        k = obj.get("dedupe_key")
        if isinstance(k, str) and k:
            keys.add(k)
    return keys


def existing_decision_dedupe_key_to_path(ops_root: str) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for path in list_decision_paths(ops_root):
        obj = read_yaml_file(path)
        if not isinstance(obj, dict):
            continue
        k = obj.get("dedupe_key")
        if not isinstance(k, str) or not k:
            continue
        # Keep the first occurrence (deterministic by list_decision_paths sorting).
        if k not in out:
            out[k] = path
    return out


def build_action_required_index_from_decisions(ops_root: str) -> List[Dict[str, Any]]:
    items: List[Dict[str, Any]] = []
    for path in list_decision_paths(ops_root):
        obj = read_yaml_file(path)
        if not isinstance(obj, dict):
            continue
        decision_id = obj.get("decision_id")
        if not decision_id:
            decision_id = os.path.splitext(os.path.basename(path))[0]
        created_at = obj.get("created_at") or ""
        issue = obj.get("issue")
        kind = obj.get("type") or ""
        request = obj.get("request") or {}
        worker = ""
        summary = ""
        if isinstance(request, dict):
            if kind == "skill_candidate":
                workers_raw = request.get("workers") or []
                worker_ids: List[str] = []
                if isinstance(workers_raw, list):
                    for w in workers_raw:
                        s = str(w).strip()
                        if s:
                            worker_ids.append(s)
                if not worker_ids:
                    submitters_raw = request.get("submitters") or []
                    if isinstance(submitters_raw, list):
                        for sub in submitters_raw:
                            if not isinstance(sub, dict):
                                continue
                            s = str(sub.get("worker") or "").strip()
                            if s and s not in worker_ids:
                                worker_ids.append(s)
                worker = (
                    ", ".join(worker_ids)
                    if worker_ids
                    else str(request.get("worker") or "")
                )
            else:
                worker = str(request.get("worker") or "")
            summary = str(request.get("reason") or request.get("summary") or "")
        items.append(
            {
                "decision_id": str(decision_id),
                "created_at": str(created_at),
                "issue": "" if issue is None else str(issue),
                "worker": worker,
                "kind": str(kind),
                "summary": summary,
            }
        )

    def sort_key(it: Dict[str, Any]) -> Tuple[str, str]:
        return (str(it.get("created_at") or ""), str(it.get("decision_id") or ""))

    items.sort(key=sort_key, reverse=True)
    return items


def build_skill_candidates_index_from_decisions(ops_root: str) -> List[Dict[str, Any]]:
    items: List[Dict[str, Any]] = []
    for path in list_decision_paths(ops_root):
        obj = read_yaml_file(path)
        if not isinstance(obj, dict):
            continue
        if str(obj.get("type") or "") != "skill_candidate":
            continue

        decision_id = obj.get("decision_id")
        if not decision_id:
            decision_id = os.path.splitext(os.path.basename(path))[0]

        created_at = str(obj.get("created_at") or "")
        request = obj.get("request") or {}
        if not isinstance(request, dict):
            request = {}

        name = str(request.get("name") or obj.get("name") or "").strip()
        summary = str(
            request.get("summary") or obj.get("summary") or request.get("reason") or ""
        ).strip()
        items.append(
            {
                "decision_id": str(decision_id),
                "created_at": created_at,
                "name": name,
                "summary": summary,
            }
        )

    def sort_key(it: Dict[str, Any]) -> Tuple[str, str]:
        return (str(it.get("created_at") or ""), str(it.get("decision_id") or ""))

    items.sort(key=sort_key, reverse=True)
    return items


def match_any_glob(path: str, patterns: List[str]) -> bool:
    p = (path or "").strip().replace("\\", "/")
    if p.startswith("./"):
        p = p[2:]
    if not p or p in {".", ".."}:
        return False
    path_parts = [seg for seg in p.split("/") if seg]

    def match_parts(parts: List[str], pat_parts: List[str]) -> bool:
        i = 0
        j = 0
        while True:
            if j >= len(pat_parts):
                return i >= len(parts)

            pat = pat_parts[j]
            if pat == "**":
                # Collapse consecutive globstars.
                while j + 1 < len(pat_parts) and pat_parts[j + 1] == "**":
                    j += 1
                # Trailing globstar matches the rest.
                if j == len(pat_parts) - 1:
                    return True
                # Try consuming 0..N segments.
                j += 1
                while i <= len(parts):
                    if match_parts(parts[i:], pat_parts[j:]):
                        return True
                    i += 1
                return False

            if i >= len(parts):
                return False
            if not fnmatch.fnmatchcase(parts[i], pat):
                return False
            i += 1
            j += 1

    for raw_pat in patterns:
        pat = (raw_pat or "").strip().replace("\\", "/")
        if pat.startswith("./"):
            pat = pat[2:]
        if not pat:
            continue
        pat_parts = [seg for seg in pat.split("/") if seg]
        if match_parts(path_parts, pat_parts):
            return True
    return False


def ensure_blocked_reason(state: Dict[str, Any], issue: int, reason: str) -> None:
    blocked = state.get("blocked")
    if not isinstance(blocked, list):
        blocked = []
        state["blocked"] = blocked
    key_issue = str(issue)
    for it in blocked:
        if not isinstance(it, dict):
            continue
        if (
            str(it.get("issue") or "") == key_issue
            and str(it.get("reason") or "") == reason
        ):
            return
    blocked.append({"issue": key_issue, "reason": reason})


def emit_decisions_from_checkin(
    ops_root: str,
    issue: int,
    worker: str,
    checkin: Dict[str, Any],
    existing_keys: set,
    existing_paths: Dict[str, str],
    issue_context: Optional[Dict[str, Any]] = None,
) -> int:
    needs = checkin.get("needs") or {}
    if not isinstance(needs, dict):
        needs = {}

    created = 0

    approval = bool(needs.get("approval") is True)
    if approval:
        k = decision_dedupe_key("approval_required", issue, worker, "v1")
        if k not in existing_keys:
            decision = {
                "version": 1,
                "created_at": utc_now_iso(),
                "issue": issue,
                "type": "approval_required",
                "dedupe_key": k,
                "request": {
                    "worker": worker,
                    "reason": "承認が必要（checkin.needs.approval=true）",
                    "checkin_id": checkin.get("checkin_id") or "",
                },
            }
            write_decision(ops_root, decision)
            existing_keys.add(k)
            created += 1

    contract = needs.get("contract_expansion") or {}
    requested_files: List[str] = []
    if isinstance(contract, dict):
        rf = contract.get("requested_files") or []
        if isinstance(rf, list):
            for x in rf:
                s = str(x).strip()
                if s:
                    requested_files.append(s)
    requested_files = sorted(set(requested_files))
    if requested_files:
        payload = "requested_files=" + ",".join(requested_files)
        k = decision_dedupe_key("contract_expansion", issue, worker, payload)
        if k not in existing_keys:
            decision = {
                "version": 1,
                "created_at": utc_now_iso(),
                "issue": issue,
                "type": "contract_expansion",
                "dedupe_key": k,
                "request": {
                    "worker": worker,
                    "reason": "契約拡張が必要（checkin.needs.contract_expansion.requested_files）",
                    "requested_files": requested_files,
                    "checkin_id": checkin.get("checkin_id") or "",
                },
            }
            write_decision(ops_root, decision)
            existing_keys.add(k)
            created += 1

    blockers_raw = needs.get("blockers") or []
    blockers: List[str] = []
    if isinstance(blockers_raw, list):
        for x in blockers_raw:
            s = str(x).strip()
            if s:
                blockers.append(s)
    for blocker in blockers:
        payload = "blocker=" + blocker
        k = decision_dedupe_key("blocker", issue, worker, payload)
        if k in existing_keys:
            continue
        is_research_request = blocker.strip().startswith("調査依頼:")
        request_obj: Dict[str, Any] = {
            "worker": worker,
            "reason": blocker,
            "checkin_id": checkin.get("checkin_id") or "",
        }
        decision_obj: Dict[str, Any] = {
            "version": 1,
            "created_at": utc_now_iso(),
            "issue": issue,
            "type": "blocker",
            "dedupe_key": k,
            "request": request_obj,
        }
        if is_research_request:
            request_obj["category"] = "research"
            if issue_context is not None:
                decision_obj["issue_context"] = issue_context
        write_decision(ops_root, decision_obj)
        existing_keys.add(k)
        created += 1

    candidates = checkin.get("candidates") or {}
    if candidates:
        if not isinstance(candidates, dict):
            raise RuntimeError("invalid checkin candidates (expected a mapping)")
        skills_raw = candidates.get("skills") or []
        if not isinstance(skills_raw, list):
            raise RuntimeError("invalid checkin candidates.skills (expected an array)")
        for it in skills_raw:
            if not isinstance(it, dict):
                raise RuntimeError(
                    "invalid checkin candidates.skills[] (expected objects)"
                )
            name = str(it.get("name") or "").strip()
            summary = str(it.get("summary") or "").strip()
            if not name:
                raise RuntimeError(
                    "invalid checkin candidates.skills[].name (required)"
                )
            if not summary:
                raise RuntimeError(
                    "invalid checkin candidates.skills[].summary (required)"
                )
            k = skill_candidate_dedupe_key(issue=issue, name=name, summary=summary)
            checkin_id = str(checkin.get("checkin_id") or "").strip()
            submitter = {
                "worker": worker,
                "checkin_id": checkin_id,
                "timestamp": str(checkin.get("timestamp") or ""),
            }

            if k in existing_keys:
                path = existing_paths.get(k)
                if not path:
                    # Should not happen; fall back to skipping to avoid multiplying decisions.
                    continue
                obj = read_yaml_file(path)
                if not isinstance(obj, dict):
                    raise RuntimeError(
                        f"invalid decision object (expected a mapping): {path}"
                    )
                if str(obj.get("type") or "") != "skill_candidate":
                    raise RuntimeError(
                        f"dedupe_key collision across decision types: {path}"
                    )
                req = obj.get("request") or {}
                if not isinstance(req, dict):
                    req = {}
                workers_raw = req.get("workers")
                workers: List[str] = []
                if isinstance(workers_raw, list):
                    for w in workers_raw:
                        s = str(w).strip()
                        if s:
                            workers.append(s)
                if not workers:
                    w0 = str(req.get("worker") or "").strip()
                    if w0:
                        workers.append(w0)
                if worker not in workers:
                    workers.append(worker)
                req["workers"] = workers

                submitters_raw = req.get("submitters")
                submitters: List[Dict[str, str]] = []
                if isinstance(submitters_raw, list):
                    for sub in submitters_raw:
                        if not isinstance(sub, dict):
                            continue
                        w = str(sub.get("worker") or "").strip()
                        cid = str(sub.get("checkin_id") or "").strip()
                        ts = str(sub.get("timestamp") or "")
                        if not w:
                            continue
                        submitters.append(
                            {"worker": w, "checkin_id": cid, "timestamp": ts}
                        )
                if not submitters:
                    w0 = str(req.get("worker") or "").strip()
                    cid0 = str(req.get("checkin_id") or "").strip()
                    if w0:
                        submitters.append(
                            {"worker": w0, "checkin_id": cid0, "timestamp": ""}
                        )

                key = f"{worker}|{checkin_id}"
                seen = set(
                    f"{s.get('worker', '')}|{s.get('checkin_id', '')}"
                    for s in submitters
                )
                if key not in seen:
                    submitters.append(submitter)
                    req["submitters"] = submitters
                    obj["request"] = req
                    atomic_write_yaml(path, obj)
                continue
            decision = {
                "version": 1,
                "created_at": utc_now_iso(),
                "issue": issue,
                "type": "skill_candidate",
                "dedupe_key": k,
                "request": {
                    "worker": worker,
                    "workers": [worker],
                    "submitters": [submitter],
                    "reason": f"{name}: {summary}",
                    "name": name,
                    "summary": summary,
                    "checkin_id": checkin_id,
                },
            }
            write_decision(ops_root, decision)
            existing_keys.add(k)
            existing_paths[k] = os.path.join(
                ops_root, "queue", "decisions", f"{decision.get('decision_id')}.yaml"
            )
            created += 1

    return created


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


def has_research_request_blocker(checkin: Dict[str, Any]) -> bool:
    needs = checkin.get("needs") or {}
    if not isinstance(needs, dict):
        return False
    blockers = needs.get("blockers") or []
    if not isinstance(blockers, list):
        return False
    for b in blockers:
        if str(b).strip().startswith("調査依頼:"):
            return True
    return False


def fetch_issue_context_for_research(toplevel: str, issue: int) -> Dict[str, Any]:
    gh_repo = detect_gh_repo_from_origin(toplevel)
    obj = gh_json(
        [
            "-R",
            gh_repo,
            "issue",
            "view",
            str(issue),
            "--json",
            "number,title,url,labels",
        ]
    )
    if not isinstance(obj, dict):
        raise RuntimeError("gh issue view must return an object")

    labels_raw = obj.get("labels") or []
    labels: List[str] = []
    if isinstance(labels_raw, list):
        for label in labels_raw:
            if isinstance(label, dict) and label.get("name"):
                labels.append(str(label.get("name")))
    labels = sorted(set([x for x in labels if str(x).strip()]))

    return {
        "repo": gh_repo,
        "number": int(obj.get("number") or issue),
        "title": str(obj.get("title") or "").strip(),
        "url": str(obj.get("url") or "").strip(),
        "labels": labels,
    }


def extract_respond_to_decision_id(checkin: Dict[str, Any]) -> str:
    respond_to = checkin.get("respond_to") or {}
    if not isinstance(respond_to, dict):
        return ""
    raw = str(respond_to.get("decision_id") or "").strip()
    if not raw:
        return ""
    return normalize_decision_id(raw)


def apply_research_response(
    ops_root: str, decision_id: str, checkin: Dict[str, Any]
) -> str:
    decision_path = find_decision_path_anywhere(ops_root, decision_id)
    decision = read_yaml_file(decision_path)
    if not isinstance(decision, dict):
        raise RuntimeError(f"invalid decision YAML (expected mapping): {decision_path}")

    if str(decision.get("type") or "") != "blocker":
        raise RuntimeError(
            f"respond_to is supported only for blocker decisions: {decision_id}"
        )
    req = decision.get("request") or {}
    if not isinstance(req, dict):
        req = {}
        decision["request"] = req
    if str(req.get("category") or "") != "research":
        raise RuntimeError(
            f"respond_to is supported only for research blocker decisions: {decision_id}"
        )

    issue_decision = decision.get("issue")
    try:
        issue_decision_int = int(issue_decision) if issue_decision is not None else None
    except Exception:
        issue_decision_int = None
    issue_checkin_raw = checkin.get("issue")
    try:
        issue_checkin = (
            int(issue_checkin_raw) if issue_checkin_raw is not None else None
        )
    except Exception:
        issue_checkin = None
    if (
        issue_decision_int is not None
        and issue_checkin is not None
        and issue_decision_int != issue_checkin
    ):
        raise RuntimeError(
            f"respond_to issue mismatch: decision.issue={issue_decision_int} != checkin.issue={issue_checkin} ({decision_id})"
        )

    response = {
        "timestamp": str(checkin.get("timestamp") or ""),
        "worker": str(checkin.get("worker") or ""),
        "checkin_id": str(checkin.get("checkin_id") or ""),
        "summary": str(checkin.get("summary") or ""),
    }
    if not response["checkin_id"]:
        raise RuntimeError(
            f"invalid checkin (missing checkin_id) for respond_to: {decision_id}"
        )

    responses_raw = decision.get("responses") or []
    responses: List[Dict[str, str]] = []
    if isinstance(responses_raw, list):
        for it in responses_raw:
            if not isinstance(it, dict):
                continue
            cid = str(it.get("checkin_id") or "").strip()
            if cid:
                responses.append(
                    {
                        "timestamp": str(it.get("timestamp") or ""),
                        "worker": str(it.get("worker") or ""),
                        "checkin_id": cid,
                        "summary": str(it.get("summary") or ""),
                    }
                )
    if not any(r.get("checkin_id") == response["checkin_id"] for r in responses):
        responses.append(response)
    decision["responses"] = responses

    if not str(decision.get("resolved_at") or "").strip():
        decision["resolved_at"] = response["timestamp"]
    if not str(decision.get("resolved_by") or "").strip():
        decision["resolved_by"] = response["worker"]
    if not str(decision.get("resolution_summary") or "").strip():
        decision["resolution_summary"] = response["summary"]

    atomic_write_yaml(decision_path, decision)

    # Auto-archive (A): if the decision lives in queue, move it to archive/decisions.
    queue_dir = os.path.join(ops_root, "queue", "decisions")
    archive_dir = os.path.join(ops_root, "archive", "decisions")
    if os.path.realpath(decision_path).startswith(os.path.realpath(queue_dir) + os.sep):
        ensure_dir(archive_dir)
        archive_base = os.path.join(archive_dir, os.path.basename(decision_path))
        archive_path = unique_path_with_suffix(archive_base)
        os.replace(decision_path, archive_path)
        return archive_path

    return decision_path


def cmd_collect(_args: argparse.Namespace) -> int:
    _abs_git_dir, common_abs, toplevel = resolve_git_dirs()
    ops_root, state_path, dashboard_path = ensure_ops_layout(common_abs)

    lock_path = os.path.join(ops_root, "locks", "collect.lock")
    lock = acquire_lock(lock_path)
    try:
        checkin_paths = list_checkin_paths(ops_root)
        state = read_yaml_file(state_path)
        if "action_required" not in state:
            state["action_required"] = []
        if "skill_candidates_pending" not in state:
            state["skill_candidates_pending"] = []
        if not checkin_paths:
            state["action_required"] = build_action_required_index_from_decisions(
                ops_root
            )
            state["skill_candidates_pending"] = (
                build_skill_candidates_index_from_decisions(ops_root)
            )
            state["updated_at"] = utc_now_iso()
            atomic_write_yaml(state_path, state)
            atomic_write_text(dashboard_path, render_dashboard_md(state))
            return 0
        items: List[Tuple[str, str, Dict[str, Any], int]] = []
        dedupe_paths = existing_decision_dedupe_key_to_path(ops_root)
        dedupe_keys = set(dedupe_paths.keys())

        for path in checkin_paths:
            checkin = read_yaml_file(path)
            issue_raw = checkin.get("issue")
            issue = as_int(issue_raw, context=f"checkin.issue path={path}")

            # Do not trust worker id inside YAML (may be tampered). Use the queue directory name as SoT.
            worker_from_dir = os.path.basename(os.path.dirname(path))
            worker = validate_worker_id(worker_from_dir)
            checkin["worker"] = worker

            archive_dir = os.path.join(ops_root, "archive", "checkins", worker)
            archive_base = os.path.join(archive_dir, os.path.basename(path))
            items.append((path, archive_base, checkin, issue))

        # Pass 1: process normal checkins first (may create decisions).
        for path, _archive_base, checkin, issue in items:
            if extract_respond_to_decision_id(checkin):
                continue

            entry = ensure_issue_entry(state, issue)
            entry["assigned_to"] = checkin.get("worker") or entry.get("assigned_to")
            phase_from_checkin = checkin.get("phase") or entry.get("phase") or "backlog"
            entry["phase"] = phase_from_checkin
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

            issue_context: Optional[Dict[str, Any]] = None
            if has_research_request_blocker(checkin):
                issue_context = fetch_issue_context_for_research(toplevel, issue)

            changes = checkin.get("changes") or {}
            files_changed: List[str] = []
            if isinstance(changes, dict):
                fc = changes.get("files_changed") or []
                if isinstance(fc, list):
                    for x in fc:
                        s = str(x).strip()
                        if s:
                            files_changed.append(s)

            contract = entry.get("contract") or {}
            allowed_files: List[str] = []
            forbidden_files: List[str] = []
            if isinstance(contract, dict):
                af = contract.get("allowed_files") or []
                if isinstance(af, list):
                    for x in af:
                        s = str(x).strip()
                        if s:
                            allowed_files.append(s)
                ff = contract.get("forbidden_files") or []
                if isinstance(ff, list):
                    for x in ff:
                        s = str(x).strip()
                        if s:
                            forbidden_files.append(s)

            requested_files: List[str] = []
            if allowed_files:
                requested_files = [
                    f
                    for f in files_changed
                    if f and not match_any_glob(f, allowed_files)
                ]
            requested_files = sorted(set(requested_files))
            forbidden_hits = sorted(
                set([f for f in files_changed if match_any_glob(f, forbidden_files)])
            )
            if forbidden_hits:
                requested_files = sorted(set(requested_files + forbidden_hits))

            if forbidden_hits or (requested_files and allowed_files):
                payload = "requested_files=" + ",".join(requested_files)
                k = decision_dedupe_key(
                    "contract_expansion",
                    issue,
                    str(checkin.get("worker") or ""),
                    payload,
                )
                if k not in dedupe_keys:
                    decision = {
                        "version": 1,
                        "created_at": utc_now_iso(),
                        "issue": issue,
                        "type": "contract_expansion",
                        "dedupe_key": k,
                        "request": {
                            "worker": str(checkin.get("worker") or ""),
                            "reason": "契約逸脱を検知（collect: changes.files_changed vs contract.allowed_files）",
                            "requested_files": requested_files,
                            "options": [
                                "拡張",
                                "差し戻し",
                                "Issue分割",
                                "別Issueへ移動",
                            ],
                            "severity": "major" if forbidden_hits else "normal",
                            "forbidden_files": forbidden_hits,
                            "checkin_id": checkin.get("checkin_id") or "",
                        },
                    }
                    write_decision(ops_root, decision)
                    dedupe_keys.add(k)

                entry["phase"] = "blocked"
                ensure_blocked_reason(state, issue, "contract_violation")
                if forbidden_hits:
                    ensure_blocked_reason(state, issue, "contract_forbidden_violation")

            emit_decisions_from_checkin(
                ops_root=ops_root,
                issue=issue,
                worker=str(checkin.get("worker") or ""),
                checkin=checkin,
                existing_keys=dedupe_keys,
                existing_paths=dedupe_paths,
                issue_context=issue_context,
            )

            record_recent_checkin(state, checkin)

        # Pass 2: process out-of-band responses after decisions have been created.
        for path, _archive_base, checkin, issue in items:
            respond_to_decision_id = extract_respond_to_decision_id(checkin)
            if not respond_to_decision_id:
                continue
            # Treat as an out-of-band response (do not mutate issue phase/assignee/progress).
            apply_research_response(ops_root, respond_to_decision_id, checkin)
            record_recent_checkin(state, checkin)

        state["action_required"] = build_action_required_index_from_decisions(ops_root)
        state["skill_candidates_pending"] = build_skill_candidates_index_from_decisions(
            ops_root
        )
        state["updated_at"] = utc_now_iso()
        atomic_write_yaml(state_path, state)

        dash = render_dashboard_md(state)
        atomic_write_text(dashboard_path, dash)

        processed = 0
        for path, archive_base, _checkin, _issue in items:
            # archive (append-only queue semantics; remove from queue after processing)
            ensure_dir(os.path.dirname(archive_base))
            archive_path = unique_path_with_suffix(archive_base)
            os.replace(path, archive_path)
            processed += 1

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
        url = (
            subprocess.check_output(
                ["git", "-C", toplevel, "remote", "get-url", "origin"],
                stderr=subprocess.STDOUT,
            )
            .decode("utf-8", errors="replace")
            .strip()
        )
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
    if url.startswith("ssh://git@github.com/"):
        path = url.split("ssh://git@github.com/", 1)[1]
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


def gh_run(cmd: List[str]) -> str:
    try:
        out = subprocess.check_output(["gh", *cmd], stderr=subprocess.STDOUT)
    except FileNotFoundError:
        raise RuntimeError("gh not found")
    except subprocess.CalledProcessError as exc:
        msg = exc.output.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"gh command failed: gh {' '.join(cmd)}\n{msg}")
    return out.decode("utf-8", errors="replace").strip()


def parse_issue_url(text: str) -> Tuple[str, int]:
    s = (text or "").strip()
    if not s:
        raise RuntimeError("gh issue create returned empty output (expected issue URL)")
    url = s.splitlines()[-1].strip()
    m = re.search(r"/issues/([0-9]+)(?:\\s|$)", url)
    if not m:
        raise RuntimeError(f"failed to parse issue number from gh output: {url}")
    return url, int(m.group(1))


_LABEL_COLORS = {
    "refactor-candidate": "BFDADC",
    "refactor-smell/": "D4C5F9",
    "refactor-risk/": "F9D0C4",
    "refactor-impact/": "C2E0C6",
}


def ensure_refactor_labels(gh_repo: str, labels: List[str]) -> None:
    # Create or update labels deterministically. This is intended for Middle (single-writer).
    for name in labels:
        n = str(name or "").strip()
        if not n:
            continue
        color = _LABEL_COLORS.get(n, "")
        if not color:
            for prefix, c in _LABEL_COLORS.items():
                if prefix.endswith("/") and n.startswith(prefix):
                    color = c
                    break
        if not color:
            color = "C5DEF5"
        desc = f"auto-managed by Agentic-SDD (refactor draft): {n}"
        gh_run(
            [
                "-R",
                gh_repo,
                "label",
                "create",
                n,
                "--color",
                color,
                "--description",
                desc,
                "--force",
            ]
        )


def render_refactor_issue_body(draft: Dict[str, Any], draft_path: str) -> str:
    summary = str(draft.get("summary") or "").strip()
    timestamp = str(draft.get("timestamp") or "").strip()
    ref = draft.get("refactor") or {}
    smells = ref.get("smells") or []
    risk = str(ref.get("risk") or "").strip()
    impact = str(ref.get("impact") or "").strip()
    targets = draft.get("targets") or {}
    files = targets.get("files") or []

    lines: List[str] = []
    lines.append("## 概要")
    lines.append("")
    lines.append(summary if summary else "(要約を追記してください)")

    lines.append("")
    lines.append("## 背景")
    lines.append("")
    lines.append(f"- Refactor draft: `{draft_path}`")
    if timestamp:
        lines.append(f"- timestamp: `{timestamp}`")
    if smells:
        if isinstance(smells, list):
            s = ", ".join([str(x) for x in smells if str(x).strip()])
            if s:
                lines.append(f"- smells: {s}")
    if risk:
        lines.append(f"- risk: {risk}")
    if impact:
        lines.append(f"- impact: {impact}")

    lines.append("")
    lines.append("## 受け入れ条件（AC）")
    lines.append("")
    lines.append("- [ ] AC1: （観測可能な条件を記述）")
    lines.append("- [ ] AC2: （観測可能な条件を記述）")

    lines.append("")
    lines.append("## 技術メモ")
    lines.append("")
    lines.append("### 変更対象ファイル（推定）")
    lines.append("")
    if isinstance(files, list) and files:
        for f in files:
            s = str(f).strip()
            if s:
                lines.append(f"- [ ] `{s}`")
    else:
        lines.append("- [ ] `path/to/file1`")

    lines.append("")
    lines.append("### 推定行数")
    lines.append("")
    lines.append("- [ ] 50行未満（小さい）")
    lines.append("- [ ] 50〜150行（適正）")
    lines.append("- [ ] 150〜300行（大きめ）")
    lines.append("- [ ] 300行超（要分割検討）")

    lines.append("")
    lines.append("## 依存関係")
    lines.append("")
    lines.append("- Blocked by: #[Issue番号]（[理由]）")
    lines.append("- 先に終わると何が可能になるか: [説明]")

    return "\n".join(lines).rstrip() + "\n"


def resolve_refactor_draft_path(
    ops_root: str, draft_path: str, worker: Optional[str], timestamp: Optional[str]
) -> Tuple[str, str, str]:
    if draft_path:
        p = os.path.realpath(draft_path)
    else:
        w = validate_worker_id(worker or "")
        ts = parse_timestamp_for_id(timestamp or "")
        p = os.path.join(ops_root, "queue", "refactor-drafts", w, f"{ts}.yaml")

    base = os.path.join(ops_root, "queue", "refactor-drafts")
    if not os.path.isfile(p):
        raise RuntimeError(f"refactor draft not found: {p}")
    if not os.path.realpath(p).startswith(os.path.realpath(base) + os.sep):
        raise RuntimeError(f"refactor draft must be under ops queue: {p}")
    worker_from_dir = os.path.basename(os.path.dirname(p))
    worker_id = validate_worker_id(worker_from_dir)
    ts_file = os.path.splitext(os.path.basename(p))[0]
    ts_compact = parse_timestamp_for_id(ts_file)
    return p, worker_id, ts_compact


def read_ops_config(ops_root: str) -> Dict[str, Any]:
    cfg_path = os.path.join(ops_root, "config.yaml")
    if not os.path.exists(cfg_path):
        return default_config_yaml()
    return read_yaml_file(cfg_path)


def select_targets(
    gh_repo: str, config: Dict[str, Any], targets: List[int]
) -> List[Dict[str, Any]]:
    if targets:
        selected: List[Dict[str, Any]] = []
        for n in targets:
            obj = gh_json(
                [
                    "-R",
                    gh_repo,
                    "issue",
                    "view",
                    str(n),
                    "--json",
                    "number,title,labels",
                ]
            )
            if not isinstance(obj, dict):
                raise RuntimeError("gh issue view must return an object")
            selected.append(obj)
        return selected

    policy = (config.get("policy") or {}).get("parallel") or {}
    require_label = bool(policy.get("require_parallel_ok_label", True))

    items = gh_json(
        [
            "-R",
            gh_repo,
            "issue",
            "list",
            "--state",
            "open",
            "--limit",
            "100",
            "--json",
            "number,title,labels",
        ]
    )
    if not isinstance(items, list):
        raise RuntimeError("gh issue list must return an array")

    out: List[Dict[str, Any]] = []
    for it in items:
        if not isinstance(it, dict):
            continue
        labels = it.get("labels") or []
        label_names = set()
        if isinstance(labels, list):
            for label in labels:
                if isinstance(label, dict):
                    name = label.get("name")
                    if name:
                        label_names.add(str(name))
        if require_label and "parallel-ok" not in label_names:
            continue
        out.append(it)
    return out


def run_worktree_check(
    toplevel: str, gh_repo: str, issues: List[int]
) -> Tuple[int, str]:
    cmd = [
        os.path.join(toplevel, "scripts", "worktree.sh"),
        "check",
        "--gh-repo",
        gh_repo,
    ]
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
    cmd = [
        "python3",
        extractor,
        "--repo-root",
        toplevel,
        "--issue",
        str(issue),
        "--gh-repo",
        gh_repo,
        "--mode",
        "section",
    ]
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode(
            "utf-8", errors="replace"
        )
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
        decision_id = (
            base_id if decision.get("decision_id") else f"{base_id}-{_DECISION_SEQ:03d}"
        )
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

    parallel_policy = (config.get("policy") or {}).get("parallel") or {}
    enabled = bool(parallel_policy.get("enabled", True))
    max_workers = int(parallel_policy.get("max_workers") or 1)
    if not enabled:
        max_workers = 1
    if max_workers < 1:
        max_workers = 1

    workers = config.get("workers") or []
    worker_ids: List[str] = []
    invalid_worker_ids: List[str] = []
    if isinstance(workers, list):
        for w in workers:
            raw: Optional[str] = None
            if isinstance(w, dict) and w.get("id"):
                raw = str(w["id"])
            elif isinstance(w, str):
                raw = w
            if raw is None:
                continue
            try:
                worker_ids.append(validate_worker_id(raw))
            except RuntimeError:
                invalid_worker_ids.append(raw)

    if invalid_worker_ids:
        decision_path = write_decision(
            ops_root,
            {
                "version": 1,
                "created_at": utc_now_iso(),
                "type": "config_invalid_workers",
                "request": {
                    "reason": "config.yaml の workers が不正（許可: A-Z a-z 0-9 _ -）",
                    "workers": invalid_worker_ids,
                },
            },
        )
        state = read_yaml_file(state_path)
        blocked = state.get("blocked")
        if not isinstance(blocked, list):
            blocked = []
            state["blocked"] = blocked
        blocked.append({"issue": None, "reason": "config_invalid_workers"})
        state["updated_at"] = utc_now_iso()
        atomic_write_yaml(state_path, state)
        atomic_write_text(dashboard_path, render_dashboard_md(state))
        sys.stdout.write(f"decision={decision_path}\n")
        return 0
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

    state = read_yaml_file(state_path)
    forbidden = [".agent/**", "docs/prd/**", "docs/epics/**"]
    issued = 0

    orders_dir = os.path.join(ops_root, "queue", "orders")
    ensure_dir(orders_dir)

    busy_phases = {"estimating", "implementing", "reviewing"}
    busy_workers: set = set()
    issues = state.get("issues") or {}
    if isinstance(issues, dict):
        for _issue_id, entry in issues.items():
            if not isinstance(entry, dict):
                continue
            assigned_to = str(entry.get("assigned_to") or "").strip()
            phase = str(entry.get("phase") or "").strip()
            if assigned_to and phase in busy_phases:
                busy_workers.add(assigned_to)

    idle_workers = [w for w in worker_ids if w not in busy_workers]
    effective_max_workers = min(max_workers, len(idle_workers))

    # Pre-extract change targets to:
    # - Emit per-issue decisions for missing/invalid targets
    # - Avoid `worktree.sh check` failing early with rc=2 for missing targets
    # - Fill up to max_workers by skipping invalid candidates and pulling additional ones
    assignable: List[Tuple[Dict[str, Any], List[str]]] = []
    for item in candidates:
        if len(assignable) >= max_workers:
            break
        n = as_int(item.get("number"), context="candidate.number")
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
                    "request": {
                        "reason": "Issue本文から変更対象ファイル（推定）を抽出できない",
                        "details": str(exc),
                    },
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
                    "request": {
                        "reason": "Issue本文から変更対象ファイル（推定）を抽出できない"
                    },
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

    # Overlap check only for issues that are actually going to be assigned.
    # Otherwise, overlap among "extra" candidates (beyond idle capacity) could block assignment.
    overlap_candidates = (
        assignable if effective_max_workers <= 0 else assignable[:effective_max_workers]
    )
    issue_numbers = [
        as_int(item.get("number"), context="overlap_candidates.number")
        for (item, _files) in overlap_candidates
    ]
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
            raise RuntimeError(
                f"worktree.sh check failed (rc={rc}):\n{check_out.strip()}"
            )

    if effective_max_workers <= 0:
        state["updated_at"] = utc_now_iso()
        atomic_write_yaml(state_path, state)
        atomic_write_text(dashboard_path, render_dashboard_md(state))
        sys.stdout.write("orders=0\n")
        return 0

    for idx, (item, allowed_files) in enumerate(assignable[:effective_max_workers]):
        n = as_int(item.get("number"), context="assignable.number")
        title = str(item.get("title") or "")
        worker = idle_workers[idx]

        entry = ensure_issue_entry(state, n)
        entry["title"] = title
        labels = [
            label.get("name")
            for label in (item.get("labels") or [])
            if isinstance(label, dict) and label.get("name")
        ]
        entry["labels"] = labels
        entry["assigned_to"] = worker
        entry["phase"] = "estimating"
        impl_policy = (config.get("policy") or {}).get("impl_mode") or {}
        default_mode = str(impl_policy.get("default") or "impl")
        force_labels = set(
            [str(x) for x in (impl_policy.get("force_tdd_labels") or [])]
        )
        impl_mode = (
            "tdd" if any(lbl in force_labels for lbl in labels) else default_mode
        )
        entry["impl_mode"] = impl_mode
        entry["progress_percent"] = entry.get("progress_percent") or 0
        entry["contract"] = {
            "allowed_files": allowed_files,
            "forbidden_files": forbidden,
        }

        slug = slugify(title)[:50]
        worktree_path = f".worktrees/issue-{n}-{slug}"
        entry["worktree"] = {"path": worktree_path}

        order_id = f"ORD-{utc_now_compact().replace('Z', '')}-{worker}-{n}"
        impl_step = "/tdd" if impl_mode == "tdd" else "/impl"
        order = {
            "version": 1,
            "order_id": order_id,
            "issued_at": utc_now_iso(),
            "worker": worker,
            "issue": n,
            "intent": f"Issue #{n} を完了（/review通過まで）",
            "impl_mode": impl_mode,
            "worktree": {"path": worktree_path},
            "contract": {"allowed_files": allowed_files, "forbidden_files": forbidden},
            "required_steps": [
                "/estimation (if not approved)",
                impl_step,
                "/review-cycle (loop until ready)",
                "/review",
                "/create-pr",
                "/cleanup",
            ],
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
    raise RuntimeError(
        f"invalid timestamp format (expected YYYYMMDDTHHMMSSZ or ISO8601Z): {value}"
    )


def utc_now_compact() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


_WORKER_ID_RE = re.compile(r"^[A-Za-z0-9_-]+$")


def validate_worker_id(value: str) -> str:
    v = (value or "").strip()
    if not v:
        raise RuntimeError("worker id is required (set --worker or AGENTIC_SDD_WORKER)")
    if not _WORKER_ID_RE.match(v):
        raise RuntimeError(f"invalid worker id: {v} (allowed: A-Z a-z 0-9 _ -)")
    return v


def detect_worker_id(explicit: Optional[str]) -> str:
    if explicit is not None:
        return validate_worker_id(explicit)
    env = os.environ.get("AGENTIC_SDD_WORKER") or os.environ.get("USER") or ""
    return validate_worker_id(env)


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
    if progress_percent < 0 or progress_percent > 100:
        raise RuntimeError(f"percent out of range (expected 0-100): {progress_percent}")

    summary = " ".join(args.summary).strip()
    if not summary:
        raise RuntimeError("summary must be non-empty")

    respond_to: Dict[str, str] = {}
    respond_to_decision_raw = str(
        getattr(args, "respond_to_decision", "") or ""
    ).strip()
    if respond_to_decision_raw:
        respond_to["decision_id"] = normalize_decision_id(respond_to_decision_raw)

    ts_compact = (
        parse_timestamp_for_id(args.timestamp) if args.timestamp else utc_now_compact()
    )
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

    requested_files: List[str] = []
    if args.request_file:
        for f in args.request_file:
            s = str(f).strip()
            if s:
                requested_files.append(s)

    blockers: List[str] = []
    if args.blocker:
        for b in args.blocker:
            s = str(b).strip()
            if s:
                blockers.append(s)

    skills: List[Dict[str, str]] = []
    skill_names: List[str] = []
    skill_summaries: List[str] = []
    if getattr(args, "skill_candidate", None):
        skill_names = [str(x) for x in (args.skill_candidate or [])]
    if getattr(args, "skill_summary", None):
        skill_summaries = [str(x) for x in (args.skill_summary or [])]

    if skill_names or skill_summaries:
        if not skill_names:
            raise RuntimeError(
                "--skill-candidate is required when --skill-summary is used"
            )
        if not skill_summaries:
            raise RuntimeError(
                "--skill-summary is required when --skill-candidate is used"
            )
        if len(skill_names) != len(skill_summaries):
            raise RuntimeError(
                f"--skill-candidate and --skill-summary counts must match: {len(skill_names)} != {len(skill_summaries)}"
            )
        for name_raw, summary_raw in zip(skill_names, skill_summaries):
            name = str(name_raw).strip()
            summary2 = str(summary_raw).strip()
            if not name:
                raise RuntimeError("skill candidate name must be non-empty")
            if not summary2:
                raise RuntimeError("skill candidate summary must be non-empty")
            skills.append({"name": name, "summary": summary2})

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
        "tests": {
            "command": args.tests_command or "",
            "result": args.tests_result or "",
        },
        "needs": {
            "approval": bool(args.needs_approval),
            "contract_expansion": {"requested_files": sorted(set(requested_files))},
            "blockers": blockers,
        },
        "next": [],
    }
    if respond_to:
        obj["respond_to"] = respond_to
    if skills:
        obj["candidates"] = {"skills": skills}

    ensure_dir(out_dir)
    atomic_write_yaml(out_path, obj)

    sys.stdout.write(out_path + "\n")
    return 0


def cmd_refactor_draft(args: argparse.Namespace) -> int:
    _abs_git_dir, common_abs, toplevel = resolve_git_dirs()
    ops_root, _state_path, _dashboard_path = ensure_ops_layout(common_abs)
    repo_root = os.path.dirname(common_abs)
    worktree_root = os.path.relpath(toplevel, repo_root)

    worker = detect_worker_id(args.worker)
    title = str(args.title or "").strip()
    if not title:
        raise RuntimeError("title must be non-empty (use --title)")

    summary = " ".join(args.summary).strip()
    if not summary:
        raise RuntimeError("summary must be non-empty")

    ts_compact = (
        parse_timestamp_for_id(args.timestamp) if args.timestamp else utc_now_compact()
    )
    ts_iso = (
        args.timestamp
        if args.timestamp and args.timestamp.endswith("Z") and "-" in args.timestamp
        else datetime.datetime.strptime(ts_compact, "%Y%m%dT%H%M%SZ")
        .replace(tzinfo=datetime.timezone.utc)
        .isoformat()
        .replace("+00:00", "Z")
    )

    smells: List[str] = []
    if getattr(args, "smell", None):
        for raw in args.smell or []:
            s = str(raw or "").strip()
            if s:
                smells.append(s)
    smells = sorted(set(smells))

    risk = str(args.risk or "").strip()
    impact = str(args.impact or "").strip()

    files: List[str] = []
    if getattr(args, "file", None):
        for raw in args.file or []:
            f = str(raw or "").strip()
            if f:
                files.append(f)
    files = sorted(set(files))

    draft_id = f"RD-{worker}-{ts_compact}"
    out_dir = os.path.join(ops_root, "queue", "refactor-drafts", worker)
    out_path = os.path.join(out_dir, f"{ts_compact}.yaml")
    if os.path.exists(out_path):
        raise RuntimeError(f"refactor draft already exists (append-only): {out_path}")

    suggested_labels: List[str] = ["refactor-candidate"]
    for s in smells:
        slug = slugify(s)
        if slug:
            suggested_labels.append(f"refactor-smell/{slug}")
    if risk:
        suggested_labels.append(f"refactor-risk/{slugify(risk) or risk}")
    if impact:
        suggested_labels.append(f"refactor-impact/{slugify(impact) or impact}")
    suggested_labels = sorted(set([x for x in suggested_labels if str(x).strip()]))

    obj: Dict[str, Any] = {
        "version": 1,
        "draft_id": draft_id,
        "timestamp": ts_iso,
        "worker": worker,
        "title": title,
        "summary": summary,
        "refactor": {
            "smells": smells,
            "risk": risk,
            "impact": impact,
            "suggested_labels": suggested_labels,
        },
        "repo": {
            "worktree_root": worktree_root,
            "toplevel": toplevel,
        },
        "targets": {"files": files},
        "next": [],
    }

    ensure_dir(out_dir)
    atomic_write_yaml(out_path, obj)
    sys.stdout.write(out_path + "\n")
    return 0


def cmd_refactor_issue(args: argparse.Namespace) -> int:
    _abs_git_dir, common_abs, toplevel = resolve_git_dirs()
    ops_root, _state_path, _dashboard_path = ensure_ops_layout(common_abs)

    gh_repo = str(args.gh_repo or "").strip()
    if not gh_repo:
        gh_repo = detect_gh_repo_from_origin(toplevel)

    draft_path, worker, ts_compact = resolve_refactor_draft_path(
        ops_root=ops_root,
        draft_path=str(args.draft or "").strip(),
        worker=str(args.worker or "").strip()
        if getattr(args, "worker", None)
        else None,
        timestamp=str(args.timestamp or "").strip()
        if getattr(args, "timestamp", None)
        else None,
    )

    # Preflight: auth must succeed before any write operations.
    gh_run(["auth", "status"])

    draft = read_yaml_file(draft_path)
    title = str(draft.get("title") or "").strip()
    if not title:
        raise RuntimeError(f"invalid refactor draft (missing title): {draft_path}")

    ref = draft.get("refactor") or {}
    suggested = ref.get("suggested_labels") or []
    labels: List[str] = []
    if isinstance(suggested, list):
        labels = [str(x).strip() for x in suggested if str(x).strip()]
    labels = sorted(set(labels))

    # Ensure our labels exist (idempotent). This may update color/description (Middle-only).
    ensure_refactor_labels(gh_repo, labels)

    body = render_refactor_issue_body(draft, draft_path=draft_path)
    fd, body_path = tempfile.mkstemp(prefix="refactor-issue-body.", suffix=".md")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(body)
        cmd = [
            "-R",
            gh_repo,
            "issue",
            "create",
            "--title",
            title,
            "--body-file",
            body_path,
        ]
        for lbl in labels:
            cmd.extend(["--label", lbl])
        out = gh_run(cmd)
        url, issue_number = parse_issue_url(out)
    finally:
        try:
            os.unlink(body_path)
        except OSError:
            pass

    # Archive draft after successful issue creation (remove from queue).
    archive_dir = os.path.join(ops_root, "archive", "refactor-drafts", worker)
    ensure_dir(archive_dir)
    archive_base = os.path.join(archive_dir, f"{ts_compact}.yaml")
    archive_path = unique_path_with_suffix(archive_base)
    os.replace(draft_path, archive_path)

    sys.stdout.write(f"repo={gh_repo}\n")
    sys.stdout.write(f"issue={issue_number}\n")
    sys.stdout.write(f"url={url}\n")
    sys.stdout.write(f"archived_draft={archive_path}\n")
    return 0


def cmd_status(_args: argparse.Namespace) -> int:
    _abs_git_dir, common_abs, _toplevel = resolve_git_dirs()
    _root, _state_path, dashboard_path = ensure_ops_layout(common_abs)
    with open(dashboard_path, "r", encoding="utf-8") as fh:
        sys.stdout.write(fh.read())
    return 0


def cmd_decision(args: argparse.Namespace) -> int:
    _abs_git_dir, common_abs, _toplevel = resolve_git_dirs()
    ops_root, _state_path, _dashboard_path = ensure_ops_layout(common_abs)

    decision_id = normalize_decision_id(str(args.id or ""))
    path = find_decision_path_anywhere(ops_root, decision_id)
    with open(path, "r", encoding="utf-8") as fh:
        sys.stdout.write(fh.read())
    return 0


def normalize_decision_id(raw: str) -> str:
    s = str(raw or "").strip()
    if s.endswith(".yaml"):
        s = s[: -len(".yaml")]
    if not s:
        raise RuntimeError(
            "decision-id must be non-empty\nnext: pass a decision-id like DEC-... (from queue/decisions)"
        )
    if "/" in s or "\\" in s:
        raise RuntimeError(
            "decision-id must not contain path separators\nnext: pass the id only (e.g. DEC-123)"
        )
    return s


def find_decision_path(ops_root: str, decision_id: str) -> str:
    decisions_dir = os.path.join(ops_root, "queue", "decisions")
    direct = os.path.join(decisions_dir, f"{decision_id}.yaml")
    if os.path.isfile(direct):
        return direct

    # Fallback: search by decision_id field (if the filename does not match)
    for path in list_decision_paths(ops_root):
        obj = read_yaml_file(path)
        if not isinstance(obj, dict):
            continue
        if str(obj.get("decision_id") or "").strip() == decision_id:
            return path

    raise RuntimeError(
        f"decision not found: {decision_id}\n"
        "next: ensure a decision file exists under queue/decisions (e.g. run /collect to generate it)"
    )


def find_decision_path_anywhere(ops_root: str, decision_id: str) -> str:
    queue_dir = os.path.join(ops_root, "queue", "decisions")
    archive_dir = os.path.join(ops_root, "archive", "decisions")

    direct_queue = os.path.join(queue_dir, f"{decision_id}.yaml")
    if os.path.isfile(direct_queue):
        return direct_queue
    direct_archive = os.path.join(archive_dir, f"{decision_id}.yaml")
    if os.path.isfile(direct_archive):
        return direct_archive

    # Fallback: scan both queue and archive by decision_id field (handles archive suffixes).
    for path in list_decision_paths(ops_root) + list_archived_decision_paths(ops_root):
        obj = read_yaml_file(path)
        if not isinstance(obj, dict):
            continue
        if str(obj.get("decision_id") or "").strip() == decision_id:
            return path

    raise RuntimeError(
        f"decision not found: {decision_id}\n"
        "next: ensure a decision file exists under queue/decisions or archive/decisions (e.g. run /collect to generate it)"
    )


def validate_skill_name(name: str) -> str:
    s = str(name or "").strip()
    if not s:
        raise RuntimeError(
            "invalid decision payload: missing request.name\nnext: set request.name to a slug like 'my-skill'"
        )
    safe = slugify(s)
    if safe != s:
        raise RuntimeError(
            f"invalid skill name: {s}\n"
            "next: use lowercase letters/numbers and hyphens only (e.g. 'contract-expansion-triage')"
        )
    return s


def render_skill_template_md(name: str, summary: str) -> str:
    summary = str(summary or "").strip()
    return (
        f"# {name}\n"
        "\n"
        "## Overview\n"
        f"{summary}\n"
        "\n"
        "## Principles\n"
        "- TBD\n"
        "\n"
        "## Patterns\n"
        "- TBD\n"
        "\n"
        "## Checklist\n"
        "- [ ] TBD\n"
        "\n"
        "## Anti-patterns\n"
        "- TBD\n"
        "\n"
        "## Related\n"
        "- TBD\n"
    )


def compute_skills_readme_update(readme_text: str, name: str, summary: str) -> str:
    link = f"- [{name}.md](./{name}.md): {summary}".rstrip()
    if f"](./{name}.md)" in readme_text:
        raise RuntimeError(
            f"skills/README.md already references: {name}.md\n"
            "next: pick a different skill name or remove the existing reference"
        )

    lines = readme_text.splitlines(True)
    section_idx = -1
    for i, ln in enumerate(lines):
        if ln.strip() == "### Process Skills":
            section_idx = i
            break
    if section_idx < 0:
        raise RuntimeError(
            "skills/README.md is missing section: '### Process Skills'\n"
            "next: add that section (or update this tool to target another section)"
        )

    insert_at = len(lines)
    for j in range(section_idx + 1, len(lines)):
        t = lines[j].strip()
        if t.startswith("### ") or t.startswith("## ") or t == "---":
            insert_at = j
            break

    # Insert at end of "Process Skills" section (before trailing blank lines).
    while insert_at > section_idx + 1 and lines[insert_at - 1].strip() == "":
        insert_at -= 1
    lines.insert(insert_at, link + "\n")
    return "".join(lines)


def cmd_skill(args: argparse.Namespace) -> int:
    _abs_git_dir, common_abs, toplevel = resolve_git_dirs()
    ops_root, _state_path, _dashboard_path = ensure_ops_layout(common_abs)

    decision_id = normalize_decision_id(args.approve)
    decision_path = find_decision_path(ops_root, decision_id)
    decision = read_yaml_file(decision_path)
    if not isinstance(decision, dict):
        raise RuntimeError(
            f"invalid decision YAML (expected mapping): {decision_path}\nnext: recreate the decision YAML"
        )

    dtype = str(decision.get("type") or "").strip()
    if dtype != "skill_candidate":
        raise RuntimeError(
            f"decision type mismatch (expected skill_candidate): {dtype or '(missing)'}\n"
            "next: choose a decision with type=skill_candidate"
        )

    request = decision.get("request") or {}
    if not isinstance(request, dict):
        raise RuntimeError(
            "invalid decision payload: request must be a mapping\nnext: set decision.request fields"
        )

    name = validate_skill_name(str(request.get("name") or ""))
    summary = str(request.get("summary") or "").strip()
    if not summary:
        raise RuntimeError(
            "invalid decision payload: missing request.summary\nnext: set request.summary (short description for README)"
        )

    skills_dir = os.path.join(toplevel, "skills")
    skill_md_rel = os.path.join("skills", f"{name}.md")
    skill_md_path = os.path.join(toplevel, skill_md_rel)
    readme_rel = os.path.join("skills", "README.md")
    readme_path = os.path.join(toplevel, readme_rel)

    if not os.path.isfile(readme_path):
        raise RuntimeError(
            f"missing {readme_rel}\nnext: create it (must include '### Process Skills' section)"
        )
    if os.path.exists(skill_md_path):
        raise RuntimeError(
            f"skill file already exists: {skill_md_rel}\nnext: choose a different name (no overwrite)"
        )

    ensure_dir(skills_dir)
    with open(readme_path, "r", encoding="utf-8") as fh:
        readme_text = fh.read()
    new_readme = compute_skills_readme_update(readme_text, name=name, summary=summary)

    # Write skill file first (no overwrite), then update README.
    atomic_write_text(
        skill_md_path, render_skill_template_md(name=name, summary=summary)
    )
    try:
        atomic_write_text(readme_path, new_readme)
    except Exception:
        try:
            os.unlink(skill_md_path)
        except OSError:
            pass
        raise

    archive_dir = os.path.join(ops_root, "archive", "decisions")
    ensure_dir(archive_dir)
    archive_base = os.path.join(archive_dir, os.path.basename(decision_path))
    archive_path = unique_path_with_suffix(archive_base)
    os.replace(decision_path, archive_path)

    sys.stdout.write(f"skill={skill_md_rel}\n")
    sys.stdout.write(f"readme={readme_rel}\n")
    sys.stdout.write(f"archived_decision={archive_path}\n")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="shogun-ops.py", description="Agentic-SDD Shogun Ops helper"
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("checkin", help="Create an append-only checkin YAML")
    c.add_argument("issue", type=int, help="Issue number")
    phases = ["backlog", "estimating", "implementing", "reviewing", "blocked", "done"]
    c.add_argument(
        "phase",
        choices=phases,
        help="backlog|estimating|implementing|reviewing|blocked|done",
    )
    c.add_argument("percent", type=int, help="Progress percent (0-100)")
    c.add_argument(
        "summary",
        nargs="+",
        help="Summary text (use `--` before summary if passing flags)",
    )
    c.add_argument("--worker", help="Worker id (default: $AGENTIC_SDD_WORKER or $USER)")
    c.add_argument(
        "--timestamp", help="Override timestamp (YYYYMMDDTHHMMSSZ or ISO8601Z)"
    )
    c.add_argument(
        "--no-auto-files-changed", dest="auto_files_changed", action="store_false"
    )
    c.add_argument(
        "--auto-files-changed", dest="auto_files_changed", action="store_true"
    )
    c.set_defaults(auto_files_changed=True)
    c.add_argument(
        "--include-staged",
        action="store_true",
        help="Include staged changes in files_changed",
    )
    c.add_argument(
        "--files-changed",
        action="append",
        help="Additional files_changed entry (repeatable)",
    )
    c.add_argument("--tests-command", help="Test command to record (optional)")
    c.add_argument(
        "--tests-result",
        choices=["pass", "fail", "skip"],
        help="Test result to record (optional)",
    )
    c.add_argument(
        "--needs-approval",
        action="store_true",
        help="Set needs.approval=true (approval required)",
    )
    c.add_argument(
        "--request-file",
        action="append",
        help="Append to needs.contract_expansion.requested_files (repeatable)",
    )
    c.add_argument(
        "--blocker",
        action="append",
        help="Append blocker reason to needs.blockers (repeatable)",
    )
    c.add_argument(
        "--respond-to-decision",
        help="Decision id to respond to (e.g. DEC-... or DEC-....yaml)",
    )
    c.add_argument(
        "--skill-candidate",
        action="append",
        help="Skill candidate name (repeatable; requires --skill-summary)",
    )
    c.add_argument(
        "--skill-summary",
        action="append",
        help="Skill candidate summary (repeatable; must match --skill-candidate count)",
    )
    c.set_defaults(func=cmd_checkin)

    rd = sub.add_parser(
        "refactor-draft",
        help="Create a refactor draft YAML (Lower-only; no GitHub writes)",
    )
    rd.add_argument("--title", required=True, help="Draft title (required)")
    rd.add_argument(
        "summary",
        nargs="+",
        help="Summary text (use `--` before summary if passing flags)",
    )
    rd.add_argument(
        "--worker", help="Worker id (default: $AGENTIC_SDD_WORKER or $USER)"
    )
    rd.add_argument(
        "--timestamp", help="Override timestamp (YYYYMMDDTHHMMSSZ or ISO8601Z)"
    )
    rd.add_argument(
        "--smell", action="append", help="Qualitative smell tag (repeatable)"
    )
    rd.add_argument("--risk", help="Qualitative risk (e.g., low|med|high)")
    rd.add_argument("--impact", help="Qualitative impact (e.g., local|cross-module)")
    rd.add_argument(
        "--file", action="append", help="Suspected target file path (repeatable)"
    )
    rd.set_defaults(func=cmd_refactor_draft)

    ri = sub.add_parser(
        "refactor-issue",
        help="Create a GitHub Issue from a refactor draft (Middle-only)",
    )
    ri.add_argument("--gh-repo", help="OWNER/REPO (default: derived from origin)")
    ri.add_argument("--draft", help="Path to a refactor draft YAML (under ops queue)")
    ri.add_argument("--worker", help="Worker id (when resolving draft path)")
    ri.add_argument(
        "--timestamp",
        help="Draft timestamp (YYYYMMDDTHHMMSSZ or ISO8601Z; when resolving draft path)",
    )
    ri.set_defaults(func=cmd_refactor_issue)

    col = sub.add_parser(
        "collect", help="Collect checkins and update state/dashboard (single-writer)"
    )
    col.set_defaults(func=cmd_collect)

    sup = sub.add_parser("supervise", help="Supervise issues and emit orders/decisions")
    sup.add_argument("--once", action="store_true", help="Run one cycle (required)")
    sup.add_argument("--gh-repo", help="OWNER/REPO (default: derived from origin)")
    sup.add_argument(
        "--targets", type=int, action="append", help="Target Issue number (repeatable)"
    )
    sup.set_defaults(func=cmd_supervise)

    sk = sub.add_parser(
        "skill", help="Approve skill_candidate decision and generate skills docs"
    )
    sk.add_argument(
        "--approve", required=True, help="Decision id (from queue/decisions)"
    )
    sk.set_defaults(func=cmd_skill)

    s = sub.add_parser("status", help="Show ops dashboard (initializes if missing)")
    s.set_defaults(func=cmd_status)

    d = sub.add_parser("decision", help="Show a decision YAML by id (queue or archive)")
    d.add_argument("--id", required=True, help="Decision id (DEC-...)")
    d.set_defaults(func=cmd_decision)
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
