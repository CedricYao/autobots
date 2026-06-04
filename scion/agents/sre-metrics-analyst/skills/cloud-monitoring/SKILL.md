---
name: cloud-monitoring
description: >-
  Skill for querying Google Cloud Monitoring APIs to extract time-series metrics,
  analyze alert policies, and assess service health. Use when investigating metric
  regressions, building Golden Signal assessments, or checking alert state.
---

# Cloud Monitoring

Utilities for analyzing metrics and monitoring data from Google Cloud Monitoring.

## Key APIs

### Time Series Query
```bash
gcloud monitoring time-series list \
  --project=boutique-demo-22 \
  --filter='metric.type="METRIC_TYPE"' \
  --interval-start-time="YYYY-MM-DDTHH:MM:SSZ" \
  --interval-end-time="YYYY-MM-DDTHH:MM:SSZ" \
  --format=json
```

### List Alert Policies
```bash
gcloud alpha monitoring policies list --project=boutique-demo-22 --format=json
```

### List Metric Descriptors
```bash
gcloud monitoring metrics-descriptors list \
  --project=boutique-demo-22 \
  --filter='metric.type=starts_with("istio.io")' \
  --format="table(type, description)"
```

## Istio/ASM Metrics Reference

| Metric | Type | Labels |
|--------|------|--------|
| `istio.io/service/server/request_count` | Delta | response_code, service_name |
| `istio.io/service/server/response_latencies` | Distribution | service_name |
| `istio.io/service/server/received_bytes_count` | Delta | service_name |
| `istio.io/service/server/sent_bytes_count` | Delta | service_name |
| `istio.io/service/server/connection_open_count` | Delta | service_name |
| `istio.io/service/server/connection_close_count` | Delta | service_name |

## Kubernetes Metrics Reference

| Metric | Type | Notes |
|--------|------|-------|
| `kubernetes.io/container/cpu/core_usage_time` | Cumulative | Rate for CPU usage |
| `kubernetes.io/container/memory/used_bytes` | Gauge | Current memory |
| `kubernetes.io/container/restart_count` | Cumulative | Delta for restart rate |
| `kubernetes.io/pod/volume/used_bytes` | Gauge | Disk pressure |

## Best Practices

- **Avoid context bloat:** API responses are massive. Always process with `jq` or export to CSV.
- **Use timeout:** Always `timeout 60 gcloud monitoring ...` to prevent hangs.
- **Paired metrics:** Compare related metrics side-by-side for correlation:
  - CPU vs Memory usage
  - Request count vs Response latency
  - Sent vs Received bytes
- **Metadata headers:** When exporting data, include time range and metric name at the top of the file.
