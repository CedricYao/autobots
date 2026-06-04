---
name: cloud-logging
description: >-
  Skill for querying and analyzing Google Cloud Logging data during incident investigations.
  Use when you need to search logs, filter by severity, correlate across services, or
  extract structured data from GCP log entries.
---

# Cloud Logging

Utilities for analyzing logs, errors, and system health across Google Cloud deployments.

## Query Patterns

### By severity
```
severity>=ERROR
severity>=WARNING
```

### By resource type
```
resource.type="k8s_container"
resource.type="k8s_cluster"
resource.type="k8s_pod"
resource.type="cloud_run_revision"
```

### By namespace and service
```
resource.labels.namespace_name="online-boutique-demo"
resource.labels.container_name="SERVICE_NAME"
resource.labels.cluster_name="online-boutique-764d49"
```

### By time window
```
timestamp>="2026-01-01T00:00:00Z" AND timestamp<="2026-01-01T01:00:00Z"
```

### Kubernetes events (crashes, restarts)
```
resource.type="k8s_cluster" AND (jsonPayload.reason="BackOff" OR jsonPayload.reason="Killing" OR jsonPayload.reason="OOMKilling")
```

## DOs and DON'Ts

- **DO** use `timeout 60` on all `gcloud logging read` commands
- **DO** use `--limit` to cap results (start with 50-100)
- **DO** use `jq` to extract specific fields instead of reading raw JSON into context
- **DO** filter by severity first to reduce volume
- **DO NOT** read large log files directly into LLM context
- **DO NOT** run `gcloud logging read` without a time bound — it will scan all retained logs

## Useful jq Patterns

```bash
# Extract timestamp, severity, service, and message
jq -r '.[] | [.timestamp, .severity, .resource.labels.container_name, .textPayload // .jsonPayload.message // ""] | @tsv'

# Count errors by service
jq -r '[.[] | .resource.labels.container_name] | group_by(.) | map({service: .[0], count: length}) | sort_by(-.count) | .[] | [.service, .count] | @tsv'

# Extract unique error messages
jq -r '[.[] | .textPayload // .jsonPayload.message // ""] | unique | .[]'
```

## Log Buckets (boutique-demo-22)

| Bucket | Retention | Contents |
|--------|-----------|----------|
| `_Default` | 30 days | All standard logs |
| `_Required` | 400 days | Audit logs (locked) |
| `shop-logs` | 30 days | k8s_container + cloud_run_revision |
