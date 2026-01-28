# Security Design Skill

Security design principles and patterns. Language/framework-agnostic.

---

## Principles

### Defense in depth

- Do not rely on a single defense
- Apply countermeasures at boundary, application, and data layers

### Principle of least privilege

- Grant only the minimum necessary permissions
- Default to deny

### Fail secure

- Deny access on error
- Detailed errors go to internal logs only

### Defense against the unexpected

- Trust no input
- Validate at boundaries

---

## Threat Modeling

### STRIDE classification

**Spoofing**
- Description: Impersonation
- Countermeasure: Authentication

**Tampering**
- Description: Modification
- Countermeasure: Integrity checks

**Repudiation**
- Description: Denial of actions
- Countermeasure: Audit logs

**Information Disclosure**
- Description: Data leakage
- Countermeasure: Encryption

**Denial of Service**
- Description: Service disruption
- Countermeasure: Rate limiting

**Elevation of Privilege**
- Description: Unauthorized access
- Countermeasure: Authorization

### Trust boundary identification

Data flow with validation points:

1. External input received
2. Boundary 1: Input validation applied
3. Internal processing
4. Boundary 2: Access control applied
5. Data storage

Key points:
- Validate at every boundary where external data enters
- Apply access control before data storage operations

---

## Common Vulnerabilities

### OWASP Top 10 categories

**Injection**
- Problem: Input interpreted as command
- Countermeasure: Parameterization, escaping

**Broken Authentication**
- Problem: Authentication flaws
- Countermeasure: MFA, session management

**Sensitive Data Exposure**
- Problem: Confidential data leakage
- Countermeasure: Encryption, minimization

**Security Misconfiguration**
- Problem: Configuration errors
- Countermeasure: Disable defaults, minimal configuration

---

## Secure Coding Patterns

### Input Validation

Whitelist-first approach:
- Explicitly define allowed values
- Reject everything else

Boundary validation:
- Validate where external input is received
- Internal functions assume validated data

### Output Encoding

Encode according to output context:
- HTML output: HTML entity escaping
- URL output: URL encoding
- SQL output: Parameterized queries

### Secret Management

- Prohibited: Secrets in source code
- Recommended: Environment variables, secret managers

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
- [ ] Dependency vulnerabilities checked
- [ ] No sensitive information in logs (see `skills/error-handling.md`)

---

## Anti-patterns

**Security by obscurity**
- Problem: Relies on secrecy
- Alternative: Public algorithm + secret key

**Client-only validation**
- Problem: Bypassable
- Alternative: Validate on server too

**Hardcoded credentials**
- Problem: Leak risk
- Alternative: Environment variables or Vault

**Detailed error messages**
- Problem: Information disclosure
- Alternative: Generic message + internal log

**Trust all input**
- Problem: Injection vulnerabilities
- Alternative: Validate at boundary

See also `skills/api-endpoint.md` for API-specific security checklist.

---

## Related

- `.agent/rules/security.md` - project-specific security requirements
- `skills/api-endpoint.md` - API security checklist
- `skills/error-handling.md` - logging guidelines and error information leakage prevention
