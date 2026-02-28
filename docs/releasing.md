# Releasing

This repository publishes GitHub Releases on tag push.

Trigger:
- Push a git tag (recommended: `vX.Y.Z.W`)

Automation:
- GitHub Actions workflow: `release`

## Create a release

1. Update `CHANGELOG.md`.
2. Update release resolver/docs references to the new tag:
   - `scripts/agentic-sdd` latest semver matcher + fail-fast behavior (`--ref latest` must not fallback)
   - `README.md` subtree update examples (`git subtree add/pull`, `update-agentic-sdd.sh --ref`)
   - `scripts/update-agentic-sdd.sh` usage example ref
3. Create and push a tag:

```bash
git tag v0.4.0.0
git push origin v0.4.0.0
```

Notes:

- Supported tag formats: `vX.Y.Z`, `X.Y.Z`, `vX.Y.Z.W`, `X.Y.Z.W`.

4. GitHub Actions `release` workflow creates/updates the GitHub Release and uploads:

- `agentic-sdd` (helper CLI)
- `agentic-sdd-<tag>-template.tar.gz`
- `agentic-sdd-<tag>-template.zip`
- `SHA256SUMS.txt`

Notes:

- The template bundle excludes this repo's `.github/workflows/*` (they are for Agentic-SDD itself).
- CI templates live under `templates/ci/` and are installed into a target repo only when opt-in options (e.g. `--ci github-actions`) are used.

## Downstream subtree update runbook

For repositories that already imported Agentic-SDD with a fixed subtree prefix:

```bash
git subtree pull --prefix=.agentic-sdd-upstream https://github.com/ToaruPen/Agentic-SDD.git v0.4.0.0 --squash
```

Or use the helper script from the imported subtree:

```bash
./.agentic-sdd-upstream/scripts/update-agentic-sdd.sh --ref v0.4.0.0
```
