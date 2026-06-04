---
name: cloud-trace
description: >-
  Skill for querying and analyzing Google Cloud Trace distributed tracing data.
  Use when investigating latency issues, analyzing request flows across microservice
  boundaries, or identifying slow spans in distributed call chains.
---

# Cloud Trace

Query and analyze distributed traces from Google Cloud Trace.

## API Commands

### List Traces
```bash
gcloud trace traces list \
  --project=boutique-demo-22 \
  --filter='start_time>="YYYY-MM-DDTHH:MM:SSZ"' \
  --limit=50 \
  --format=json
```

### Get Trace Detail
```bash
gcloud trace traces describe TRACE_ID \
  --project=boutique-demo-22 \
  --format=json
```

### REST API (for advanced queries)
```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://cloudtrace.googleapis.com/v2/projects/boutique-demo-22/traces?filter=..." \
  | jq '.traces[:10]'
```

## Span Analysis

### Critical Path
The critical path is the chain of spans that determines the total request latency:
1. Start from the root span
2. At each level, follow the child span that ends latest
3. The critical path spans are the latency bottleneck

### Latency Breakdown
For each span, calculate:
- **Self time** = span duration - sum(child span durations)
- **Child time** = sum(child span durations)
- High self time = processing bottleneck in that service
- High child time = bottleneck is downstream

### Error Detection
- Check span status for error codes
- Look for spans with `status.code != 0`
- Error spans near the leaf of the call tree are closest to root cause

## Istio/ASM Trace Behavior

- Istio sidecars automatically inject trace context headers (B3, W3C TraceContext)
- Each sidecar creates client and server spans for every service-to-service call
- loadgenerator has no sidecar — the first instrumented span is at the frontend's Istio sidecar
- Trace sampling is controlled by the mesh configuration
