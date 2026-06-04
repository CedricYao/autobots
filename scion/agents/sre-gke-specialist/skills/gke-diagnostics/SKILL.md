---
name: gke-diagnostics
description: >-
  Comprehensive GKE and Kubernetes diagnostic procedures for pod crashes, OOMKills,
  resource exhaustion, scheduling failures, and deployment issues on GKE Autopilot
  clusters. Use when investigating workload-level issues on GKE.
---

# GKE Diagnostics

Systematic diagnostic procedures for GKE Autopilot clusters.

## Pod Failure Diagnosis Flowchart

```
Pod not running?
├── Status: CrashLoopBackOff
│   ├── Exit code 1 → Application error → check logs
│   ├── Exit code 137 → OOMKilled → check memory limits
│   └── Exit code 143 → SIGTERM → check liveness probe, preStop hook
├── Status: ImagePullBackOff
│   └── Check image name, registry auth, Artifact Registry access
├── Status: Pending
│   ├── Insufficient resources → check resource requests vs available capacity
│   ├── Unschedulable → check node selectors, taints, tolerations
│   └── Autopilot scaling → wait for node provisioning (1-3 min typical)
└── Status: Running but not Ready
    └── Check readiness probe → check application startup time
```

## Container Exit Codes

| Exit Code | Meaning | Investigation |
|-----------|---------|---------------|
| 0 | Clean exit | Check if expected (job completion) |
| 1 | Application error | Read container logs for stack trace |
| 2 | Shell misuse | Check entrypoint/command configuration |
| 126 | Permission denied | Check file permissions in container image |
| 127 | Command not found | Check entrypoint binary exists in image |
| 137 | SIGKILL (OOMKilled) | Compare memory usage vs limits |
| 143 | SIGTERM | Normal shutdown, check if initiated by deployment update or liveness failure |
| 255 | Unknown | Check dmesg/kernel logs for system-level issues |

## GKE Autopilot Considerations

- Nodes are fully managed — no SSH access, no DaemonSets, no privileged containers
- Resource requests MUST equal limits (Autopilot enforces this)
- Pod scheduling may take 1-3 minutes if new nodes need provisioning
- Minimum resources: 250m CPU, 512Mi memory per container (standard workloads)
- Node auto-upgrade is automatic — check for recent node version changes
- No access to kubelet logs or node-level metrics

## Resource Pressure Signals via Monitoring API

When kubectl is unavailable, use Cloud Monitoring:

```bash
# Container restart count (spike = crashes)
gcloud monitoring time-series list \
  --project=boutique-demo-22 \
  --filter='metric.type="kubernetes.io/container/restart_count" AND resource.labels.namespace_name="online-boutique-demo"' \
  --interval-start-time="YYYY-MM-DDTHH:MM:SSZ" \
  --format=json

# Container CPU usage
gcloud monitoring time-series list \
  --project=boutique-demo-22 \
  --filter='metric.type="kubernetes.io/container/cpu/core_usage_time" AND resource.labels.namespace_name="online-boutique-demo"' \
  --interval-start-time="YYYY-MM-DDTHH:MM:SSZ" \
  --format=json

# Container memory usage
gcloud monitoring time-series list \
  --project=boutique-demo-22 \
  --filter='metric.type="kubernetes.io/container/memory/used_bytes" AND resource.labels.namespace_name="online-boutique-demo"' \
  --interval-start-time="YYYY-MM-DDTHH:MM:SSZ" \
  --format=json
```
