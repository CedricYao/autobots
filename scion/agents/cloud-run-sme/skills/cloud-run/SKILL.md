---
name: cloud-run
description: >-
  Cloud Run operational expertise: service ops, traffic management, scaling
  configuration, log/metric analysis, emergency deploy, environment config,
  and cross-region diagnosis for boutique-demo-22 frontend services.
---

# Cloud Run Operations

## View Commands (READ — safe at any time)

### Service Status
```bash
# List all Cloud Run services
gcloud run services list --region=us-west1 --project=boutique-demo-22 --format="table(name,status.url,status.conditions.type,status.conditions.status)"

# Describe specific service (full config)
gcloud run services describe frontend-alt-prod --region=us-west1 --project=boutique-demo-22 --format=yaml

# List revisions (deployment history)
gcloud run revisions list --service=frontend-alt-prod --region=us-west1 --project=boutique-demo-22 --limit=10 --format="table(name,status.conditions.status,metadata.creationTimestamp,spec.containerConcurrency)"

# Current traffic split
gcloud run services describe frontend-alt-prod --region=us-west1 --project=boutique-demo-22 --format="yaml(status.traffic)"
```

### Metrics
```bash
# Error rate (MQL)
fetch cloud_run_revision
| metric 'run.googleapis.com/request_count'
| filter resource.service_name == 'frontend-alt-prod'
| align rate(1m)
| group_by [metric.response_code_class], [value_request_count_aggregate: aggregate(value.request_count)]

# P99 latency
fetch cloud_run_revision
| metric 'run.googleapis.com/request_latencies'
| filter resource.service_name == 'frontend-alt-prod'
| align delta(1m)
| every 1m
| group_by [], [value_request_latencies_percentile: percentile(value.request_latencies, 99)]

# Instance count
fetch cloud_run_revision
| metric 'run.googleapis.com/container/instance_count'
| filter resource.service_name == 'frontend-alt-prod'
| align mean(1m)

# CPU and memory utilization
fetch cloud_run_revision
| metric 'run.googleapis.com/container/cpu/utilizations'
| filter resource.service_name == 'frontend-alt-prod'
| align mean(1m)
```

### Logs
```bash
# Recent errors
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="frontend-alt-prod" AND severity>=ERROR' --project=boutique-demo-22 --limit=50 --format=json --freshness=1h

# Request logs (all)
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="frontend-alt-prod" AND httpRequest.status>=500' --project=boutique-demo-22 --limit=20 --format=json --freshness=30m

# Backend connectivity errors (VPC connector / VIP)
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="frontend-alt-prod" AND textPayload=~"connection.*timeout|ECONNREFUSED|502"' --project=boutique-demo-22 --limit=20 --format=json --freshness=1h
```

### Dependencies
```bash
# VPC connector status
gcloud compute networks vpc-access connectors describe west1-default --region=us-west1 --project=boutique-demo-22 --format="yaml(state,machineType,minInstances,maxInstances,minThroughput,maxThroughput)"
```

## Modify Commands (WRITE — require operator access)

### Traffic Management
```bash
# Rollback: shift 100% traffic to known-good revision
gcloud run services update-traffic frontend-alt-prod --to-revisions=REVISION_NAME=100 --region=us-west1 --project=boutique-demo-22
# Risk: low | Reversible: yes | Approval: no

# Canary: send 10% to new revision
gcloud run services update-traffic frontend-alt-prod --to-revisions=NEW_REVISION=10,CURRENT_REVISION=90 --region=us-west1 --project=boutique-demo-22
# Risk: low | Reversible: yes | Approval: no

# Promote: shift 100% to latest
gcloud run services update-traffic frontend-alt-prod --to-latest --region=us-west1 --project=boutique-demo-22
# Risk: medium | Reversible: yes | Approval: recommended
```

### Scaling
```bash
# Set min instances (prevent cold starts)
gcloud run services update frontend-alt-prod --min-instances=2 --region=us-west1 --project=boutique-demo-22
# Risk: low (cost increase) | Reversible: yes

# Set max instances (cost cap)
gcloud run services update frontend-alt-prod --max-instances=100 --region=us-west1 --project=boutique-demo-22
# Risk: medium (may throttle under load) | Reversible: yes

# Set concurrency
gcloud run services update frontend-alt-prod --concurrency=80 --region=us-west1 --project=boutique-demo-22
# Risk: medium | Reversible: yes
```

### Emergency Deploy (bypasses Cloud Deploy pipeline)
```bash
# Direct deploy — EMERGENCY ONLY
gcloud run deploy frontend-alt-prod --image=us-central1-docker.pkg.dev/boutique-demo-22/docker/IMAGE:TAG --region=us-west1 --project=boutique-demo-22
# Risk: HIGH | Reversible: via traffic rollback | Approval: REQUIRED
# Policy exception: bypasses Cloud Deploy pipeline approval process
```

### Environment Configuration
```bash
# Update environment variables
gcloud run services update frontend-alt-prod --update-env-vars=KEY=VALUE --region=us-west1 --project=boutique-demo-22
# Risk: medium | Reversible: yes

# Update VPC connector
gcloud run services update frontend-alt-prod --vpc-connector=CONNECTOR_NAME --vpc-egress=all-traffic --region=us-west1 --project=boutique-demo-22
# Risk: HIGH (affects backend connectivity) | Approval: REQUIRED
```

## Change Records

### Primary: Cloud Deploy Release History
```bash
gcloud deploy releases list --delivery-pipeline=alt-frontend-demo --project=boutique-demo-22 --format="table(name,renderState,createTime)"
```

### Audit Logs
```bash
# Who modified Cloud Run services
gcloud logging read 'resource.type="cloud_run_revision" AND logName="projects/boutique-demo-22/logs/cloudaudit.googleapis.com%2Factivity"' --project=boutique-demo-22 --limit=20 --format=json --freshness=7d
```

### Revision History
```bash
gcloud run revisions list --service=frontend-alt-prod --region=us-west1 --project=boutique-demo-22 --format="table(name,metadata.creationTimestamp,status.conditions.status)"
```
Limitation: shows WHAT changed and WHEN, not WHO or WHY.

## Alert Signals

### P1 (page immediately)
- **Error rate > 1% for 2 minutes** — `run.googleapis.com/request_count` filtered by response_code_class=5xx. User-facing outage confirmed.
- **P99 latency > 3s for 5 minutes** — `run.googleapis.com/request_latencies`. Users experiencing unacceptable delays.

### P2 (alert, investigate within 15 minutes)
- **Error rate 0.1–1% for 5 minutes** — Degraded but not critical.
- **Instance count at max for 10 minutes** — May be approaching capacity limit.
- **Backend connectivity errors > 5/min** — VPC connector or VIP issue developing.

### P3 (track, business hours)
- **CPU > 80% sustained** — Right-sizing needed.
- **Memory > 85% sustained** — OOM risk.
- **Cold start rate > 10%** — min-instances may need increase.

## Cross-Region Diagnosis

The architecture Cloud Run (us-west1) → VPC Connector → VIP 10.23.0.10 (us-central1) creates a cross-region dependency. When diagnosing issues:

1. Check if the issue is Cloud Run itself or the backend path
2. Look for VPC connector saturation (connector at max instances)
3. Check cross-region latency (expect ~20-30ms baseline, alert if > 40ms)
4. VPC connector uses e2-micro instances — consider upgrading to e2-standard for throughput
5. All environments share the same connector — connector saturation affects dev, stage, AND prod
