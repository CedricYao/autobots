---
name: deploy-operations
description: >-
  Reference for Cloud Deploy and Kubernetes deployment operations in boutique-demo-22.
  Use when you need to check deployment state, perform rollbacks, or execute
  remediation via kubectl or gcloud deploy commands.
---

# Deploy Operations

Deployment management commands for the Online Boutique environment.

## Cloud Deploy Pipeline

### Pipeline: alt-frontend-demo
- **Stages:** dev -> stage -> prod (serial promotion)
- **Targets:** Cloud Run services in us-west1
- **Production approval:** Required for prod stage

```bash
# List releases
gcloud deploy releases list \
  --delivery-pipeline=alt-frontend-demo \
  --region=us-central1 \
  --project=boutique-demo-22

# Promote a release to next stage
gcloud deploy releases promote \
  --release=RELEASE_NAME \
  --delivery-pipeline=alt-frontend-demo \
  --region=us-central1 \
  --project=boutique-demo-22

# Rollback (create new rollout targeting previous release)
gcloud deploy rollouts create ROLLOUT_NAME \
  --release=PREVIOUS_RELEASE \
  --delivery-pipeline=alt-frontend-demo \
  --region=us-central1 \
  --project=boutique-demo-22
```

## Kubernetes Deployment Operations

### Check Current State
```bash
kubectl get deployments -n online-boutique-demo -o wide
kubectl get pods -n online-boutique-demo
kubectl describe deployment SERVICE_NAME -n online-boutique-demo
```

### Rollback
```bash
# Undo last deployment change
kubectl rollout undo deployment/SERVICE_NAME -n online-boutique-demo

# Rollback to specific revision
kubectl rollout undo deployment/SERVICE_NAME -n online-boutique-demo --to-revision=N

# Check rollout history
kubectl rollout history deployment/SERVICE_NAME -n online-boutique-demo
```

### Restart
```bash
kubectl rollout restart deployment/SERVICE_NAME -n online-boutique-demo
```

### Scale
```bash
kubectl scale deployment/SERVICE_NAME -n online-boutique-demo --replicas=N
```

### Environment Variable Patch
```bash
kubectl set env deployment/SERVICE_NAME -n online-boutique-demo KEY=VALUE
```

## Verification After Remediation

Always verify after any change:
```bash
# Check rollout status
kubectl rollout status deployment/SERVICE_NAME -n online-boutique-demo

# Check pod health
kubectl get pods -n online-boutique-demo -l app=SERVICE_NAME

# Check recent events
kubectl events -n online-boutique-demo --for=deployment/SERVICE_NAME
```

## Artifact Registry

Images are stored at: `us-central1-docker.pkg.dev/boutique-demo-22/docker/`

```bash
# List image tags
gcloud artifacts docker images list \
  us-central1-docker.pkg.dev/boutique-demo-22/docker/frontend-alt \
  --format=json
```
