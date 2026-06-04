---
name: artifact-registry
description: >-
  Artifact Registry expertise: image inspection, vulnerability scanning,
  lifecycle management, tagging workflows, supply chain security, and
  Container Analysis for boutique-demo-22 Docker repository.
---

# Artifact Registry Operations

## View Commands (READ — safe at any time)

### Image Inspection
```bash
# List all images
gcloud artifacts docker images list us-central1-docker.pkg.dev/boutique-demo-22/docker --include-tags --format="table(package,tags,createTime,updateTime)"

# List tags for a specific image
gcloud artifacts docker tags list us-central1-docker.pkg.dev/boutique-demo-22/docker/IMAGE --format="table(tag,version)"

# Describe image metadata (including scan status)
gcloud artifacts docker images describe us-central1-docker.pkg.dev/boutique-demo-22/docker/IMAGE@sha256:DIGEST --show-all-metadata --format=json

# List image versions with digests
gcloud artifacts docker images list us-central1-docker.pkg.dev/boutique-demo-22/docker/IMAGE --format="table(version,createTime,updateTime)" --limit=20
```

### Vulnerability Scanning
```bash
# List vulnerabilities for a specific image
gcloud artifacts vulnerabilities list --filter="resourceUri=https://us-central1-docker.pkg.dev/boutique-demo-22/docker/IMAGE@sha256:DIGEST" --format="table(vulnerability.shortDescription,vulnerability.effectiveSeverity,vulnerability.fixAvailable,vulnerability.packageIssue.affectedPackage)"

# List all CRITICAL vulnerabilities across repository
gcloud artifacts vulnerabilities list --filter="vulnerability.effectiveSeverity=CRITICAL" --format="table(resourceUri,vulnerability.shortDescription,vulnerability.fixAvailable)" --project=boutique-demo-22

# Check scan status for an image
gcloud artifacts docker images describe us-central1-docker.pkg.dev/boutique-demo-22/docker/IMAGE:TAG --show-all-metadata --format="yaml(discovery)"
```

### Repository Configuration
```bash
# Describe repository settings
gcloud artifacts repositories describe docker --location=us-central1 --project=boutique-demo-22 --format=yaml

# List cleanup policies
gcloud artifacts repositories describe docker --location=us-central1 --project=boutique-demo-22 --format="yaml(cleanupPolicies)"
```

### Storage
```bash
# Check repository size (approximate via listing)
gcloud artifacts docker images list us-central1-docker.pkg.dev/boutique-demo-22/docker --format=json | jq 'length'
```

## Modify Commands (WRITE — require operator access)

### Lifecycle Management
```bash
# Delete untagged images older than 30 days
gcloud artifacts docker images delete us-central1-docker.pkg.dev/boutique-demo-22/docker/IMAGE@sha256:DIGEST --delete-tags
# Risk: medium | Reversible: NO (image deleted permanently)
# Approval: recommended for tagged images

# Set cleanup policy
gcloud artifacts repositories set-cleanup-policies docker --location=us-central1 --project=boutique-demo-22 --policy=POLICY_FILE
# Risk: medium | Reversible: update policy
```

### Tagging
```bash
# Tag image for promotion
gcloud artifacts docker tags add us-central1-docker.pkg.dev/boutique-demo-22/docker/IMAGE@sha256:DIGEST us-central1-docker.pkg.dev/boutique-demo-22/docker/IMAGE:prod-YYYYMMDD
# Risk: low | Reversible: delete tag

# Remove tag
gcloud artifacts docker tags delete us-central1-docker.pkg.dev/boutique-demo-22/docker/IMAGE:TAG
# Risk: low | Reversible: re-tag
```

## Change Records

### Audit Logs
```bash
# Who pushed/deleted images
gcloud logging read 'logName="projects/boutique-demo-22/logs/cloudaudit.googleapis.com%2Factivity" AND protoPayload.serviceName="artifactregistry.googleapis.com"' --project=boutique-demo-22 --limit=20 --format=json --freshness=30d
```
Captures: push, delete, policy changes. Retention: 400 days.

### Image History
```bash
# Image creation timestamps (proxy for push history)
gcloud artifacts docker images list us-central1-docker.pkg.dev/boutique-demo-22/docker/IMAGE --format="table(version,createTime)" --sort-by=~createTime --limit=20
```

## Alert Signals

### P1 (page immediately)
- **Critical CVE in actively deployed image with known exploit** — immediate rebuild and redeploy required.

### P2 (alert, investigate within 15 minutes)
- **Critical CVE in deployed image (no known exploit)** — plan rebuild within 24 hours.
- **Registry API errors during deploy pipeline** — blocking deployments.

### P3 (track, business hours)
- **HIGH CVEs accumulating** — schedule patching sprint.
- **Storage > 5 GB without lifecycle policy** — cost risk.
- **Prod images > 7 days old** — freshness risk.

## Supply Chain Security

### Image Promotion Workflow
```
Build → Push to AR → Scan completes → No CRITICAL CVEs → Tag for staging
→ Deploy to staging → Verify → Tag for prod → Approve prod rollout → Deploy
```

### Binary Authorization (if enabled)
- Attestor verifies image was built by trusted pipeline
- Policy enforces only attested images can deploy to production
- Break-glass policy for emergencies (audited, time-limited)

### Best Practices
- Always reference images by digest (`@sha256:...`), not tag (`:latest`)
- Scan on push — don't deploy until scan completes
- Lifecycle policy: delete untagged images > 30 days, keep last 10 tagged versions
- Separate repositories for dev/staging/prod if strict isolation needed
