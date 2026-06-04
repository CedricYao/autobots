---
name: cloud-monitoring
description: >-
  GCP observability expertise: MQL queries, alerting policy design, Cloud Logging
  filters, log-based metrics, distributed tracing, SLO/SLI definition, dashboard
  design, uptime checks, and cost management for boutique-demo-22.
---

# Cloud Monitoring Operations

## View Commands (READ — safe at any time)

### Metrics (MQL)
```bash
# Cloud Run error rate
fetch cloud_run_revision
| metric 'run.googleapis.com/request_count'
| filter resource.project_id == 'boutique-demo-22'
| align rate(1m)
| group_by [resource.service_name, metric.response_code_class],
    [value_request_count_aggregate: aggregate(value.request_count)]

# Cloud Run P99 latency
fetch cloud_run_revision
| metric 'run.googleapis.com/request_latencies'
| filter resource.project_id == 'boutique-demo-22'
| align delta(1m)
| every 1m
| group_by [resource.service_name],
    [value_request_latencies_percentile: percentile(value.request_latencies, 99)]

# Cloud Run instance count
fetch cloud_run_revision
| metric 'run.googleapis.com/container/instance_count'
| filter resource.project_id == 'boutique-demo-22'
| align mean(1m)
| group_by [resource.service_name], [value_instance_count_mean: mean(value.instance_count)]

# Cloud Run CPU utilization
fetch cloud_run_revision
| metric 'run.googleapis.com/container/cpu/utilizations'
| filter resource.project_id == 'boutique-demo-22'
| align mean(1m)
| group_by [resource.service_name], [value_utilizations_mean: mean(value.utilizations)]

# VPC connector throughput
fetch vpc_access_connector
| metric 'vpcaccess.googleapis.com/connector/sent_bytes_count'
| filter resource.project_id == 'boutique-demo-22'
| align rate(1m)
```

### Alerting Policies
```bash
# List all alerting policies
gcloud alpha monitoring policies list --project=boutique-demo-22 --format="table(displayName,enabled,conditions.displayName)"

# Describe specific policy
gcloud alpha monitoring policies describe POLICY_ID --project=boutique-demo-22 --format=yaml

# List notification channels
gcloud alpha monitoring channels list --project=boutique-demo-22 --format="table(displayName,type,enabled)"
```

### Dashboards
```bash
# List dashboards
gcloud monitoring dashboards list --project=boutique-demo-22 --format="table(name,displayName)"

# Describe dashboard (get widget configuration)
gcloud monitoring dashboards describe DASHBOARD_ID --project=boutique-demo-22 --format=yaml
```

### Uptime Checks
```bash
# List uptime checks
gcloud monitoring uptime list-configs --project=boutique-demo-22 --format="table(displayName,monitoredResource.type,httpCheck.path)"
```

### Cloud Logging
```bash
# Recent errors across all services
gcloud logging read 'severity>=ERROR' --project=boutique-demo-22 --limit=50 --format=json --freshness=1h

# Cloud Run specific errors
gcloud logging read 'resource.type="cloud_run_revision" AND severity>=ERROR' --project=boutique-demo-22 --limit=50 --format=json --freshness=1h

# Audit logs (who changed what)
gcloud logging read 'logName="projects/boutique-demo-22/logs/cloudaudit.googleapis.com%2Factivity"' --project=boutique-demo-22 --limit=20 --format=json --freshness=24h

# Log volume by resource type
gcloud logging read '' --project=boutique-demo-22 --limit=1 --format=json --freshness=1h
# Better: use log-based metrics for volume tracking
```

### Cloud Trace
```bash
# List recent traces (via API — no direct gcloud command)
# Use Cloud Console or API: cloudtrace.googleapis.com/v2/projects/boutique-demo-22/traces
# Filter by latency, service, or status code
```

## Modify Commands (WRITE — require operator access)

