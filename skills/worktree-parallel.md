# Worktree Parallel Skill

Deterministic guardrails and patterns for parallel implementation using `git worktree`.

This is about reducing merge conflicts and "semantic drift" (two parallel changes that compile
but contradict each other).

---

## Overview

`git worktree` enables parallel development by creating multiple working directories that share
the same `.git` database.

Worktrees do NOT automatically prevent conflicts. Conflict prevention is achieved by:

1. Splitting Issues so that change targets are disjoint
2. Declaring dependencies (blocked vs parallel-ok)
3. Merging incrementally (finish one, merge one)

Agentic-SDD is designed to support this by requiring each Issue to declare its estimated change
targets (files) and dependencies.

---

## Principles

1. One Issue = one branch = one worktree
2. `parallel-ok` requires known, disjoint change targets
3. If change targets are unknown, do NOT parallelize (mark `blocked`)
4. Serialize SoT changes (PRD/Epic): do not edit them across parallel branches
5. Prefer "append-only" changes for shared files

---

## Deterministic parallel criteria

Treat an Issue as eligible for parallel work ONLY when:

- The Issue body includes `### 変更対象ファイル（推定）` with repo-relative paths.
- The set of declared files does NOT overlap with other parallel Issues.

Use `./scripts/worktree.sh check ...` to validate overlap before starting.

---

## Patterns

### Pattern: Hotspot-first (serialize)

When a shared "hotspot" file must change (routing, shared config, core types, DI wiring):

1. Create a single "foundation" Issue that touches the hotspot
2. Merge it first
3. Block dependent Issues until it is merged

### Pattern: Append-only shared file

When multiple Issues must touch a shared file, enforce "append-only":

- Only add new exports/handlers/entries
- Do not reorder existing items
- Avoid renames

If you cannot guarantee append-only, serialize.

### Pattern: Tight change-target contract

Treat the Issue's declared file list as a contract.

- If implementation needs additional files, stop and re-evaluate parallel status.
- Update the Issue body (or mark as blocked) before continuing.

---

## Checklist

- [ ] Each Issue declares `### 変更対象ファイル（推定）` (repo-relative paths)
- [ ] Each Issue declares dependencies (`Blocked by` + what becomes possible)
- [ ] `./scripts/worktree.sh check ...` reports no overlaps
- [ ] One worktree per Issue created (`./scripts/worktree.sh new ...`)
- [ ] Tool configs generated per worktree (OpenCode/Codex) if needed
- [ ] Each Issue passes `/review` (DoD + `/sync-docs`) before merge

---

## Anti-patterns

- Parallel Issues editing the same file/area without explicit serialization
- Mixing PRD/Epic edits across multiple parallel branches
- "Hidden" change targets (Issue does not declare files; later changes expand scope)
- Large refactors attempted in parallel

---

## Related

- `.agent/rules/issue.md` - dependency + labels
- `.agent/rules/branch.md` - branch naming
- `.agent/commands/worktree.md` - command definition
- `scripts/worktree.sh` - deterministic wrapper
