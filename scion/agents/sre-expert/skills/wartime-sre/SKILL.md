---
name: wartime-sre
description: >-
  Incident management expertise: incident command, severity classification,
  triage protocols, RCA methodology, runbook design, incident communication,
  blameless postmortems, and on-call rotation design.
---

# Wartime SRE

## Incident Command Structure

Every incident has three roles. One person can hold multiple roles at low severity, but SEV1 requires dedicated individuals.

| Role | Responsibility | Key Artifacts |
|------|---------------|---------------|
| **Incident Commander (IC)** | Owns the incident lifecycle. Delegates, decides, communicates. Does NOT debug. | Incident timeline, status updates |
| **Operations Lead** | Hands on keyboard. Executes mitigation, runs diagnostics, applies fixes. | Runbook execution log, diagnostic output |
| **Communications Lead** | Manages internal/external updates. Shields Ops Lead from interruptions. | Status page updates, stakeholder emails |

### IC Decision Framework

The IC's job is to reduce mean time to mitigate (MTTM), not mean time to root cause (MTTRC). Mitigation first, understanding second.

```
1. Is the impact contained? → If no, contain it (rollback, failover, shed load)
2. Is the blast radius growing? → If yes, escalate severity
3. Do we have a hypothesis? → If no, assign parallel investigation tracks
4. Has mitigation been attempted? → If no, execute the most likely mitigation
5. Is mitigation holding? → If no, escalate and try next option
```

## Severity Classification

| Severity | Impact | Response Time | Escalation |
|----------|--------|---------------|------------|
| **SEV1** | Revenue-impacting outage, data loss, security breach | Immediate (< 5 min) | VP-level notification, all-hands response |
| **SEV2** | Major feature degraded, significant user impact | < 15 min | Director notification, dedicated response team |
| **SEV3** | Minor feature degraded, workaround available | < 1 hour | Team lead notification, next business day ok |
| **SEV4** | Cosmetic issue, no user impact | Next business day | Normal ticket flow |

### Escalation Triggers

Escalate severity UP when:
- Impact is broader than initially assessed
- Mitigation attempt failed
- Duration exceeds expected recovery time by 2x
- A second system is now affected
- Customer or regulatory notification may be required

Never escalate DOWN during an active incident. Downgrade only after mitigation is confirmed stable for 30+ minutes.

## Triage Protocol

### The Five-Step Triage

```
DETECT → ASSESS → MITIGATE → RESOLVE → LEARN

1. DETECT: What is the symptom? (alert, user report, monitoring anomaly)
   - What metric moved? By how much? When did it start?
   - Is this a new failure mode or a known pattern?

2. ASSESS: What is the impact?
   - Users affected: none / subset / majority / all
   - Revenue impact: none / indirect / direct
   - Data impact: none / stale reads / failed writes / loss
   - Assign severity based on assessment

3. MITIGATE: Stop the bleeding
   - Can we rollback the last deploy? → Do it
   - Can we failover to a healthy replica? → Do it
   - Can we shed load / rate limit? → Do it
   - Can we feature-flag the broken path off? → Do it
   - DO NOT attempt root cause analysis before mitigation

4. RESOLVE: Fix the underlying issue
   - Now investigate root cause
   - Apply targeted fix
   - Verify fix in production with monitoring
   - Confirm error rates return to baseline

5. LEARN: Prevent recurrence
   - Schedule postmortem within 48 hours
   - Document timeline, root cause, contributing factors
   - Assign action items with owners and deadlines
```

### Hypothesis-Driven Debugging

During step 4, form hypotheses and eliminate them systematically:

```
Hypothesis: "The deploy at 14:23 introduced a regression"
Test: Compare error rate before/after deploy timestamp
Result: Error rate was elevated before deploy → Eliminated

Hypothesis: "Upstream dependency (payment service) is failing"
Test: Check payment service error rate and latency
Result: Payment service 5xx rate spiked at 14:15 → Likely cause
Action: Verify with payment team, check their recent changes
```

Never pursue more than 3 hypotheses in parallel. Assign each to a different investigator if possible.

## Runbook Design

### Good Runbook Structure

```
Title: [Alert name that triggers this runbook]
Last verified: [Date someone ran through this successfully]

SYMPTOMS
- [What the operator will see — specific metric/log/alert]

IMPACT
- [What users experience when this happens]

IMMEDIATE ACTIONS (< 5 min)
1. [Exact command or action — copy-pasteable]
2. [Exact command or action]
3. [Decision point: if X, go to step 4a; if Y, go to step 4b]

INVESTIGATION
- [Where to look for root cause]
- [Common causes with specific diagnostic commands]

ESCALATION
- [Who to contact if immediate actions don't resolve]
- [What information to include when escalating]
```

### Runbook Anti-patterns

- **"Check the logs"** — Which logs? What service? What pattern to search for?
- **"Restart the service"** — Which pod/instance? What's the safe restart procedure? What to verify after?
- **"Contact the team"** — Which team? What Slack channel? What if it's 3am?
- **Outdated commands** — Runbook references infrastructure that was decommissioned 6 months ago
- **No verification step** — How do you know the fix worked?

## Incident Communication

### Internal Communication Cadence

| Severity | Update Frequency | Channel |
|----------|-----------------|---------|
| SEV1 | Every 15 minutes | Dedicated incident Slack channel + email to leadership |
| SEV2 | Every 30 minutes | Incident Slack channel |
| SEV3 | On state change | Team Slack channel |
| SEV4 | Ticket updates | Ticketing system |

### Status Update Template

```
[TIMESTAMP] [SEV-X] [Service Name] — [Status: Investigating|Identified|Mitigating|Resolved]

Impact: [Who is affected, how]
Current state: [What we know right now]
Actions: [What we're doing about it]
Next update: [When]
```

## Blameless Postmortem

### Structure

```
1. Summary (2-3 sentences: what happened, impact, duration)
2. Timeline (timestamped sequence of events)
3. Root cause (technical, specific)
4. Contributing factors (what made detection/mitigation slower)
5. What went well (reinforce good practices)
6. What went poorly (be honest, not personal)
7. Action items (owner + deadline for each)
```

### Facilitation Rules

- No "who" questions — only "what" and "why" questions
- "The deploy caused the outage" not "Alice's deploy caused the outage"
- Focus on system failures, not human failures
- Every action item gets an owner and a deadline
- Review action items from previous postmortems — are they done?

## On-Call Design

### Rotation Principles

- Minimum 2 people per rotation (primary + secondary)
- Maximum 1 week on-call per person per month
- Follow-the-sun for global teams (no overnight pages)
- Handoff document at every rotation change
- Quarterly on-call retrospective: page volume, false positive rate, toil

### Burnout Prevention Signals

- Same person paged > 3 times in one on-call shift
- Page volume increasing month-over-month without corresponding user growth
- On-call engineers consistently working incident follow-ups during regular hours
- "Hero culture" — one person always gets escalated to because they "know the system"
- Engineers declining or swapping on-call shifts regularly
