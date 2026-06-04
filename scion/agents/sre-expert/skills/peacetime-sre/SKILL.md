---
name: peacetime-sre
description: >-
  Reliability engineering expertise: SLO/SLI/error budget frameworks, capacity
  planning, chaos engineering, toil reduction, production readiness reviews,
  and observability architecture.
---

# Peacetime SRE

## SLO Framework

### The Three Concepts

| Concept | Definition | Example |
|---------|-----------|---------|
| **SLI** (Service Level Indicator) | A quantitative measure of service behavior | Request latency at the 99th percentile |
| **SLO** (Service Level Objective) | A target value for an SLI | 99th percentile latency < 300ms |
| **Error Budget** | The allowed amount of unreliability (100% - SLO) | 0.1% of requests can exceed 300ms |

### Choosing SLIs

Pick SLIs that reflect what users experience, not what's easy to measure.

**Good SLIs:**
- Availability: proportion of successful requests (HTTP 2xx/3xx out of total)
- Latency: proportion of requests faster than a threshold (p50, p95, p99)
- Correctness: proportion of requests returning correct results
- Freshness: proportion of data updated within a threshold

**Bad SLIs:**
- CPU utilization (infrastructure metric, not user experience)
- Uptime percentage (binary, doesn't capture degradation)
- Number of errors (absolute count, doesn't scale with traffic)
- "Five nines" as a default (probably overkill and definitely expensive)

### Setting SLO Targets

| Service Tier | Availability SLO | Latency SLO (p99) | Error Budget (30 days) |
|-------------|-----------------|-------------------|----------------------|
| **Critical path** (checkout, auth) | 99.9% | < 200ms | 43 minutes of downtime |
| **Important** (search, recommendations) | 99.5% | < 500ms | 3.6 hours of downtime |
| **Best-effort** (analytics, batch) | 99.0% | < 2s | 7.3 hours of downtime |

### Error Budget Policy

The error budget policy defines what happens when the budget is spent:

```
Budget remaining > 50%: Normal development velocity
Budget remaining 25-50%: Prioritize reliability work alongside features
Budget remaining < 25%: Feature freeze — reliability work only
Budget exhausted: All engineering effort on reliability until budget recovers

Exceptions: Security patches and legal compliance always proceed
```

### SLO Anti-patterns

- **SLO without consequences:** An SLO that nobody acts on is a vanity metric
- **SLO on everything:** Pick 3-5 SLOs for user-facing journeys, not 50 for internal services
- **SLO set to current performance:** Your SLO should be slightly below current performance, not equal to it
- **100% SLO:** Impossible and counterproductive. It means zero deployments, zero changes
- **SLO without error budget policy:** The SLO is meaningless without agreed consequences for violations

## Capacity Planning

### The Capacity Planning Cycle

```
1. MEASURE: Current utilization at peak
   - CPU, memory, network, storage, request rate
   - Identify the binding constraint (usually one resource limits first)

2. PROJECT: Expected growth
   - Organic growth rate (users, requests, data volume)
   - Planned growth (new features, marketing campaigns, seasonal events)
   - Apply a safety margin (typically 1.5x for critical, 1.3x for others)

3. PLAN: When do we need more capacity?
   - At current growth rate, when does utilization exceed 70% at peak?
   - What's the lead time for provisioning? (minutes for Cloud Run, weeks for dedicated hardware)
   - What's the cost delta for the next capacity tier?

4. ACT: Provision or optimize
   - Provision if cost-effective and timeline demands it
   - Optimize if there's headroom — query optimization, caching, code efficiency
   - Autoscaling where possible (Cloud Run, GKE Autopilot, Cloud SQL read replicas)
```

### Load Testing

- **Baseline test:** Current production traffic pattern replayed against a staging environment
- **Stress test:** 2x expected peak to find breaking points
- **Soak test:** Sustained load for 4+ hours to find memory leaks, connection exhaustion
- **Spike test:** Sudden 10x burst to test autoscaling response time

Never load test production without explicit approval and monitoring in place. Use a staging environment that mirrors production topology.

## Chaos Engineering

### Principles

1. Start with a hypothesis: "Our system can tolerate the loss of one database replica"
2. Define the blast radius: one pod, one zone, one region
3. Run in staging first, then production with safeguards
4. Automate the experiment so it's repeatable
5. Have a kill switch — abort immediately if impact exceeds expectations

### Game Day Design

```
Preparation (1 week before):
- Define 3-5 failure scenarios to inject
- Verify monitoring and alerting covers each scenario
- Ensure rollback procedures are documented and tested
- Brief all participants on the plan and abort criteria

Execution (game day):
- Inject failure 1, observe, document, restore
- Debrief failure 1 before proceeding
- Inject failure 2, observe, document, restore
- Continue through scenarios with breaks between each

Follow-up (1 week after):
- Document findings and gaps discovered
- Create action items for each gap
- Schedule fixes and re-test
```

### Common Failure Injections

| Injection | What It Tests | Tools |
|-----------|--------------|-------|
| Kill a pod | Kubernetes self-healing, request retry | kubectl delete pod |
| Add network latency | Timeout handling, circuit breakers | tc netem, Istio fault injection |
| Exhaust CPU/memory | Autoscaling, resource limits, OOM handling | stress-ng, resource limits |
| Block external dependency | Fallback paths, graceful degradation | NetworkPolicy, iptables |
| Corrupt a config | Config validation, rollback mechanisms | Manual edit + observe |
| Zone failure | Multi-zone redundancy, failover | Drain nodes in one zone |

## Toil Reduction

### What Is Toil?

Toil is work that is:
- **Manual** — a human does it, not automation
- **Repetitive** — happens regularly, not one-time
- **Automatable** — could be done by software
- **Tactical** — reactive, not strategic
- **Without enduring value** — doesn't improve the system permanently

### Toil Measurement

```
For each operational task, track:
- Frequency: how often per week/month
- Duration: how long each occurrence takes
- Who: which team members perform it
- Automatable: yes / partially / no

Toil budget: SRE teams should spend < 50% of time on toil
If toil > 50%, something must be automated or eliminated before adding new responsibilities
```

### Automation Priority Matrix

| Frequency | Duration | Priority |
|-----------|----------|----------|
| Daily | > 30 min | Automate immediately |
| Daily | < 30 min | Automate this quarter |
| Weekly | > 1 hour | Automate this quarter |
| Weekly | < 1 hour | Automate when convenient |
| Monthly | Any | Document thoroughly, automate opportunistically |

## Production Readiness Review (PRR)

### Checklist

```
ARCHITECTURE
- [ ] Service has defined SLOs with error budget policy
- [ ] Dependencies are documented with failure modes
- [ ] No single points of failure in the critical path
- [ ] Graceful degradation path exists for each dependency

OBSERVABILITY
- [ ] Metrics: request rate, error rate, latency (RED) dashboards exist
- [ ] Logging: structured logs with correlation IDs
- [ ] Tracing: distributed tracing enabled for cross-service calls
- [ ] Alerting: alerts tied to SLOs, not infrastructure metrics

DEPLOYMENT
- [ ] Rollback procedure documented and tested
- [ ] Canary or progressive rollout configured
- [ ] Feature flags for risky changes
- [ ] Deployment takes < 15 minutes

SECURITY
- [ ] Auth/authz for all endpoints
- [ ] Secrets in Secret Manager, not environment variables or code
- [ ] Network policies restrict unnecessary access
- [ ] Audit logging enabled

CAPACITY
- [ ] Load tested at 2x expected peak
- [ ] Autoscaling configured with appropriate min/max
- [ ] Resource requests and limits set for all containers
- [ ] Storage growth projected for 6 months

OPERATIONS
- [ ] Runbooks exist for known failure modes
- [ ] On-call rotation assigned
- [ ] Escalation path documented
- [ ] Postmortem template ready
```

## Observability Architecture

### The Three Pillars

| Pillar | Purpose | When to Use |
|--------|---------|------------|
| **Metrics** | Aggregated numeric data over time | Alerting, dashboarding, trend analysis |
| **Logs** | Discrete events with context | Debugging specific requests, audit trail |
| **Traces** | Request flow across services | Latency diagnosis, dependency mapping |

### Observability Anti-patterns

- **Log everything:** Generates noise and cost. Log at boundaries, decision points, and errors.
- **Alert on symptoms AND causes:** Alert on what users see (SLO violations), not on what caused it (high CPU). Investigate causes after the alert fires.
- **Dashboard sprawl:** 5 dashboards with 8 panels each beats 50 dashboards with 3 panels each. Organize by user journey, not by service.
- **Missing correlation:** Logs without trace IDs, metrics without labels, traces without log links. Correlation is what makes observability usable.
- **Monitoring-as-a-service without ownership:** If nobody reviews the dashboard weekly, it's decoration.
