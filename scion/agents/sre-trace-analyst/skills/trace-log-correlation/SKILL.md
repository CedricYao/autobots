---
name: trace-log-correlation
description: >-
  Correlate Cloud Trace spans with Cloud Logging entries for complete request forensics.
  Use as a fallback when trace data is sparse, or to enrich trace analysis with
  detailed log context from specific services.
---

# Trace-Log Correlation

Techniques for correlating distributed traces with log entries across the Online Boutique microservices.

## Correlation Methods

### By Trace ID
When both trace and log data exist, correlate via the trace ID field:

```bash
# Find logs for a specific trace
gcloud logging read \
  'resource.type="k8s_container" AND trace="projects/boutique-demo-22/traces/TRACE_ID"' \
  --project=boutique-demo-22 \
  --format=json
```

### By Timestamp Window
When trace IDs are unavailable, correlate by narrow time windows:

```bash
# Find all service interactions within a 5-second window
gcloud logging read \
  'resource.type="k8s_container" AND resource.labels.namespace_name="online-boutique-demo" AND timestamp>="YYYY-MM-DDTHH:MM:SSZ" AND timestamp<="YYYY-MM-DDTHH:MM:SSZ" AND httpRequest.requestUrl!=""' \
  --project=boutique-demo-22 \
  --format=json \
  --limit=100
```

### By Request Path
For HTTP requests through the frontend:

```bash
# Find request entries for a specific path
gcloud logging read \
  'resource.type="k8s_container" AND httpRequest.requestUrl=~"/product/" AND resource.labels.container_name="frontend"' \
  --project=boutique-demo-22 \
  --format=json \
  --limit=20
```

## Service Dependency Map

Use this map to follow request flow through logs when traces are unavailable:

| Source Service | Destination Services | Protocol |
|---------------|---------------------|----------|
| frontend | adservice, productcatalogservice, currencyservice, cartservice, recommendationservice, shippingservice, checkoutservice | gRPC |
| checkoutservice | cartservice, productcatalogservice, currencyservice, shippingservice, paymentservice, emailservice | gRPC |
| recommendationservice | productcatalogservice | gRPC |

## Latency Estimation from Logs

When trace span durations are unavailable, estimate latency from log timestamps:
1. Find the request log entry at service A (timestamp T1)
2. Find the corresponding response/completion log at service A (timestamp T2)
3. Service A processing time ~ T2 - T1
4. Compare across services in the call chain to find where time is spent
