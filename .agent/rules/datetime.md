# Datetime Formatting Rules

Rules for consistent date/time formatting in docs and code.

---

## Base formats

### Date

```
YYYY-MM-DD
```

Example: `2024-03-15`

### Timestamp

```
YYYY-MM-DDTHH:mm:ssZ        # UTC
YYYY-MM-DDTHH:mm:ss+09:00   # JST
```

Examples:

- `2024-03-15T10:30:00Z` (UTC)
- `2024-03-15T19:30:00+09:00` (JST)

---

## Where to use

- Document dates: `YYYY-MM-DD`
- Commit messages: not needed (git provides timestamps)
- Logs: ISO 8601 (prefer UTC)
- API responses: ISO 8601 (prefer UTC)
- Filenames: `YYYYMMDD` or `YYYY-MM-DD` (e.g. `20240315` / `2024-03-15`)

---

## Time zones

Principles:

- Use UTC as the default
- If you use local time, include the offset explicitly

Notation:

- `Z`: UTC (+00:00)
- `+09:00`: JST
- `+00:00`: explicit UTC

---

## In documents

PRD / Epic / Issue:

```markdown
## メタ情報

- 作成日: 2024-03-15
- 更新日: 2024-03-20
```

Change log:

```markdown
## 変更履歴

- 2024-03-15: v1.0 初版作成
- 2024-03-20: v1.1 AC追加
```

---

## In code

Preferred:

```typescript
// ISO 8601 (UTC)
const timestamp = new Date().toISOString();
// => "2024-03-15T10:30:00.000Z"
```

Not recommended:

```typescript
// Local time (timezone not explicit)
const timestamp = new Date().toString();
// => "Fri Mar 15 2024 19:30:00 GMT+0900 (Japan Standard Time)"
```

---

## Forbidden formats

- `03/15/2024`: ambiguous (MM/DD vs DD/MM) -> `2024-03-15`
- `15-Mar-2024`: hard to parse -> `2024-03-15`
- `2024年3月15日`: locale-dependent -> `2024-03-15`
- Time without timezone: ambiguous -> add `Z` or `+09:00`

---

## Related

- `.agent/rules/commit.md` - commit message rules
- `docs/prd/_template.md` - PRD template
