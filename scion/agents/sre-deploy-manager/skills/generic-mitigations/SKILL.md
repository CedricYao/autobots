---
name: generic-mitigations
description: >-
  Guidance on rapid incident mitigation strategies. Use when you need to select and
  execute a mitigation action during a production incident. Covers rollback, restart,
  scale, drain, degrade, and block-list techniques with risk assessments.
---

# Generic Mitigations

Rapid actions to stabilize production systems during incidents.

## Core Philosophy

1. **Mitigate first, root-cause later.** You don't need to fully understand an outage to stop user impact.
2. **Favor broad-spectrum actions.** Rely on predictable, pre-tested procedures over spontaneous hotfixes.
3. **Monitor after every action.** Verify the mitigation worked before declaring success.

## Mitigation Strategies

| Strategy | When to Use | Risk | Prerequisites |
|----------|-------------|------|---------------|
| **Rollback** | Deployment-triggered errors, regressions | LOW | Known-good previous version exists |
| **Restart** | Stuck processes, leaked resources, transient state corruption | LOW | Service is stateless or handles restarts gracefully |
| **Scale Up** | Traffic spikes, resource starvation | LOW | Scalable infrastructure, won't shift bottleneck downstream |
| **Degrade** | Capacity saturation, cascading failures | MEDIUM | Feature flags or toggles exist for non-essential features |
| **Block List** | Single disruptive tenant, poisonous payload, DoS | MEDIUM | Quick filtering at API gateway or proxy layer |
| **Drain** | Regional infrastructure failure, localized outage | HIGH | Multi-region deployment that can absorb rerouted traffic |
| **Quarantine** | Hot DB rows, spammy users, poisoned data streams | HIGH | Ability to isolate logical streams |

## Risk Assessment Format

Every mitigation command MUST include a risk assessment:

```
# Action: [What you're doing]
# Risk: [NONE/LOW/MEDIUM/HIGH]: [Why this risk level]
# Impact: [What will happen during execution]
# Rollback: [How to undo if it makes things worse]
```

## Decision Flow

1. Is the incident tied to a recent deployment? -> **Rollback**
2. Is a single service unhealthy but config unchanged? -> **Restart**
3. Is the system under unexpected load? -> **Scale Up**
4. Is a specific client/request pattern causing harm? -> **Block List**
5. Is the issue localized to a region/zone? -> **Drain**
