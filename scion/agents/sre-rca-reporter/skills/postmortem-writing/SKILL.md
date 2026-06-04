---
name: postmortem-writing
description: >-
  Best practices for writing blameless, evidence-based postmortem and RCA reports.
  Use when synthesizing investigation findings into a structured incident report.
---

# Postmortem Writing

Best practices for creating high-quality incident postmortems.

## Core Principles

1. **Blameless culture:** Focus on systemic improvements, not individual blame. Use passive voice for failures ("the deployment was pushed" not "engineer X pushed").
2. **Evidence-based:** Every assertion must cite a specific log entry, metric data point, or trace span.
3. **Actionable:** Every lesson learned should produce a concrete action item with an owner and priority.
4. **Precise timelines:** Use exact timestamps (UTC), never "around" or "approximately."
5. **Concise:** Shorter is better. The executive summary should tell the full story in 3 sentences.

## Action Item Types

| Type | Definition | Example |
|------|-----------|---------|
| **Mitigate** | Reduce impact if this happens again | Add circuit breaker to checkout->payment call |
| **Detect** | Catch this earlier next time | Create alert for payment service restart count >2 in 5 min |
| **Prevent** | Stop this from happening at all | Add pre-deploy health check that validates PORT env var |
| **Process** | Improve the response process | Document runbook for payment service crash scenario |

## Priority Guidelines

- **P1:** Must fix before next on-call rotation. The system is still vulnerable to the same failure.
- **P2:** Fix within 2 weeks. Important improvement but not immediately critical.
- **P3:** Fix within quarter. Nice-to-have improvement.

## Timeline Formatting

- Use bullet points, never tables, for timeline entries
- Mark milestones in red: `<== <span style="color:red">Milestone Name</span>`
- Required milestones: Start of Incident, Incident Detected, Mitigation, End of Incident
- Abstract the day and timezone at the top

## Common Pitfalls

- Writing too much — the report should be scannable in 2 minutes
- Mixing facts with speculation — clearly label hypotheses
- Missing action items — every "went poorly" should produce an action item
- Vague action items — "improve monitoring" is not actionable; "create alert for X metric exceeding Y threshold" is
