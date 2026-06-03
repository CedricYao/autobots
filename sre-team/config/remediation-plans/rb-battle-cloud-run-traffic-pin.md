# Runbook: RB-006 — Cloud Run Emergency Traffic Pinning
## Trigger: Unauthorized revision detected on any frontend-alt service

### Overview
When a chaos team or unauthorized actor creates a new Cloud Run revision, pin traffic to the known-good revision to prevent customer impact.

### Prerequisites
- `gcloud` CLI authenticated with `run.services.update` permission
- Known-good revision tag: `lawi7y9v` (verified baseline)

### Steps

#### 1. Identify the Attack
```bash
# Check current traffic split
gcloud run services describe frontend-alt-{dev|stage|prod} \
  --project=boutique-demo-22 --region=us-west1 \
  --format='yaml(status.traffic)'

# Check for unauthorized revisions (compare generation number)
gcloud run services describe frontend-alt-{dev|stage|prod} \
  --project=boutique-demo-22 --region=us-west1 \
  --format='value(metadata.generation)'
```

#### 2. Pin Traffic to Known-Good Revision
```bash
# Pin 100% traffic to known-good revision
gcloud run services update-traffic frontend-alt-{dev|stage|prod} \
  --project=boutique-demo-22 --region=us-west1 \
  --to-tags=lawi7y9v=100
```

#### 3. Verify
```bash
# Confirm traffic is pinned
gcloud run services describe frontend-alt-{dev|stage|prod} \
  --project=boutique-demo-22 --region=us-west1 \
  --format='yaml(status.traffic)'

# Verify env vars are correct on active revision
gcloud run services describe frontend-alt-{dev|stage|prod} \
  --project=boutique-demo-22 --region=us-west1 \
  --format='yaml(spec.template.spec.containers[0].env)'
```

#### 4. Clean Up Unauthorized Revisions
```bash
# List all revisions
gcloud run revisions list --service=frontend-alt-{dev|stage|prod} \
  --project=boutique-demo-22 --region=us-west1

# Delete unauthorized revisions (cannot delete latest)
gcloud run revisions delete {revision-name} \
  --project=boutique-demo-22 --region=us-west1 --quiet
```

### Known-Good Baseline
| Service | Revision Tag | Generation | Env Vars | Startup Probe |
|---------|-------------|------------|----------|---------------|
| frontend-alt-dev | lawi7y9v | 60 | 12 vars, PRODUCT_CATALOG=10.23.0.10:3550 | fT=3,pS=10,tS=5 |
| frontend-alt-stage | lawi7y9v | 34 | 12 vars, PRODUCT_CATALOG=10.23.0.10:3550 | None (baseline) |
| frontend-alt-prod | lawi7y9v | 32 | 12 vars, PRODUCT_CATALOG=10.23.0.10:3550 | fT=3,pS=10,tS=5 |

### Escalation
If traffic cannot be pinned (permission denied): escalate to IAM SME to check if `run.services.update` or `iam.serviceAccounts.actAs` has been revoked.
