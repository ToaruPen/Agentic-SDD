# Releasing

This repository publishes GitHub Releases on tag push.

Trigger:
- Push a git tag (recommended: `vX.Y.Z`)

Automation:
- GitHub Actions workflow: `release`

## Create a release

1. Update `CHANGELOG.md`.
2. Update pinned defaults to the new tag:
   - `scripts/agentic-sdd` (`DEFAULT_REF_FALLBACK`)
3. Create and push a tag:

```bash
git tag X.Y.Z
git push origin X.Y.Z
```

Notes:

- `vX.Y.Z` is also supported.

4. GitHub Actions `release` workflow creates/updates the GitHub Release and uploads:

- `agentic-sdd` (helper CLI)
- `agentic-sdd-<tag>-template.tar.gz`
- `agentic-sdd-<tag>-template.zip`
- `SHA256SUMS.txt`

Notes:

- The template bundle excludes this repo's `.github/workflows/*` (they are for Agentic-SDD itself).
- CI templates live under `templates/ci/` and are installed into a target repo only when opt-in options (e.g. `--ci github-actions`) are used.
