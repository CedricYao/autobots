---
name: cloud-deploy
description: >-
  Cloud Deploy pipeline expertise: release management, rollout operations,
  approval workflows, Skaffold rendering, stage skew detection, audit trail,
  and emergency bypass procedures for the alt-frontend-demo pipeline.
---

# Cloud Deploy Operations

## View Commands (READ — safe at any time)

### Pipeline Status
```bash
# List delivery pipelines
gcloud deploy delivery-pipelines list --project=boutique-demo-22 --format="table(name,uid,createTime)"

# Describe pipeline (stages, targets)
gcloud deploy delivery-pipelines describe alt-frontend-demo --project=boutique-demo-22 --format=yaml

# List targets
gcloud deploy targets list --project=boutique-demo-22 --format="table(name,targetId,run.location)"
```

### Release Management
```bash
# List recent releases
gcloud deploy releases list --delivery-pipeline=alt-frontend-demo --project=boutique-demo-22 --limit=10 --format="table(name,renderState,createTime,deliveryPipelineSnapshot.serialPipeline.stages.targetId)"

# Describe specific release (full details)
gcloud deploy releases describe RELEASE_NAME --delivery-pipeline=alt-frontend-demo --project=boutique-demo-22 --format=yaml

# List rollouts for a release
gcloud deploy rollouts list --release=RELEASE_NAME --delivery-pipeline=alt-frontend-demo --project=boutique-demo-22 --format="table(name,state,approvalState,deployStartTime,deployEndTime,targetId)"
```

### Rollout Details
```bash
# Describe specific rollout
gcloud deploy rollouts describe ROLLOUT_NAME --release=RELEASE_NAME --delivery-pipeline=alt-frontend-demo --project=boutique-demo-22 --format=yaml

# Check target execution config (SA, pool, artifacts)
gcloud deploy targets describe TARGET_NAME --project=boutique-demo-22 --format="yaml(executionConfigs)"
```

### Stage Skew Detection
```bash
# Compare deployed versions across stages
# Run for each target and compare release names:
gcloud deploy rollouts list --release=LATEST_RELEASE --delivery-pipeline=alt-frontend-demo --project=boutique-demo-22 --format="table(targetId,state)"
```
Healthy: all targets on same release or within 2 releases. Critical: prod > 5 releases behind staging.

### Logs
```bash
# Render logs (why did rendering fail?)
gcloud logging read 'resource.type="clouddeploy.googleapis.com/DeliveryPipeline" AND resource.labels.pipeline_id="alt-frontend-demo"' --project=boutique-demo-22 --limit=20 --format=json --freshness=1h

# Deploy audit logs (who triggered what?)
gcloud logging read 'logName="projects/boutique-demo-22/logs/cloudaudit.googleapis.com%2Factivity" AND protoPayload.serviceName="clouddeploy.googleapis.com"' --project=boutique-demo-22 --limit=20 --format=json --freshness=7d
```

## Modify Commands (WRITE — require operator access)

### Release Operations
```bash
# Create a new release
gcloud deploy releases create RELEASE_NAME --delivery-pipeline=alt-frontend-demo --project=boutique-demo-22 --images=IMAGE_NAME=IMAGE_PATH
# Risk: low (starts at first stage) | Reversible: yes (rollback target)

# Promote release to next stage
gcloud deploy releases promote --release=RELEASE_NAME --delivery-pipeline=alt-frontend-demo --project=boutique-demo-22
# Risk: medium | Reversible: yes (rollback target)
```

### Approval Operations
```bash
# Approve production rollout
gcloud deploy rollouts approve ROLLOUT_NAME --release=RELEASE_NAME --delivery-pipeline=alt-frontend-demo --project=boutique-demo-22
# Risk: medium (releases to prod) | Reversible: via rollback

# Reject production rollout
gcloud deploy rollouts reject ROLLOUT_NAME --release=RELEASE_NAME --delivery-pipeline=alt-frontend-demo --project=boutique-demo-22
# Risk: low | Reversible: create new release
```

### Rollback
```bash
# Rollback a target to previous release
gcloud deploy targets rollback TARGET_NAME --delivery-pipeline=alt-frontend-demo --project=boutique-demo-22
# Risk: low | Reversible: promote again

# Cancel a stuck rollout
gcloud deploy rollouts cancel ROLLOUT_NAME --release=RELEASE_NAME --delivery-pipeline=alt-frontend-demo --project=boutique-demo-22
# Risk: low | Reversible: retry rollout
```

### Emergency Bypass
```bash
# Direct Cloud Run deploy (bypasses entire pipeline)
gcloud run deploy frontend-alt-prod --image=us-central1-docker.pkg.dev/boutique-demo-22/docker/IMAGE:TAG --region=us-west1 --project=boutique-demo-22
# Risk: HIGH | Policy exception: bypasses approval workflow
# Approval: REQUIRED | Document: incident record mandatory
```

## Change Records

### Primary: Release History
```bash
gcloud deploy releases list --delivery-pipeline=alt-frontend-demo --project=boutique-demo-22 --format="table(name,renderState,createTime)"
```
Captures: release name, render state, creation time, associated rollouts.

### Audit Logs
```bash
gcloud logging read 'logName="projects/boutique-demo-22/logs/cloudaudit.googleapis.com%2Factivity" AND protoPayload.serviceName="clouddeploy.googleapis.com"' --project=boutique-demo-22 --limit=20 --format=json --freshness=30d
```
Captures: who triggered releases, approvals, rollbacks. Retention: 400 days.

## Alert Signals

### P1 (page immediately)
- **Prod rollout FAILED** — deployment to production failed, service may be in inconsistent state.
- **Pipeline halted** — no releases progressing through any stage for > 1 hour during active development.

### P2 (alert, investigate within 15 minutes)
- **Render failure** — release can't render, blocking all deployments.
- **Rollout stuck IN_PROGRESS > 15 min** — likely SA permission issue or Cloud Run update failure.
- **Prod approval pending > 4 hours** — deployment bottleneck.

### P3 (track, business hours)
- **Stage skew > 3 releases** — prod falling behind staging, accumulating deployment risk.
- **Render time > 5 min** — Skaffold configuration may need optimization.

## Skaffold Configuration

The pipeline uses Skaffold for manifest rendering. Key files:
- `skaffold.yaml` — defines build artifacts and deploy profiles
- Profiles map to Cloud Deploy targets (dev, stage, prod)
- Rendering substitutes environment-specific values (service URLs, resource limits)

Common render failures:
- Missing environment substitution variable
- YAML syntax error in Kubernetes manifests
- Image reference not found in Artifact Registry
- Skaffold version incompatibility
