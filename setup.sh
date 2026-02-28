#!/usr/bin/env bash
# setup.sh — Codex remote environment bootstrap for Agentic-SDD
# This script is executed automatically by ChatGPT Codex after cloning the repo.
# Target: Debian/Ubuntu-based container (Codex default).
set -euo pipefail

echo "=== Agentic-SDD: Codex remote environment setup ==="

# ── Python dependencies ──────────────────────────────────────────────
echo "[1/5] Installing Python packages..."
python3 -m pip install --quiet --upgrade pip
python3 -m pip install --quiet -r requirements-dev.txt
python3 -m pip install --quiet -r requirements-agentic-sdd.txt

# ── System tools (shellcheck, ripgrep) ───────────────────────────────
echo "[2/5] Installing shellcheck and ripgrep..."
if ! command -v shellcheck >/dev/null 2>&1 || ! command -v rg >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq shellcheck ripgrep
fi

# ── actionlint ───────────────────────────────────────────────────────
echo "[3/5] Installing actionlint..."
if ! command -v actionlint >/dev/null 2>&1 && [ ! -f ./actionlint ]; then
  version="1.6.27"
  asset="actionlint_${version}_linux_amd64.tar.gz"
  sha256="5c9b6e5418f688b7f7c7e3d40c13d9e41b1ca45fb6a2c35788b0580e34b7300f"
  url="https://github.com/rhysd/actionlint/releases/download/v${version}/${asset}"

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  curl -fsSL "$url" -o "$tmpdir/$asset"
  echo "${sha256}  $tmpdir/$asset" | sha256sum -c -
  tar -xzf "$tmpdir/$asset" -C "$tmpdir"
  install -m 0755 "$tmpdir/actionlint" /usr/local/bin/actionlint
  trap - EXIT
  rm -rf "$tmpdir"
fi

# ── GitHub CLI (gh) ──────────────────────────────────────────────────
echo "[4/5] Checking GitHub CLI..."
if ! command -v gh >/dev/null 2>&1; then
  echo "  Installing gh..."
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq gh
fi

# ── Git hooks ────────────────────────────────────────────────────────
echo "[5/5] Setting up git hooks..."
if [ -f scripts/setup-githooks.sh ]; then
  bash scripts/setup-githooks.sh
else
  git config core.hooksPath .githooks 2>/dev/null || true
fi

echo "=== Setup complete ==="
