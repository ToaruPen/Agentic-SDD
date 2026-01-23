# Releasing

This repository publishes GitHub Releases on tag push.

## Create a release

1) Update `CHANGELOG.md`.
2) Create and push a tag:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

3) GitHub Actions `release` workflow creates/updates the GitHub Release and uploads:

- `agentic-sdd` (helper CLI)
- `agentic-sdd-vX.Y.Z-template.tar.gz`
- `agentic-sdd-vX.Y.Z-template.zip`
- `SHA256SUMS.txt`
