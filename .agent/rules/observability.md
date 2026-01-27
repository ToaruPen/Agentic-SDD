# Observability Rules

Rules for projects with observability requirements.

Applies when: PRD Q6-6 (Audit log requirement) is "Yes"

---

## Required when

<!-- grep keyword: OBSERVABILITY_REQUIRED_WHEN -->

Apply this rule if any of the following conditions are met:

- [ ] Deployed to production environment
- [ ] Root cause analysis is needed for incidents
- [ ] Audit requirements exist (finance, healthcare, government)
- [ ] Distributed system (microservices, async processing)
- [ ] SLO/SLA exists
- [ ] Operated by multiple people

---

## Not required when

<!-- grep keyword: OBSERVABILITY_NOT_REQUIRED_WHEN -->

Not applicable in these cases:

- Throwaway scripts (one-time execution)
- Local-only tools (personal use)
- Prototype/PoC (purpose is to validate functionality)
- Non-operational code (libraries, SDKs)

---

## PRD requirements

<!-- grep keyword: OBSERVABILITY_PRD_REQ -->

When PRD Q6-6 is "Yes", include:

1. Audit requirements (need to record who did what)
2. Log retention period requirements (regulations, etc.)

Specific design is defined in Epic.

---

## Epic requirements

<!-- grep keyword: OBSERVABILITY_EPIC_REQ -->

Include the following section in Epic:

<epic_section name="Observability Design">

### Observability Design (Required if PRD Q6-6: Yes)

Logging:
- Output destination: [e.g., stdout, file, CloudWatch, Datadog]
- Format: [e.g., JSON, structured logs]
- Levels: [e.g., ERROR, WARN, INFO, DEBUG]
- Retention period: [e.g., 30 days, 1 year (audit requirement)]

Metrics:
- [Metric name]: [Description]
- Example: request_duration_seconds: Request processing time
- Example: request_count: Request count
- Example: error_count: Error count

Tracing (for distributed systems):
- Method: [e.g., OpenTelemetry, Jaeger, X-Ray]
- Propagation: [e.g., W3C Trace Context, B3]

Alerting:
- [Condition]: [Notification target]
- Example: Error rate > 5%: Slack #alerts
- Example: p99 response time > 5s: PagerDuty

</epic_section>

---

## DoD requirements

<!-- grep keyword: OBSERVABILITY_DOD_REQ -->

The following become required in DoD (when Q6-6: Yes):

- [ ] Logging is implemented
- [ ] Errors include sufficient context in logs
- [ ] No sensitive information in logs

---

## Log level guidelines

<!-- grep keyword: OBSERVABILITY_LOG_LEVELS -->

| Level | Purpose | Example |
|-------|---------|---------|
| ERROR | Immediate action needed | DB connection failure, data inconsistency |
| WARN | Attention needed | Retry occurred, threshold approaching |
| INFO | Important normal events | Request start/end, state changes |
| DEBUG | Development only | Detailed data contents, intermediate states |

---

## Log content guidelines

<!-- grep keyword: OBSERVABILITY_LOG_CONTENT -->

Information to include:
- Timestamp (ISO 8601)
- Log level
- Request ID / Trace ID
- User ID (if applicable)
- Operation performed
- Result (success/failure)
- On error: stack trace

Information to exclude:
- Passwords
- Access tokens
- Credit card numbers
- PII (must be masked)

---

## Checklist

<!-- grep keyword: OBSERVABILITY_CHECKLIST -->

### Design phase

- [ ] Log output destination is decided
- [ ] Log format is decided
- [ ] Metrics items are defined
- [ ] Alert conditions are defined

### Implementation phase

- [ ] Stack traces are recorded on errors
- [ ] Context (request ID, etc.) is included
- [ ] Sensitive information is masked
- [ ] Log levels are used appropriately

### Operations phase

- [ ] Alert conditions are configured
- [ ] Logs are searchable (queryable format)
- [ ] Dashboard is prepared

---

## Examples

<example type="good">
```json
{
  "timestamp": "2024-01-15T10:30:00.123Z",
  "level": "INFO",
  "request_id": "req-abc123",
  "user_id": "user-456",
  "action": "user.login",
  "result": "success",
  "duration_ms": 150
}
```
</example>

<example type="bad">
```
User logged in successfully
(No timestamp, no context, not structured)
```
</example>

---

## Related

- `.agent/rules/dod.md` - Evidence requirements
- `.agent/rules/epic.md` - Epic structure
- `.agent/rules/security.md` - Secret masking
- `skills/error-handling.md` - Error handling (logging)
- `docs/prd/_template.md` - PRD Q6-6
