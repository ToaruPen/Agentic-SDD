# /generate-project-config

Generate project-specific skills/rules from an Epic.

## Usage

```
/generate-project-config [epic-file]
```

## Overview

Based on the Epic decisions (tech choices and PRD Q6 requirements), generate project-specific skills/rules.

Generated files:
- `.agentic-sdd/project/config.json`: project config (always generated)
- `.agentic-sdd/project/skills/tech-stack.md`: tech stack guide (when the Epic includes tech selection)
- `.agentic-sdd/project/rules/security.md`: security rules (when Q6-5 = Yes)
- `.agentic-sdd/project/rules/performance.md`: performance rules (when Q6-7 = Yes)
- `.agentic-sdd/project/rules/api-conventions.md`: API conventions (when the Epic includes API design)

Notes (user-facing artifacts remain Japanese; these files are project-local guidance):
- `.agentic-sdd/project/config.json`: project config (always generated)
- `.agentic-sdd/project/skills/tech-stack.md`: tech stack guide (when the Epic includes tech selection)
- `.agentic-sdd/project/rules/security.md`: security rules (when Q6-5 = Yes)
- `.agentic-sdd/project/rules/performance.md`: performance rules (when Q6-7 = Yes)
- `.agentic-sdd/project/rules/api-conventions.md`: API conventions (when the Epic includes API design)

## Flow

### Phase 1: Load the Epic file

1. Read the specified Epic file
2. If the file does not exist, fail

### Phase 2: Extract inputs

Use `scripts/extract-epic-config.py` to extract:

1. Tech selection (section 3.2)
   - language, framework, database, infrastructure
2. PRD Q6 requirements (section 5)
   - Q6-5: security
   - Q6-6: observability
   - Q6-7: performance
   - Q6-8: availability
3. API design (section 3.4)
   - endpoint list

### Phase 3: Select templates

Select templates based on extracted inputs:

| Condition | Generated file |
|------|-------------|
| Tech selection exists | `.agentic-sdd/project/skills/tech-stack.md` |
| Q6-5 = Yes | `.agentic-sdd/project/rules/security.md` |
| Q6-7 = Yes | `.agentic-sdd/project/rules/performance.md` |
| API design exists | `.agentic-sdd/project/rules/api-conventions.md` |

### Phase 4: Render templates and write files

Use `scripts/generate-project-config.py`:

1. Load template files
2. Render via Jinja2 variables
3. Write outputs under `.agentic-sdd/project/`

### Phase 5: Review generated outputs

1. Print the list of generated files
2. Print a short summary per file
3. Ask the user to confirm

## Output

```
.agentic-sdd/project/
├── config.json
├── skills/
│   └── tech-stack.md
└── rules/
    ├── security.md
    ├── performance.md
    └── api-conventions.md
```

## Example

```bash
# Generate directly from an Epic file
python scripts/generate-project-config.py docs/epics/my-project-epic.md

# Split extraction and generation
python scripts/extract-epic-config.py docs/epics/my-project-epic.md -o /tmp/config.json
python scripts/generate-project-config.py /tmp/config.json

# Dry-run (preview generated files)
python scripts/generate-project-config.py docs/epics/my-project-epic.md --dry-run
```

## Notes

- Outputs are template-based; project-specific details still require manual edits.
- Generic rules live under `.agent/rules/`; generated rules are project-specific supplements.
- Existing files may be overwritten.

## Related

- `.agent/commands/create-epic.md` - Epic creation command
- `.agent/rules/security.md` - Generic security rules
- `.agent/rules/performance.md` - Generic performance rules
 - `templates/project-config/` - template files

## Next command

After generation, review/edit the generated files as needed, then run `/create-issues` to split into Issues.
