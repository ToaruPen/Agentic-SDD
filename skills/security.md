# Security Design Skill

Security design principles and patterns. Language/framework-agnostic.

---

## Principles

1. **Defense in depth**
   - Do not rely on a single defense
   - Apply countermeasures at boundary, application, and data layers

2. **Principle of least privilege**
   - Grant only the minimum necessary permissions
   - Default to deny

3. **Fail secure**
   - Deny access on error
   - Detailed errors go to internal logs only

4. **Defense against the unexpected**
   - Trust no input
   - Validate at boundaries

---

## Threat Modeling

### STRIDE classification

| Threat | Description | Countermeasure |
|--------|-------------|----------------|
| Spoofing | Impersonation | Authentication |
| Tampering | Modification | Integrity checks |
| Repudiation | Denial of actions | Audit logs |
| Information Disclosure | Data leakage | Encryption |
| Denial of Service | Service disruption | Rate limiting |
| Elevation of Privilege | Unauthorized access | Authorization |

### Trust boundary identification

```
External input → [Boundary] → Internal processing → [Boundary] → Data storage
                    ↑                                   ↑
                Validation                        Access control
```

---

## Common Vulnerabilities

### OWASP Top 10 categories

1. **Injection**: Input interpreted as command
   - Countermeasure: Parameterization, escaping

2. **Broken Authentication**: Authentication flaws
   - Countermeasure: MFA, session management

3. **Sensitive Data Exposure**: Confidential data leakage
   - Countermeasure: Encryption, minimization

4. **Security Misconfiguration**: Configuration errors
   - Countermeasure: Disable defaults, minimal configuration

---

## Secure Coding Patterns

### Input Validation

Whitelist-first:
  - Explicitly define allowed values
  - Reject everything else

Boundary validation:
  - Validate where external input is received
  - Internal functions assume validated data

### Output Encoding

Encode according to output context:
  - HTML: HTML entity escaping
  - URL: URL encoding
  - SQL: Parameterized queries

### Secret Management

Prohibited: Secrets in source code
Recommended: Environment variables, secret managers

---

## Checklist

### Design phase

- [ ] Trust boundaries identified
- [ ] Data classification complete
- [ ] Authentication/authorization method decided
- [ ] Threat modeling conducted

### Implementation phase

- [ ] Input validation at boundaries
- [ ] Parameterized queries used
- [ ] No secrets in code
- [ ] Error messages contain no internal information

### Review phase

- [ ] OWASP Top 10 countermeasures confirmed
- [ ] Dependency vulnerabilities checked (npm audit, pip-audit, etc.)
- [ ] No sensitive information in logs

---

## Anti-patterns

| Pattern | Problem | Alternative |
|---------|---------|-------------|
| Security by obscurity | Relies on secrecy | Public algorithm + secret key |
| Client-only validation | Bypassable | Validate on server too |
| Hardcoded credentials | Leak risk | Environment variables/Vault |
| Detailed error messages | Information disclosure | Generic message + internal log |
| Trust all input | Injection | Validate at boundary |

---

## Related

- `.agent/rules/security.md` - project-specific security requirements
- `skills/api-endpoint.md` - API security
- `skills/error-handling.md` - preventing error information leakage
