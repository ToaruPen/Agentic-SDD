#!/usr/bin/env bash

set -euo pipefail

eprint() { printf '%s\n' "$*" >&2; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$repo_root/templates/ci/github-actions/.github/workflows/agentic-sdd-gc.yml"

if [[ ! -f "$src" ]]; then
	eprint "Missing GC template: $src"
	exit 1
fi

# Validate YAML structure and GC template contract via Python (stdlib only; no PyYAML dependency)
python3 - "$src" <<'PYEOF'
import re, sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    lines = f.readlines()

errors = []

# Strip comment-only lines for content checks
content_lines = [l for l in lines if not l.lstrip().startswith('#')]
content = ''.join(content_lines)
full_text = ''.join(lines)

# --- YAML structure ---

# First non-blank, non-comment line must be a top-level key or YAML document marker
first_content = next((l for l in lines if l.strip() and not l.strip().startswith('#')), '')
if not re.match(r'^([a-zA-Z]|---)', first_content):
    errors.append('First content line must start with a top-level key or YAML document marker (---)')

# No tabs (YAML forbids tab indentation)
for i, line in enumerate(lines, 1):
    if '\t' in line.split('#', 1)[0]:  # ignore tabs inside comments
        errors.append(f'Line {i}: tab character in indentation')

# Indentation must be spaces in multiples of 2
for i, line in enumerate(lines, 1):
    stripped = line.rstrip('\n')
    if not stripped or stripped.lstrip() == stripped:
        continue  # skip blank/top-level lines
    indent = len(stripped) - len(stripped.lstrip())
    if indent % 2 != 0:
        errors.append(f'Line {i}: odd indentation ({indent} spaces)')

# --- Required top-level keys (anchored to line start) ---

for required_key in ['name:', 'on:', 'jobs:']:
    if not re.search(rf'^{re.escape(required_key)}', content, re.MULTILINE):
        errors.append(f'Missing top-level key: {required_key}')

# Extract the jobs block (from 'jobs:' to the next top-level key or EOF)
# Top-level keys start at column 0; everything indented belongs to jobs.
jobs_match = re.search(
    r'^jobs:\s*\n((?:\s+.*\n|\s*\n)*)',
    content, re.MULTILINE,
)
if not jobs_match:
    errors.append('Could not extract jobs block from template')
else:
    jobs_block = jobs_match.group(1)
    # steps: must appear as an indented key within the jobs block
    if not re.search(r'^\s+steps:\s*$', jobs_block, re.MULTILINE):
        errors.append('No steps: key found inside jobs block')
    # At least one step must contain run: or uses:
    if not re.search(r'^\s+(run:|uses:)', jobs_block, re.MULTILINE):
        errors.append('No run: or uses: entry found inside jobs steps')

# --- GC template contract (non-comment lines only) ---

# Must reference lint-sot.py in a run: block (not just in comments)
if not re.search(r'lint-sot\.py', content):
    errors.append('GC template does not reference lint-sot.py in non-comment lines')

# Must write to GITHUB_STEP_SUMMARY in non-comment lines
if not re.search(r'GITHUB_STEP_SUMMARY', content):
    errors.append('GC template does not write to GITHUB_STEP_SUMMARY in non-comment lines')

# --- GITHUB_STEP_SUMMARY contract ---
# Extract text actually redirected to GITHUB_STEP_SUMMARY:
#   1. Single-line:  echo '...' >> "$GITHUB_STEP_SUMMARY"
#   2. Group block:  { echo '...'; ... } >> "$GITHUB_STEP_SUMMARY"
summary_text_parts = []

# Single-line redirects
for m in re.finditer(
    r'^(.*>>\s*"?\$GITHUB_STEP_SUMMARY"?.*)$', content, re.MULTILINE,
):
    summary_text_parts.append(m.group(1))

# Group redirects: { ... } >> "$GITHUB_STEP_SUMMARY"
for m in re.finditer(
    r'\{([^}]*)\}\s*>>\s*"?\$GITHUB_STEP_SUMMARY"?', content, re.DOTALL,
):
    summary_text_parts.append(m.group(1))

summary_text = '\n'.join(summary_text_parts)

if not summary_text:
    errors.append('No content redirected to GITHUB_STEP_SUMMARY')

if 'passed' not in summary_text:
    errors.append('Success summary (passed) not found in GITHUB_STEP_SUMMARY output')
if 'FAILED' not in summary_text:
    errors.append('Failure summary (FAILED) not found in GITHUB_STEP_SUMMARY output')

if errors:
    for e in errors:
        print(f'YAML validation: {e}', file=sys.stderr)
    sys.exit(1)
PYEOF

eprint "OK: scripts/tests/test-gc-template.sh"
