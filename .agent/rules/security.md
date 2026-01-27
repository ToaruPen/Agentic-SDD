# Security Rules

Rules for projects with security requirements.

Applies when: PRD Q6-5 (PII/confidential data) is "Yes"

---

## Required when

<!-- grep keyword: SECURITY_REQUIRED_WHEN -->

Apply this rule if any of the following conditions are met:

- [ ] Handles PII (name, email, address, phone number, date of birth, etc.)
- [ ] Has authentication/authorization (login, permission management, sessions)
- [ ] Publicly accessible (public API, website, mobile app)
- [ ] Handles confidential data (internal information, medical data, financial data)
- [ ] Has payment/billing (credit cards, bank accounts)
- [ ] Subject to regulations (GDPR, HIPAA, PCI-DSS, data protection laws, etc.)

---

## Not required when

<!-- grep keyword: SECURITY_NOT_REQUIRED_WHEN -->

Not applicable in these cases:

- Local-only tools (not network accessible)
- Handles only public data (no confidentiality)
- Static site without authentication
- Internal network only (VPN access only)

---

## PRD requirements

<!-- grep keyword: SECURITY_PRD_REQ -->

When PRD Q6-5 is "Yes", include:

1. Types of data handled (PII, confidential information, etc.)
2. Regulatory requirements (GDPR, PCI-DSS, etc.)

Specific countermeasures are defined in Epic.

---

## Epic requirements

<!-- grep keyword: SECURITY_EPIC_REQ -->

Include the following section in Epic:

<epic_section name="Security Design">

### Security Design (Required if PRD Q6-5: Yes)

Data handled:
- [Data type]: [Protection level]
- Example: User email address: encrypted at rest
- Example: Password: hashed (bcrypt, cost=12)
- Example: Credit card: PCI-DSS compliant, tokenized

Authentication/Authorization:
- Authentication method: [e.g., JWT, session, OAuth 2.0]
- Authorization model: [e.g., RBAC, ABAC]
- Session management: [e.g., expiration, refresh tokens]

Countermeasures checklist:
- [ ] Input validation/sanitization
- [ ] SQL injection prevention (parameterized queries)
- [ ] XSS prevention (escaping, CSP)
- [ ] CSRF prevention (tokens)
- [ ] Secret management (environment variables, vault)

</epic_section>

---

## DoD requirements

<!-- grep keyword: SECURITY_DOD_REQ -->

The following become required in DoD (when Q6-5: Yes):

- [ ] Security countermeasures are reviewed
- [ ] No hardcoded secrets
- [ ] Input validation is implemented
- [ ] Authentication/authorization is implemented as required

---

## Prohibited

<!-- grep keyword: SECURITY_PROHIBITED -->

The following are prohibited:

- Hardcoded secrets/passwords/API keys
- Plaintext password storage
- Using external input without validation
- Excessive privilege grants (violating principle of least privilege)
- Logging sensitive information (passwords, tokens, card numbers, etc.)
- Transmitting sensitive data over HTTP (HTTPS required)

---

## Checklist

<!-- grep keyword: SECURITY_CHECKLIST -->

### Design phase

- [ ] Data classification is complete
- [ ] Authentication/authorization method is decided
- [ ] Countermeasures list is created
- [ ] Regulatory requirements are confirmed

### Implementation phase

- [ ] Secrets are accessed via environment variables/vault
- [ ] Input validation is performed at boundaries
- [ ] Error messages do not contain sensitive information
- [ ] HTTPS is used (production environment)

### Review phase

- [ ] OWASP Top 10 countermeasures are confirmed
- [ ] Dependency vulnerabilities are checked (npm audit, pip-audit, etc.)
- [ ] Commit history is checked for secrets

---

## Examples

<example type="good">
- Passwords are hashed with bcrypt (cost=12)
- API key is read from environment variable `API_KEY`
- User input is sanitized before use in DB queries
</example>

<example type="bad">
- `const password = "admin123";` (hardcoded)
- `db.query("SELECT * FROM users WHERE id = " + userId);` (SQL injection)
- `console.log("Token: " + userToken);` (logging sensitive info)
</example>

---

## Related

- `.agent/rules/dod.md` - Evidence requirements
- `.agent/rules/epic.md` - Epic structure
- `.agent/rules/observability.md` - Logging (secret masking)
- `skills/error-handling.md` - Error handling
- `docs/prd/_template.md` - PRD Q6-5
