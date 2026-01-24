# API Endpoint Design Skill

Guidelines and checklists for designing and implementing REST API endpoints.

Language/framework-agnostic; concept-based.

---

## Principles

### 1) Resource-oriented

- URLs represent resources (nouns)
- Operations are expressed by HTTP methods

```
GET    /users      # list users
GET    /users/:id  # get a user
POST   /users      # create a user
PUT    /users/:id  # replace a user
PATCH  /users/:id  # update a user
DELETE /users/:id  # delete a user
```

### 2) Consistency

- Consistent naming (plural, kebab-case, etc)
- Consistent response envelope
- Consistent error format

### 3) Stateless

- No server-side session state
- Auth context is provided per request

---

## URL design

Basic patterns:

- `/resources`: collection (e.g. `/users`)
- `/resources/:id`: single resource (e.g. `/users/123`)
- `/resources/:id/sub-resources`: nested resources (e.g. `/users/123/posts`)

Naming conventions:

- Preferred: `/users`; avoid: `/user` (use plural)
- Preferred: `/user-profiles`; avoid: `/userProfiles` (use kebab-case)
- Preferred: `/users/123`; avoid: `/users?id=123` (use path params)

Query parameters:

- Pagination: `page`, `limit` (e.g. `?page=2&limit=20`)
- Sorting: `sort`, `order` (e.g. `?sort=created_at&order=desc`)
- Filtering: field names (e.g. `?status=active`)
- Search: `q` / `search` (e.g. `?q=keyword`)

---

## HTTP methods

- GET: read (idempotent: yes / safe: yes)
- POST: create (idempotent: no / safe: no)
- PUT: replace (idempotent: yes / safe: no)
- PATCH: update (idempotent: no / safe: no)
- DELETE: delete (idempotent: yes / safe: no)

---

## Status codes

Success:

- 200: success with body (GET, PUT, PATCH)
- 201: created (POST)
- 204: success without body (DELETE)

Client errors:

- 400: bad request (validation)
- 401: unauthenticated
- 403: unauthorized
- 404: not found
- 409: conflict (duplicate)
- 422: unprocessable (business rule)

Server errors:

- 500: unexpected error
- 502: bad gateway (upstream error)
- 503: service unavailable

---

## Request/response format

Request body:

```json
{
  "name": "John Doe",
  "email": "john@example.com"
}
```

Success response (single):

```json
{
  "data": {
    "id": "123",
    "name": "John Doe",
    "email": "john@example.com",
    "createdAt": "2024-03-15T10:30:00Z"
  }
}
```

Success response (list):

```json
{
  "data": [
    { "id": "123", "name": "John Doe" },
    { "id": "124", "name": "Jane Doe" }
  ],
  "meta": {
    "total": 100,
    "page": 1,
    "limit": 20
  }
}
```

Error response:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid input.",
    "details": [
      { "field": "email", "message": "Email format is invalid." }
    ]
  }
}
```

---

## Checklist

Design:

- [ ] URL is resource-oriented
- [ ] HTTP methods are appropriate
- [ ] Status codes are appropriate
- [ ] Request/response format is consistent
- [ ] Error format is defined

Implementation:

- [ ] Input validation exists
- [ ] AuthN/AuthZ exists (when applicable)
- [ ] Error handling exists
- [ ] Logging is appropriate
- [ ] Tests exist

Security:

- [ ] Inputs are sanitized
- [ ] SQL injection is considered
- [ ] XSS is considered
- [ ] Rate limiting is considered (when applicable)
- [ ] No secrets/PII leak in responses

---

## Anti-patterns

- Verb in URL: `/getUsers` -> `GET /users`
- Using POST for everything: unclear intent -> use appropriate methods
- Always returning 200: hard to distinguish errors -> use proper codes
- Always returning detailed errors: security risk -> keep prod errors minimal

---

## Related

- `skills/error-handling.md` - error handling
- `skills/testing.md` - testing
- `.agent/rules/dod.md` - Definition of Done
