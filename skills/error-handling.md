# Error Handling Skill

Guidelines for designing error classification, handling, logging, and user messaging.

Language/framework-agnostic; concept-based.

---

## Error classification

### By source

- User error: invalid input/operation (missing required fields, invalid format)
- Business error: business rule violation (insufficient balance, forbidden action)
- System error: internal bug (null reference, type error)
- External error: dependency failure (API timeout, DB connection failure)

### By recoverability

- Recoverable: user can fix (show concrete guidance)
- Unrecoverable (temporary): may succeed after retry (provide retry path)
- Unrecoverable (permanent): requires support (provide support contact)

---

## Principles

### 1) Fail fast

Detect problems early and fail explicitly.

```
// Good: validate early
if (!userId) {
  throw new ValidationError("userId is required");
}

// Bad: continue with null/undefined
const user = users.find(u => u.id === userId); // undefined
user.name; // crashes later
```

### 2) Catch at the right granularity

```
// Good: classify and handle
try {
  await saveUser(user);
} catch (error) {
  if (error instanceof ValidationError) {
    // handle validation error
  } else if (error instanceof DatabaseError) {
    // handle DB error
  } else {
    // unexpected error
    throw error;
  }
}

// Bad: catch and swallow
try {
  await saveUser(user);
} catch (error) {
  console.log(error);
}
```

### 3) Meaningful messages

- For users: what happened and what to do
- For developers: stack trace and context

---

## Error propagation by layer

- UI: display messages and notify the user
- Application: translate technical errors -> user-facing errors; log
- Domain/infra: raise technical errors; do not format UI messages

---

## Logging

Log levels:

- ERROR: immediate action needed
- WARN: needs attention
- INFO: important normal events
- DEBUG: debugging details

Include:

- Timestamp
- Error type
- Message
- Context (request id, user id, etc)
- Stack trace

Never log:

- Passwords
- Access tokens
- Credit card numbers
- PII (mask if needed)

---

## User notification

Patterns:

- Inline field errors (e.g. "Email is invalid")
- Toast/snackbar for transient notifications
- Modal for important actions (e.g. "Session expired. Please log in again")
- Dedicated pages for fatal errors (404/500)

Message quality:

Good:

- "Email format is invalid."
- "Cannot connect to the server. Please try again later."
- "This page does not exist."

Bad:

- "ValidationError: email"
- "500 Internal Server Error"
- "null pointer exception"

---

## Retry strategy

Retry candidates:

- Network timeout: retry (temporary)
- 429 Too Many Requests: retry after wait
- 503 Service Unavailable: retry (temporary)
- 400 Bad Request: do not retry
- 401 Unauthorized: do not retry (needs auth)

Exponential backoff example:

```
Attempt 1: immediately
Attempt 2: after 1s
Attempt 3: after 2s
Attempt 4: after 4s
Attempt 5: after 8s
(fail after max attempts)
```

---

## Checklist

Design:

- [ ] Error categories are defined
- [ ] Handling policy per category is defined
- [ ] User-facing messages are defined
- [ ] Logging policy is defined

Implementation:

- [ ] Exceptions are caught at an appropriate layer
- [ ] Messages are specific and actionable
- [ ] Secrets are not logged
- [ ] Retry policy exists (when applicable)

Testing:

- [ ] Negative paths are tested (not only happy path)
- [ ] User-facing messages are verified
- [ ] Logs are emitted as expected (when relevant)

---

## Anti-patterns

- Swallowing exceptions: hides problems -> classify and rethrow unexpected errors
- One generic message for everything: hard to debug -> make messages specific
- Showing technical errors to users: confusion -> translate to user-friendly text
- Losing user input on error: bad UX -> preserve input state
- Infinite retries: resource exhaustion -> set a max retry count

---

## Related

- `skills/api-endpoint.md` - API design (error responses)
- `skills/testing.md` - testing (negative-path tests)
- `.agent/rules/dod.md` - Definition of Done
