---
name: gcp-sre
description: >-
  GCP-specific SRE patterns: Cloud Monitoring alerting policies, Cloud Logging
  architecture, Cloud Trace integration, Cloud Deploy pipelines, Cloud Run and
  GKE operational patterns, and enterprise tooling integration.
---

# GCP SRE Patterns

## Cloud Monitoring

### Alerting Policy Design

```
Good alert:
  Display name: "Checkout API — Error Rate SLO Violation"
  Condition: error_rate > 0.1% over 5 minutes (aligned to SLO)
  Notification: PagerDuty (SEV2)
  Documentation: links to runbook, dashboard, escalation path
  
Bad alert:
  Display name: "High CPU on checkout-service"
  Condition: cpu > 80% for 1 minute
  Notification: Email to team
  Problem: CPU is a cause, not a symptom. Users don't experience "high CPU."
```

### Alert Design Principles

- **Alert on SLO burn rate, not raw metrics.** A 1% error rate for 5 minutes burns budget differently than 0.1% for an hour. Use multi-window, multi-burn-rate alerting.
- **Every alert must have a runbook link.** If there's no documented action to take, the alert shouldn't page anyone.
- **Tune notification channels to severity.** SEV1 = PagerDuty page. SEV3 = Slack notification. Not everything is a page.
- **Alert on absence of data.** If a service stops emitting metrics, that's often worse than a spike in error rate.

### Multi-Window Burn Rate Alerting

```
Fast burn (SEV1): 
  14.4x burn rate over 1 hour AND 14.4x burn rate over 5 minutes
  → Budget will be exhausted in ~2 hours at this rate

Slow burn (SEV2):
  6x burn rate over 6 hours AND 6x burn rate over 30 minutes  
  → Budget will be exhausted in ~5 days at this rate

Slow leak (ticket):
  1x burn rate over 3 days AND 1x burn rate over 6 hours
  → Budget will be exhausted by end of window
```

### Uptime Checks

- Use GCP Uptime Checks for external availability monitoring
- Check from multiple regions (at least 3)
- Validate response content, not just HTTP status (a 200 with an error page is not healthy)
- Set check interval based on SLO: critical services every 60s, others every 300s
- Alert on 2+ consecutive failures from 2+ regions to reduce false positives

## Cloud Logging

### Log Architecture

```
Application logs → Cloud Logging → Log Router
                                      ├→ Default bucket (30 day retention)
                                      ├→ Long-term bucket (compliance, 365+ days)
                                      ├→ BigQuery (analytics, cost investigation)
                                      └→ Pub/Sub (real-time processing, SIEM)
```

### Log Routing Rules

| Log Type | Destination | Retention | Purpose |
|----------|------------|-----------|---------|
| Application logs (INFO+) | Default bucket | 30 days | Debugging |
| Application logs (ERROR+) | Analytics bucket | 90 days | Trend analysis |
| Audit logs (Admin Activity) | Compliance bucket | 365 days | Regulatory compliance |
| Audit logs (Data Access) | Compliance bucket | 365 days | Security investigation |
| Request logs | BigQuery | 90 days | Cost analysis, traffic patterns |
| DEBUG logs | Excluded | — | Excluded from ingestion (cost control) |

### Log-Based Metrics

Create custom metrics from log patterns for alerting:

```
Metric: custom.googleapis.com/checkout/payment_failures
Filter: resource.type="cloud_run_revision"
        AND jsonPayload.event="payment_failed"
Aggregation: count per 1 minute
Alert: > 5 per minute → SEV2
```

### Cost Control

Cloud Logging can be expensive at scale. Control costs by:
- Excluding DEBUG-level logs from ingestion (log exclusion filters)
- Setting appropriate retention periods per bucket
- Using log sampling for high-volume, low-value logs
- Routing to BigQuery for analytics instead of querying Cloud Logging directly
- Monitoring `logging.googleapis.com/billing/bytes_ingested` with a budget alert

## Cloud Trace

### Integration Pattern

```
Application → OpenTelemetry SDK → Cloud Trace Exporter → Cloud Trace

Key configuration:
- Sampling rate: 1% for high-traffic services, 100% for low-traffic
- Propagation: W3C TraceContext headers across all services
- Custom spans: wrap external calls (database, cache, third-party APIs)
- Span attributes: include user_id, request_id, feature_flag variants
```

### Latency Analysis Workflow

1. SLO alert fires: p99 latency exceeded threshold
2. Open Cloud Trace, filter by time window and service
3. Sort by latency descending, examine slowest traces
4. Identify the slow span (database query? external API? CPU-bound processing?)
5. Correlate with logs using trace_id
6. Fix the specific bottleneck, verify p99 drops

### Trace Anti-patterns

- **Not propagating context:** Traces end at service boundaries without context propagation
- **Tracing everything:** 100% sampling on a 10K RPS service generates enormous cost and noise
- **Missing custom spans:** Auto-instrumentation covers HTTP/gRPC but misses database queries and cache calls
- **No correlation to logs:** A trace without linked logs forces manual timestamp correlation

## Cloud Run Operations

### Scaling Configuration

