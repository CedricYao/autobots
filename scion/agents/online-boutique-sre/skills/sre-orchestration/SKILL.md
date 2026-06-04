---
name: sre-orchestration
description: >-
  Orchestration playbook for coordinating specialized SRE agents during incident
  response on the Online Boutique application. Use when deciding which agents to
  launch, in what order, and how to synthesize their findings.
---

# SRE Orchestration

Decision framework for coordinating SRE investigation agents.

## Agent Selection Matrix

| Incident Type | Always Launch | Also Launch | When to Add |
|--------------|---------------|-------------|-------------|
| **Any incident** | sre-log-investigator, sre-metrics-analyst | — | — |
| **Latency** | (above) | sre-trace-analyst | When p95/p99 elevated |
| **Crash/Restart** | (above) | sre-gke-specialist | When restart count > 0 |
| **Connectivity** | (above) | sre-gke-specialist | When service-to-service calls fail |
| **Deployment regression** | (above) | sre-deploy-manager | When change correlation needed |
| **Unknown/Complex** | (above) | ALL agents | When symptoms are unclear |

## Synthesis Checklist

Before concluding root cause, verify:
- [ ] All launched agents have reported back
- [ ] Onset timestamps agree across agents (within 2-minute tolerance)
- [ ] Affected services agree across agents
- [ ] Log errors are consistent with metric anomalies
- [ ] Root cause hypothesis explains ALL observed symptoms
- [ ] Confidence level assessed (High/Medium/Low)

## Remediation Decision Tree

```
Root cause identified?
├── Yes, with HIGH confidence
│   ├── Matches known scenario? → Execute known remediation
│   └── Novel failure? → Assess risk
│       ├── LOW risk (rollback, restart, scale) → Execute
│       ├── MEDIUM risk (config patch, policy change) → Execute with monitoring
│       └── HIGH risk (drain, data rollback) → Escalate to human
└── No
    ├── Ongoing impact? → Apply generic mitigation (restart/rollback most recent change)
    └── Impact resolved? → Proceed to report phase
```

## Report Publication

After RCA report is generated:
```bash
# Publish to GCS
gsutil cp /tmp/incident-report-*.md gs://platform-team-project-work/incident-reports/

# Verify upload
gsutil ls gs://platform-team-project-work/incident-reports/
```

## Escalation Criteria

Escalate to human when:
- Root cause unclear after all agents investigated
- HIGH risk remediation needed
- Security incident detected
- Multiple cascading failures
- kubectl access required but unavailable
- Incident duration exceeds 30 minutes without mitigation
