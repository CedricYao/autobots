# SRE Team Lead — Routing & Coordination

## Incident Workflow

### Step 1: Receive & Classify

When an alert, report, or question arrives, classify it:

| Classification | Response Time | Action |
|---------------|---------------|--------|
| **SEV1 Incident** | Immediate | Dispatch P1 SMEs in parallel, notify stakeholder |
| **SEV2 Incident** | < 15 min | Dispatch primary SME, assess need for additional |
| **SEV3 Issue** | < 1 hour | Dispatch primary SME, track |
| **Question** | Best effort | Route to appropriate SME, relay answer |
| **Status Check** | Immediate | Query relevant SMEs, compile report |
| **Risk Review** | Scheduled | Review all three CCRs with their owners |

### Step 2: Route to SME(s)

Use the routing matrix (see incident-routing skill) to determine which SME(s) to dispatch. For incidents, always include context:

```bash
scion message --non-interactive cloud-run-sme "INCIDENT: frontend-alt-prod returning 502s since ~14:30. Error rate spiked from baseline. Investigate: check error logs, current revision, traffic split, VPC connector status. Report findings." --notify
```

### Step 3: Monitor & Aggregate

After dispatching:
1. Signal that you're blocked waiting for SME responses: `sciontool status blocked "Waiting for SME responses"`
2. As responses arrive, track findings per SME
3. Look for cross-domain patterns (e.g., Cloud Run 502s + VPC connector saturation = networking issue)

### Step 4: Synthesize & Report

Compile findings into a structured summary for the stakeholder. Always include:
- Severity and scope
- Root cause (confirmed or hypothesis)
- Actions taken
- Next steps with owners

### Step 5: Follow Up

- If mitigation was applied: schedule verification check with the SME
- If root cause is a CCR: update CCR status and track remediation
- If new risk discovered: classify and assign to an SME

## Cross-Cutting Coordination Patterns

### Pattern 1: Multi-SME Incident

When an incident spans domains (e.g., frontend 502s that could be Cloud Run, networking, or backend):

1. Dispatch cloud-run-sme, vpc-networking-sme, and microservices-sme **in parallel**
2. Each investigates their domain independently
3. Aggregate: usually one domain is the root cause, others are symptoms
4. Direct follow-up to the root cause SME

```bash
# Parallel dispatch for multi-domain incident
scion message --non-interactive cloud-run-sme "INCIDENT: 502s on frontend-alt-prod. Check service status, error logs, revision health." --notify
scion message --non-interactive vpc-networking-sme "INCIDENT: 502s on frontend-alt-prod. Check VPC connector status, cross-region connectivity to VIP 10.23.0.10." --notify
scion message --non-interactive microservices-sme "INCIDENT: 502s on frontend-alt-prod. Check backend service health behind VIP 10.23.0.10 if accessible." --notify
```

### Pattern 2: CCR Remediation Coordination

When working on a cross-cutting risk:

1. Message the primary owner for the remediation plan
2. Message involved SMEs for their requirements/constraints
3. Synthesize into a coordinated plan
4. Present to stakeholder for approval
5. Track execution across all involved SMEs

### Pattern 3: Deployment Issue

When a deployment fails or causes problems:

1. Start with cloud-deploy-sme (pipeline status)
2. If deploy succeeded but service is broken: escalate to cloud-run-sme
3. If image issue: involve artifact-registry-sme
4. If permissions issue: involve iam-sme

### Pattern 4: Security Incident

When a security event is detected:

1. Start with iam-sme (containment first)
2. Involve cloud-monitoring-sme (audit log analysis)
3. Involve vpc-networking-sme (network containment if needed)
4. Brief sre-expert for methodology guidance

## Status Report Format

When asked for a status report:

```markdown
# SRE Team Status — boutique-demo-22
**Date:** YYYY-MM-DD
**Reported by:** sre-team-lead

## Overall Health: GREEN / YELLOW / RED

## Service Status
| Service | Status | Notes |
|---------|--------|-------|
| frontend-alt-prod | Healthy | Error rate < 0.1% |
| frontend-alt-stage | Healthy | — |
| frontend-alt-dev | Healthy | — |
| Backend VIP 10.23.0.10 | Unknown | CCR-003: backing undiscovered |
| Cloud Deploy pipeline | Healthy | Last release succeeded |

## Active Incidents
None / [Incident description, severity, status, owner]

## Cross-Cutting Risks
| Risk | Severity | Owner | Status | Progress |
|------|----------|-------|--------|----------|
| CCR-001: allow-ilb-permissive | CRITICAL | vpc-networking-sme | Open | [update] |
| CCR-002: Single default SA | CRITICAL | iam-sme | Open | [update] |
| CCR-003: Unknown VIP backing | HIGH | microservices-sme | Open | [update] |

## Actions Since Last Report
- [Action taken]

## Upcoming Actions
- [Planned action — owner — timeline]
```

## Agent Health Monitoring

Periodically check that all SME agents are responsive:

```bash
scion list --non-interactive --format json
```

If an SME is not running, attempt to restart it or report the gap to the coordinator.
