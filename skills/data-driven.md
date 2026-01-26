# Data-Driven Development

Optional skill for projects requiring measurable improvements and systematic debugging.

This skill is particularly useful for:
- Large-scale projects
- Performance-critical applications
- Projects with complex debugging needs

---

## When to use

- Performance optimization work
- Complex bug investigation
- Projects requiring measurable success criteria
- Long-running development cycles

## When not to use

- Small, straightforward changes
- Projects without measurable metrics
- Time-constrained quick fixes

---

## Five-step framework

### 1. Inject

Embed measurement points into the system.

Types of instrumentation:
- Logs: structured logging at key points
- Metrics: timing, counts, rates
- Traces: request/transaction flow

Guidelines:
- Instrument at boundaries (input/output)
- Include context (request ID, user ID)
- Use structured formats (JSON)

### 2. Trace

Track data flow from input to output.

Focus areas:
- Transformation points: where data changes form
- Decision points: where branching occurs
- Integration points: external system calls

Output: documented data flow with observable checkpoints

### 3. Collect

Gather evidence continuously.

Methods:
- Automated pipelines (CI/CD integration)
- Baseline snapshots (before changes)
- Regression detection (after changes)

Storage:
- Version-controlled baselines
- Timestamped results
- Reproducible collection scripts

### 4. Understand

Analyze patterns and anomalies.

Techniques:
- Statistical comparison (before/after)
- Visualization (trends, distributions)
- Anomaly detection (outliers, regressions)

Questions to answer:
- What changed?
- How much did it change?
- Is the change significant?

### 5. Systematize

Make investigations reproducible.

Deliverables:
- Documented measurement procedures
- Automated collection scripts
- Reproducible analysis steps

Goal: anyone can repeat the investigation and get the same results

---

## Metrics output template

When completing a task with measurable outcomes, output metrics in this format:

```json
{
  "task_id": "TASK-001",
  "status": "completed",
  "metrics": {
    "duration_ms": 147.05,
    "stages": {
      "parse": 72.03,
      "process": 35.01,
      "output": 40.01
    }
  },
  "quality": {
    "test_pass_rate": 0.98,
    "error_count": 2,
    "coverage_delta": "+2.3%"
  },
  "before_after": {
    "before": "234ms p95",
    "after": "156ms p95",
    "improvement": "33%"
  }
}
```

---

## Checklist

Before starting:
- [ ] Measurement points identified
- [ ] Baseline collected
- [ ] Success criteria defined

During work:
- [ ] Changes are instrumented
- [ ] Results are collected
- [ ] Comparisons are documented

After completion:
- [ ] Before/After comparison available
- [ ] Improvement is measurable
- [ ] Process is reproducible

---

## Related

- `.agent/rules/dod.md` - evidence requirements
- `skills/testing.md` - test design
- `skills/tdd-protocol.md` - TDD protocol
