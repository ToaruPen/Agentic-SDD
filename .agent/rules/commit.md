# Commit Message Rules

Commit message conventions based on Conventional Commits.

---

## Base format

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

---

## Type (required)

- `feat`: new feature
- `fix`: bug fix
- `docs`: documentation only
- `style`: formatting only (no semantic change)
- `refactor`: refactor (no bug fix / no feature)
- `perf`: performance improvement
- `test`: add/update tests
- `build`: build system / dependencies
- `ci`: CI changes
- `chore`: misc (no src/test changes)
- `revert`: revert a previous commit

---

## Scope (optional)

Scope indicates the area of change (project-defined).

```
feat(api): add user registration endpoint
fix(ui): correct button alignment
docs(readme): update installation instructions
```

---

## Description (required)

- Use imperative mood ("add" not "added")
- Start with lowercase
- No trailing period
- Keep within ~50 chars

Good:

```
feat(auth): add password reset functionality
fix(api): handle null response from external service
refactor(utils): extract validation logic to separate module
```

Bad:

```
feat(auth): Added password reset functionality.
fix: bug fix
Update code
```

---

## Body (optional)

Use the body to explain "why" and notable details.

```
feat(auth): add password reset functionality

Users can now reset their password via email.
The reset link expires after 24 hours.

Closes #123
```

---

## Footer (optional)

Breaking changes:

```
feat(api)!: change response format for user endpoint

BREAKING CHANGE: The user endpoint now returns an array instead of an object.
```

Issue references:

```
fix(cart): correct total calculation

Fixes #456
Closes #789
```

---

## Examples

Feature:

```
feat(user): add profile picture upload

- Support JPEG and PNG formats
- Max file size: 5MB
- Auto-resize to 200x200

Closes #234
```

Bug fix:

```
fix(payment): correct tax calculation for international orders

The tax rate was incorrectly applied to shipping costs.
Now only product prices are taxed.

Fixes #567
```

Refactor:

```
refactor(api): extract authentication middleware

- Move auth logic from routes to middleware
- Add unit tests for middleware
- No functional changes
```

Docs:

```
docs(contributing): add commit message guidelines
```

---

## Commit granularity

Principles:

- One commit = one logical change
- Commit in a working state
- Keep reviewable size

Split examples:

- Feature + bug fix: split into feature and fix/test commits
- Refactor + feature: split into a refactor-only commit and a feature commit
- Multiple independent fixes: split per problem

---

## Related

- `.agent/rules/branch.md` - branch naming rules
- `.agent/rules/datetime.md` - datetime formatting rules
