---
name: iam
description: >-
  IAM expertise: policy analysis, service account lifecycle, least-privilege
  design, Workload Identity Federation, Secret Manager operations, audit log
  analysis, IAM recommender, and incident response for boutique-demo-22.
---

# IAM Operations

## View Commands (READ — safe at any time)

### IAM Policy Analysis
```bash
# Project-level IAM policy
gcloud projects get-iam-policy boutique-demo-22 --format=json

# List all role bindings for a specific member
gcloud projects get-iam-policy boutique-demo-22 --flatten="bindings[].members" --filter="bindings.members:SA_EMAIL" --format="table(bindings.role)"

# List all custom roles
gcloud iam roles list --project=boutique-demo-22 --format="table(name,title,stage)"

# Describe a role (see permissions)
gcloud iam roles describe ROLE_NAME --format="yaml(includedPermissions)"
```

### Service Account Management
```bash
# List all service accounts
gcloud iam service-accounts list --project=boutique-demo-22 --format="table(email,displayName,disabled)"

# Describe SA (creation time, unique ID)
gcloud iam service-accounts describe SA_EMAIL --format=yaml

# List SA keys
gcloud iam service-accounts keys list --iam-account=SA_EMAIL --format="table(name,validAfterTime,validBeforeTime,keyType,keyOrigin)"

# Check SA usage (IAM Recommender)
gcloud recommender recommendations list --recommender=google.iam.policy.Recommender --project=boutique-demo-22 --format="table(name,description,priority)"
```

### IAM Audit Logs
```bash
# Admin activity logs (always on, 400 day retention)
gcloud logging read 'logName="projects/boutique-demo-22/logs/cloudaudit.googleapis.com%2Factivity" AND protoPayload.methodName=~"SetIamPolicy|CreateServiceAccount|DeleteServiceAccount|CreateServiceAccountKey"' --project=boutique-demo-22 --limit=20 --format=json --freshness=30d

# Data access logs (must be enabled)
gcloud logging read 'logName="projects/boutique-demo-22/logs/cloudaudit.googleapis.com%2Fdata_access"' --project=boutique-demo-22 --limit=20 --format=json --freshness=7d

# SA authentication events
gcloud logging read 'protoPayload.authenticationInfo.principalEmail=~"@boutique-demo-22.iam.gserviceaccount.com"' --project=boutique-demo-22 --limit=20 --format=json --freshness=24h
```

### Secret Manager
```bash
# List secrets (if API enabled)
gcloud secrets list --project=boutique-demo-22 --format="table(name,createTime,replication.automatic)"

# Describe secret (metadata only — NOT the value)
gcloud secrets describe SECRET_NAME --project=boutique-demo-22 --format=yaml

# List secret versions
gcloud secrets versions list SECRET_NAME --project=boutique-demo-22 --format="table(name,state,createTime)"
```

### Workload Identity Federation
```bash
# List workload identity pools
gcloud iam workload-identity-pools list --location=global --project=boutique-demo-22 --format="table(name,displayName,state)"

# Describe pool (providers, attribute mapping)
gcloud iam workload-identity-pools describe POOL_NAME --location=global --project=boutique-demo-22 --format=yaml
```

## Modify Commands (WRITE — require operator access)

### Service Account Lifecycle
```bash
# Create dedicated SA
gcloud iam service-accounts create cloud-run-frontend-sa --display-name="Cloud Run Frontend SA" --project=boutique-demo-22
# Risk: low | Reversible: delete SA

# Assign role to SA
gcloud projects add-iam-policy-binding boutique-demo-22 --member="serviceAccount:cloud-run-frontend-sa@boutique-demo-22.iam.gserviceaccount.com" --role="roles/run.invoker"
# Risk: low (granting access) | Reversible: remove binding

# Disable SA (containment)
gcloud iam service-accounts disable SA_EMAIL --project=boutique-demo-22
# Risk: HIGH (services using this SA will fail) | Reversible: enable
# Approval: REQUIRED unless active security incident

# Delete SA key
gcloud iam service-accounts keys delete KEY_ID --iam-account=SA_EMAIL --project=boutique-demo-22
# Risk: HIGH (services using this key will fail) | Reversible: NO
# Approval: REQUIRED unless active security incident
```

