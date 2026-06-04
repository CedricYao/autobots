---
name: incident-response
description: >-
  Primary incident response orchestration skill. Use when an alert fires or an incident
  is reported to coordinate investigation, mitigation, and reporting across specialized
  SRE agents.
---

# Incident Response Orchestration

Guide for coordinating autonomous SRE agents during incident response.

## Triage Checklist

- [ ] Alert/incident parsed — what metric, what resource, what time
- [ ] Incident type classified — performance, availability, crash, connectivity
- [ ] Severity set — P1 (user-facing, broad), P2 (user-facing, limited), P3 (internal only)
- [ ] Investigation agents launched in parallel
- [ ] Timeline of events established

## Agent Launch Patterns

### Standard Investigation (all incidents)
```
sre-log-investigator + sre-metrics-analyst (parallel)
```

### Latency Investigation
```
sre-log-investigator + sre-metrics-analyst + sre-trace-analyst (parallel)
```

### Crash/Restart Investigation
```
sre-log-investigator + sre-metrics-analyst + sre-gke-specialist (parallel)
then sre-deploy-manager (for change correlation)
```

### Full Investigation (complex/unknown)
```
sre-log-investigator + sre-metrics-analyst + sre-trace-analyst + sre-gke-specialist + sre-deploy-manager (all parallel)
```

## Evidence Synthesis

When correlating findings from multiple agents:

1. **Time alignment:** Do all agents agree on when the anomaly started?
2. **Service agreement:** Do all agents identify the same service(s) as problematic?
3. **Signal consistency:** Do the log errors match what metrics show? Do traces confirm the latency source?
4. **Root cause convergence:** Does a single explanation account for all observed symptoms?

If agents disagree, dig deeper into the conflicting evidence before concluding.

## Escalation Criteria

Escalate to a human (report to user) when:
- Root cause cannot be determined with available evidence
- Mitigation requires HIGH risk action (drain, data rollback)
- The incident involves security (unauthorized access, data exposure)
- kubectl access is needed but unavailable (auth plugin gap)
- Multiple cascading failures make automated response unreliable