### Alerting Policies
```bash
# Create alerting policy (from JSON file)
gcloud alpha monitoring policies create --policy-from-file=policy.json --project=boutique-demo-22
# Risk: low | Reversible: delete policy

# Update alerting policy
gcloud alpha monitoring policies update POLICY_ID --policy-from-file=updated-policy.json --project=boutique-demo-22
# Risk: medium (may miss alerts during update) | Reversible: update again

# Enable/disable policy
gcloud alpha monitoring policies update POLICY_ID --enabled --project=boutique-demo-22
gcloud alpha monitoring policies update POLICY_ID --no-enabled --project=boutique-demo-22
# Risk: HIGH if disabling (alert gap) | Reversible: re-enable
```

### Log Configuration
```bash
# Create log sink (route logs to storage)
gcloud logging sinks create SINK_NAME storage.googleapis.com/BUCKET --log-filter='FILTER' --project=boutique-demo-22
# Risk: low | Reversible: delete sink

# Create exclusion filter (reduce log volume/cost)
gcloud logging sinks update _Default --add-exclusion='name=EXCLUSION_NAME,filter=FILTER' --project=boutique-demo-22
# Risk: medium (may miss important logs) | Reversible: remove exclusion

# Create log-based metric
gcloud logging metrics create METRIC_NAME --description='DESCRIPTION' --log-filter='FILTER' --project=boutique-demo-22
# Risk: low | Reversible: delete metric
```

### Dashboards
```bash
# Create dashboard (from JSON)
gcloud monitoring dashboards create --config-from-file=dashboard.json --project=boutique-demo-22
# Risk: low | Reversible: delete dashboard
```

## SLO/SLI Definition

### Recommended SLIs for boutique-demo-22

| SLI | Metric | Good Events | Total Events |
|-----|--------|-------------|--------------|
| Availability | `run.googleapis.com/request_count` | response_code < 500 | all requests |
| Latency | `run.googleapis.com/request_latencies` | latency < 1000ms | all requests |
| Correctness | Application-specific | Correct responses | all responses |

### SLO Targets

| Service | Availability SLO | Latency SLO (p99) | Error Budget (30 days) |
|---------|-----------------|-------------------|----------------------|
| frontend-alt-prod | 99.9% | < 1s | 43 min downtime |
| frontend-alt-stage | 99.5% | < 2s | 3.6 hours |
| frontend-alt-dev | 99.0% | < 3s | 7.3 hours |

### Error Budget Policy
```
Budget > 50%:   Normal development velocity
Budget 25-50%:  Prioritize reliability alongside features
Budget < 25%:   Feature freeze — reliability only
Budget exhausted: All effort on reliability until recovered
```

## Alert Design Principles

### Multi-Window Burn Rate
```
Fast burn (P1 page):
  14.4x burn rate over 1 hour AND 14.4x over 5 minutes
  → Budget exhausted in ~2 hours

Slow burn (P2 alert):
  6x burn rate over 6 hours AND 6x over 30 minutes
  → Budget exhausted in ~5 days

Slow leak (P3 ticket):
  1x burn rate over 3 days AND 1x over 6 hours
  → Budget exhausted by end of window
```

### Anti-patterns
- **Alert on CPU, not user experience** — CPU is a cause, users don't experience "high CPU"
- **No runbook link in alert** — if there's no documented action, don't page
- **Same severity for all environments** — prod P1 should page; dev P1 should notify
- **Alert on absence without baseline** — verify the metric normally emits before alerting on its absence

## Log Architecture

```
Application → Cloud Logging → Log Router
                                ├→ _Default bucket (30 day retention)
                                ├→ Compliance bucket (365+ days, if needed)
                                ├→ BigQuery (analytics, if needed)
                                └→ Exclusion filters (cost control)
```

### Cost Control
- Exclude DEBUG logs from ingestion
- Set appropriate retention per bucket
- Use log sampling for high-volume, low-value logs
- Monitor `logging.googleapis.com/billing/bytes_ingested` with budget alert
- Route to BigQuery for analytics instead of querying Cloud Logging directly
