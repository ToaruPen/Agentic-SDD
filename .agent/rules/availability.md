# Availability Rules

Rules for projects with availability requirements.

Applies when: PRD Q6-8 (Availability requirement) is "Yes"

---

## Required when

<!-- grep keyword: AVAILABILITY_REQUIRED_WHEN -->

Apply this rule if any of the following conditions are met:

- [ ] 24/7 operation is required
- [ ] Downtime directly impacts business revenue
- [ ] SLA/SLO exists (e.g., 99.9% uptime)
- [ ] Disaster recovery plan is required
- [ ] Serves external customers
- [ ] Handles non-interruptible processes (payments, reservations)

---

## Not required when

<!-- grep keyword: AVAILABILITY_NOT_REQUIRED_WHEN -->

Not applicable in these cases:

- Internal tools (business hours only)
- Prototype/PoC (purpose is to validate functionality)
- Personal use only
- Downtime has minimal impact

---

## PRD requirements

<!-- grep keyword: AVAILABILITY_PRD_REQ -->

When PRD Q6-8 is "Yes", include:

1. Uptime requirements overview (e.g., 24/7, business hours only)
2. SLA/SLO existence

Specific design and recovery plans are defined in Epic.

---

## Epic requirements

<!-- grep keyword: AVAILABILITY_EPIC_REQ -->

Include the following section in Epic:

<epic_section name="Availability Design">

### Availability Design (Required if PRD Q6-8: Yes)

SLO:
- Uptime: [e.g., 99.9% (max 43 minutes downtime per month)]
- Allowed downtime: [e.g., 43 minutes per month]
- Response time: [e.g., p99 < 3 seconds]

Redundancy:
- Method: [e.g., multi-AZ, replicas, load balancer]
- Failover: [automatic/manual]

Disaster recovery:
- RTO (Recovery Time Objective): [e.g., 1 hour]
- RPO (Recovery Point Objective): [e.g., 1 hour (max data loss)]
- Backup frequency: [e.g., daily, hourly]
- Backup retention: [e.g., 30 days]

Rollback:
- Method: [e.g., Blue-Green, Canary, manual rollback]
- Procedure: [overview]
- Duration: [e.g., within 5 minutes]

</epic_section>

---

## DoD requirements

<!-- grep keyword: AVAILABILITY_DOD_REQ -->

The following become required in DoD (when Q6-8: Yes):

- [ ] Rollback procedure is documented
- [ ] Backup is configured
- [ ] Incident response contacts/procedures are clear

---

## SLO guidelines

<!-- grep keyword: AVAILABILITY_SLO -->

| Uptime | Monthly downtime | Use case |
|--------|------------------|----------|
| 99% | 7h 18m | Internal tools, non-critical |
| 99.9% | 43m | General web services |
| 99.95% | 22m | E-commerce, SaaS |
| 99.99% | 4m | Finance, payments, infrastructure |

---

## Checklist

<!-- grep keyword: AVAILABILITY_CHECKLIST -->

### Design phase

- [ ] SLO is defined numerically
- [ ] Redundancy method is decided
- [ ] RTO/RPO is defined
- [ ] Backup method is decided

### Implementation phase

- [ ] Health check endpoint exists
- [ ] Graceful shutdown is implemented
- [ ] Timeouts/retries are configured appropriately
- [ ] Service remains stable when external dependencies fail

### Operations phase

- [ ] Backup is running on schedule
- [ ] Backup restore has been tested
- [ ] Rollback procedure has been tested
- [ ] Incident response procedure exists
- [ ] On-call rotation exists (for 24/7)

---

## Examples

<example type="good">
SLO:
- Uptime: 99.9% (max 43 minutes downtime per month)
- p99 response: within 3 seconds

Disaster recovery:
- RTO: 1 hour
- RPO: 1 hour (hourly backups)
- Backup: RDS automated backup + S3 cross-region replication

Rollback:
- Method: Blue-Green deployment
- Procedure: Traffic switch via AWS CodeDeploy
- Duration: within 5 minutes
</example>

<example type="bad">
Availability: Make it high
(No numbers, no specific method, no recovery plan)
</example>

---

## Related

- `.agent/rules/dod.md` - Evidence requirements
- `.agent/rules/epic.md` - Epic structure
- `.agent/rules/observability.md` - Monitoring for availability
- `.agent/rules/performance.md` - Response time SLO
- `docs/prd/_template.md` - PRD Q6-8