### IAM Policy Changes
```bash
# Remove over-privileged binding
gcloud projects remove-iam-policy-binding boutique-demo-22 --member=MEMBER --role=ROLE
# Risk: HIGH (service may lose access) | Reversible: add binding back
# Approval: REQUIRED — verify service doesn't need the role first

# Add binding
gcloud projects add-iam-policy-binding boutique-demo-22 --member=MEMBER --role=ROLE
# Risk: medium (expanding access) | Reversible: remove binding
```

### Secret Manager
```bash
# Enable Secret Manager API
gcloud services enable secretmanager.googleapis.com --project=boutique-demo-22
# Risk: low | Reversible: disable (but secrets are lost)

# Create secret
gcloud secrets create SECRET_NAME --replication-policy="automatic" --project=boutique-demo-22
# Risk: low | Reversible: delete secret

# Add secret version
gcloud secrets versions add SECRET_NAME --data-file=SECRET_FILE --project=boutique-demo-22
# Risk: low | Reversible: disable version

# Disable old version (after rotation)
gcloud secrets versions disable VERSION_ID --secret=SECRET_NAME --project=boutique-demo-22
# Risk: medium (services using old version will fail) | Reversible: enable
```

## Change Records

### Primary: IAM Audit Logs
```bash
gcloud logging read 'logName="projects/boutique-demo-22/logs/cloudaudit.googleapis.com%2Factivity" AND protoPayload.serviceName="iam.googleapis.com"' --project=boutique-demo-22 --limit=20 --format=json --freshness=30d
```
Captures: all IAM changes (bindings, SAs, keys). Retention: 400 days. Immutable.

### Policy Analyzer (who can access what)
```bash
gcloud asset analyze-iam-policy --organization=ORG_ID --identity=SA_EMAIL --project=boutique-demo-22 --format=json
```

## Alert Signals

### P1 (page immediately)
- **SA key created for production SA** — potential credential leak vector.
- **Owner/Editor role granted to external identity** — potential unauthorized access.
- **SA disabled unexpectedly** — potential service disruption or containment action.

### P2 (alert, investigate within 15 minutes)
- **New SA created outside of change management** — potential unauthorized SA.
- **IAM policy binding change on production resources** — verify authorized.
- **Secret accessed from unexpected identity** — potential credential misuse.

### P3 (track, business hours)
- **IAM Recommender flags unused permissions** — schedule least-privilege tightening.
- **SA key older than 90 days** — rotation needed.
- **Multiple SAs with overlapping roles** — consolidation opportunity.

## Least-Privilege Design

### Target SA Architecture for boutique-demo-22

| Service Account | Purpose | Roles |
|----------------|---------|-------|
| `cloud-run-frontend-sa` | Cloud Run frontend services | `roles/run.invoker`, `roles/cloudtrace.agent` |
| `cloud-deploy-sa` | Cloud Deploy pipeline | `roles/clouddeploy.operator`, `roles/run.admin`, `roles/iam.serviceAccountUser` |
| `sre-observer-sa` | SRE agent read-only access | `roles/monitoring.viewer`, `roles/logging.viewer`, `roles/run.viewer` |
| `sre-operator-sa` | SRE agent incident response | `roles/run.admin`, `roles/monitoring.editor` (break-glass, time-limited) |

### Migration Path
1. Create dedicated SAs with minimum roles
2. Update Cloud Run services to use new SAs (one at a time, starting with dev)
3. Monitor for permission denied errors (indicates missing role)
4. Add missing roles as discovered (iterate to least privilege)
5. After 30 days with no permission denied: restrict default SA to `roles/viewer`
6. After 90 days: consider disabling default SA entirely
