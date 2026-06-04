---
name: cloud-storage
description: >-
  Cloud Storage expertise: bucket operations, lifecycle policy management,
  storage IAM, cost management, CI/CD storage integration, and object
  management for boutique-demo-22 infrastructure buckets.
---

# Cloud Storage Operations

## View Commands (READ — safe at any time)

### Bucket Status
```bash
# List all buckets
gcloud storage buckets list --project=boutique-demo-22 --format="table(name,location,storageClass,public_access_prevention,uniform_bucket_level_access)"

# Describe bucket (full config)
gcloud storage buckets describe gs://BUCKET_NAME --format=yaml

# Bucket size summary
gcloud storage ls --long gs://BUCKET_NAME/ --summarize --recursive

# List objects (recent)
gcloud storage ls --long gs://BUCKET_NAME/ --recursive | tail -20
```

### Lifecycle Policies
```bash
# View lifecycle configuration
gcloud storage buckets describe gs://BUCKET_NAME --format="yaml(lifecycle)"
```

### IAM
```bash
# Bucket-level IAM policy
gcloud storage buckets get-iam-policy gs://BUCKET_NAME --format=json

# Check uniform bucket-level access
gcloud storage buckets describe gs://BUCKET_NAME --format="yaml(uniform_bucket_level_access)"
```

### CI/CD Integration
```bash
# Identify which buckets support which pipeline component:
# - Cloud Build artifacts bucket (build outputs)
# - Cloud Deploy staging bucket (release artifacts)
# - Cloud Deploy render bucket (rendered manifests)
# - Cloud Build logs bucket (build logs)

# Check recent Cloud Build artifacts
gcloud storage ls --long gs://BUCKET_NAME/source/ | tail -10

# Check Cloud Deploy release artifacts
gcloud storage ls --long gs://BUCKET_NAME/ | tail -10
```

### Audit Logs
```bash
# Storage access and modification logs
gcloud logging read 'logName="projects/boutique-demo-22/logs/cloudaudit.googleapis.com%2Factivity" AND protoPayload.serviceName="storage.googleapis.com"' --project=boutique-demo-22 --limit=20 --format=json --freshness=30d
```

## Modify Commands (WRITE — require operator access)

### Lifecycle Management
```bash
# Set lifecycle policy (delete objects older than 30 days)
# lifecycle.json:
# {
#   "rule": [
#     {
#       "action": {"type": "Delete"},
#       "condition": {"age": 30}
#     }
#   ]
# }
gcloud storage buckets update gs://BUCKET_NAME --lifecycle-file=lifecycle.json
# Risk: medium (may delete needed artifacts) | Reversible: update policy
# Approval: recommended — verify retention requirements first

# Remove lifecycle policy
gcloud storage buckets update gs://BUCKET_NAME --clear-lifecycle
# Risk: low (stops automatic deletion) | Reversible: re-apply policy
```

### Object Management
```bash
# Delete specific objects
gcloud storage rm gs://BUCKET_NAME/path/to/object
# Risk: HIGH (irreversible) | Reversible: NO (unless versioning enabled)
# Approval: REQUIRED for any production-related objects

# Delete old objects (bulk cleanup)
gcloud storage rm gs://BUCKET_NAME/** --recursive --older-than=30d
# Risk: HIGH | Reversible: NO
# Approval: REQUIRED
```

### Bucket Configuration
```bash
# Enable uniform bucket-level access
gcloud storage buckets update gs://BUCKET_NAME --uniform-bucket-level-access
# Risk: medium (changes access model) | Reversible: within 90 days

# Set storage class
gcloud storage buckets update gs://BUCKET_NAME --default-storage-class=NEARLINE
# Risk: low (affects new objects only) | Reversible: change class back
```

## Change Records

### Audit Logs
```bash
gcloud logging read 'logName="projects/boutique-demo-22/logs/cloudaudit.googleapis.com%2Factivity" AND protoPayload.serviceName="storage.googleapis.com"' --project=boutique-demo-22 --limit=20 --format=json --freshness=30d
```
Captures: bucket creation/deletion, IAM changes, lifecycle policy updates. Retention: 400 days.

### Object-level Logging (if enabled)
```bash
gcloud logging read 'logName="projects/boutique-demo-22/logs/cloudaudit.googleapis.com%2Fdata_access" AND protoPayload.serviceName="storage.googleapis.com"' --project=boutique-demo-22 --limit=20 --format=json --freshness=7d
```
Captures: object reads/writes. Must be explicitly enabled.

## Alert Signals

### P2 (alert, investigate within 15 minutes)
- **Pipeline failure with storage 403** — Cloud Build or Cloud Deploy can't write artifacts, blocking all deployments.

### P3 (track, business hours)
- **Storage > 10 GB** — cost concern, lifecycle policy needed.
- **No lifecycle policy on any bucket** — unbounded growth risk.
- **Objects older than 90 days** — stale artifacts accumulating.

### P4 (log, address opportunistically)
- **Storage class suboptimal** — artifacts accessed rarely should be NEARLINE/COLDLINE.
- **Fine-grained access on CI/CD buckets** — should be uniform bucket-level.

## Cost Management

### Storage Cost Factors
- Standard storage: ~$0.02/GB/month
- Operations: ~$0.005 per 1000 Class A (writes), ~$0.0004 per 1000 Class B (reads)
- Network egress: free within same region, charged cross-region

### Cost Optimization
1. **Lifecycle policies** — delete CI/CD artifacts after 30 days (saves ~90% of storage cost)
2. **Storage class** — move infrequently accessed objects to NEARLINE (50% cheaper)
3. **Deduplication** — Cloud Build may produce duplicate artifacts across builds
4. **Compression** — ensure build artifacts are compressed before storage

### Budget Alert
Set a budget alert at $5/month for storage. If triggered, investigate:
- Which bucket is growing fastest
- Are lifecycle policies working
- Is a pipeline producing abnormally large artifacts
