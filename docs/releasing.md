# Releasing

This repository publishes GitHub Releases on tag push.

## Create a release

1) Update `CHANGELOG.md`.
2) Create and push a tag:

```bash
git tag X.Y.Z
git push origin X.Y.Z
```

Notes:

- `vX.Y.Z` is also supported.

3) GitHub Actions `release` workflow creates/updates the GitHub Release and uploads:

- `agentic-sdd` (helper CLI)
- `agentic-sdd-<tag>-template.tar.gz`
- `agentic-sdd-<tag>-template.zip`
- `SHA256SUMS.txt`