```
Critical service:
  min-instances: 2 (avoid cold starts)
  max-instances: 100
  concurrency: 80 (per instance)
  cpu-throttling: disabled (CPU always allocated)
  startup-cpu-boost: enabled

Best-effort service:
  min-instances: 0 (scale to zero OK)
  max-instances: 20
  concurrency: 100
  cpu-throttling: enabled (save cost)
```

### Health Patterns

- **Startup probe:** Verify the service can reach its dependencies before accepting traffic
- **Liveness probe:** Kill and restart if the process is hung (use cautiously — restart loops are worse than degradation)
- **Readiness probe:** Remove from load balancer if temporarily unable to serve (database connection lost, dependency down)

### Cloud Run Anti-patterns

- **No min instances for critical services:** Cold starts add 2-10 seconds of latency
- **Global variables for connection pools:** Cloud Run instances are recycled — initialize connections in the request path or use lazy initialization with health checks
- **Ignoring CPU throttling:** With CPU throttling enabled, background work between requests doesn't execute. If you need background processing, disable throttling.
- **No concurrency limits:** Default is 80, but if your service does CPU-heavy work per request, lower it to match available CPU

## GKE Operations

### GKE Autopilot vs Standard

| Consideration | Autopilot | Standard |
|--------------|-----------|----------|
| **Use when** | Workload is standard, team is small | Need GPU, custom node configs, DaemonSets |
| **Node management** | Google manages | You manage |
| **Cost model** | Pay per pod resource request | Pay per node |
| **Scaling** | Automatic | Configure cluster autoscaler |
| **Best for** | Most workloads, fewer ops staff | Specialized workloads, large SRE teams |

### Pod Resource Patterns

```
Request = what the scheduler guarantees
Limit = the hard ceiling

Good practice:
  resources:
    requests:
      cpu: 250m      # Based on observed p50 usage
      memory: 256Mi   # Based on observed steady-state
    limits:
      cpu: 1000m      # 4x request — allows bursting
      memory: 512Mi   # 2x request — OOMKill if exceeded

Anti-pattern:
  requests:
    cpu: 100m         # Too low — gets CPU-throttled under load
    memory: 64Mi      # Too low — OOMKilled during normal operation
  limits:
    cpu: 4000m        # Too high — wastes cluster capacity in scheduling
    memory: 8Gi       # Too high — one pod could starve others
```

### Deployment Rollout

```
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 25%        # Create new pods before killing old ones
    maxUnavailable: 0%   # Zero downtime — never remove a pod until replacement is ready

With Cloud Deploy:
  pipeline:
    stages:
      - target: staging
        strategy: standard
      - target: canary
        strategy:
          canary:
            percentages: [10, 25, 50]
            verify: true    # Run contract tests at each stage
      - target: production
        strategy: standard
```

## Cloud Deploy Pipelines

### Pipeline Design

```
Source → Cloud Build → Artifact Registry → Cloud Deploy
                                              ├→ Staging (auto-deploy)
                                              ├→ Canary (auto-promote if tests pass)
                                              └→ Production (manual approval)

Verification at each stage:
  - Contract tests pass against the stage's URL
  - SLO metrics stable for 10 minutes post-deploy
  - No new error patterns in logs
```

### Rollback Strategy

- **Automated rollback:** If verification fails at any canary percentage, automatically roll back
- **Manual rollback:** For production, retain the ability to roll back to the previous release with one command
- **Rollback testing:** Practice rollbacks monthly. A rollback procedure you've never tested is a rollback procedure that doesn't work.

## Enterprise Tooling Integration

### Monitoring Stack Patterns

| Pattern | Components | When to Use |
|---------|-----------|-------------|
| **GCP-native** | Cloud Monitoring + Cloud Logging + Cloud Trace | GCP-only, small team, lower cost |
| **Hybrid** | Datadog/Grafana + Cloud Logging + Cloud Trace | Multi-cloud or existing investment in external tools |
| **Enterprise** | Datadog + PagerDuty + ServiceNow + Confluence | Large org with established ITSM processes |

### PagerDuty Integration

```
Cloud Monitoring Alert → Notification Channel (PagerDuty)
                            → PagerDuty Service (maps to team)
                              → Escalation Policy
                                → On-call schedule
                                  → Primary → Secondary → Manager

Key configuration:
- Map GCP alert severity to PagerDuty urgency (SEV1→High, SEV3→Low)
- Include runbook link in alert documentation (PagerDuty displays it)
- Configure auto-resolve when the GCP alert resolves
- Set up maintenance windows for planned deployments
```

### Access Control for SRE in Regulated Environments

```
Principle: Least privilege + break-glass + audit everything

Day-to-day access:
  - Read-only to production (Viewer role)
  - Read-write to staging and dev
  - Logs and metrics access in all environments

Incident access (break-glass):
  - Temporary elevated access via PAM (Privileged Access Management)
  - Time-bounded (4 hours max, renewable)
  - Every action audit-logged
  - Post-incident review of all elevated access

Deployment access:
  - CI/CD pipeline deploys, not humans
  - Pipeline uses Workload Identity Federation (no stored keys)
  - Manual deployment requires approval from 2nd engineer
  - All deployments logged and attributable
```
