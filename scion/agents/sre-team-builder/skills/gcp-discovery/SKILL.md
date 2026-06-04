---
name: gcp-discovery
description: >-
  GCP resource inventory commands for every major resource type. Used to discover
  what exists in a GCP project before building an SRE team. Commands grouped by
  category with expected output format and what to extract.
---

# GCP Discovery Commands

## Pre-Flight

Before running discovery, verify access:

```bash
# Verify authentication
gcloud auth list --format="table(account,status)"

# Verify project access
gcloud projects describe PROJECT_ID --format="table(projectId,projectNumber,name,lifecycleState)"

# List enabled APIs (determines which discovery commands will work)
gcloud services list --enabled --project=PROJECT_ID --format="table(name)" --sort-by=name
```

If auth fails, stop — discovery requires authenticated gcloud access to the target project.

## Compute Resources

### Cloud Run
```bash
# List services (all regions)
gcloud run services list --project=PROJECT_ID --format=json

# For each service, get detailed config:
gcloud run services describe SERVICE_NAME --region=REGION --project=PROJECT_ID --format=json
```

**Extract:** service name, region, URL, image, CPU/memory, concurrency, min/max instances, VPC connector, environment variables (names only, not values), service account, traffic split.

**Signals:** VPC connector usage → vpc-networking-sme needed. Multiple environments (dev/stage/prod) → likely Cloud Deploy managed. Backend references in env vars → dependency mapping.

### GKE Clusters
```bash
# List clusters
gcloud container clusters list --project=PROJECT_ID --format=json

# If clusters exist, describe each:
gcloud container clusters describe CLUSTER_NAME --location=LOCATION --project=PROJECT_ID --format=json
```

**Extract:** cluster name, location, node count, machine type, Autopilot vs Standard, master version, network/subnet, workload identity enabled.

**Signals:** Any cluster → microservices-sme needed. Workload Identity disabled → iam-sme flag. Multiple node pools → resource tuning concerns.

### Compute Engine
```bash
# List instances
gcloud compute instances list --project=PROJECT_ID --format=json
```

**Extract:** instance name, zone, machine type, status, network interfaces, service account.

**Signals:** Running instances → may need a compute-sme (not in current template set, flag as uncovered).

## CI/CD Resources

### Cloud Deploy
```bash
# List delivery pipelines
gcloud deploy delivery-pipelines list --project=PROJECT_ID --format=json

# For each pipeline:
gcloud deploy delivery-pipelines describe PIPELINE_NAME --project=PROJECT_ID --format=json

# List targets
gcloud deploy targets list --project=PROJECT_ID --format=json

# Recent releases
gcloud deploy releases list --delivery-pipeline=PIPELINE_NAME --project=PROJECT_ID --limit=5 --format=json
```

**Extract:** pipeline name, stages (targets), target regions, execution SA, recent release render state.

**Signals:** Any pipeline → cloud-deploy-sme needed. Pipeline stages matching Cloud Run services → deployment dependency mapped. Render failures → immediate action item.

### Artifact Registry
```bash
# List repositories
gcloud artifacts repositories list --project=PROJECT_ID --format=json

# For Docker repos, list images:
gcloud artifacts docker images list REPO_PATH --project=PROJECT_ID --include-tags --format=json --limit=20
```

**Extract:** repo name, format (Docker/Maven/npm), location, encryption, cleanup policies.

**Signals:** Docker repos → artifact-registry-sme needed. No cleanup policies → flag for lifecycle management. Images referenced by Cloud Run → supply chain link.

### Cloud Build
```bash
# Recent builds
gcloud builds list --project=PROJECT_ID --limit=10 --format=json

# Build triggers
gcloud builds triggers list --project=PROJECT_ID --format=json 2>/dev/null || echo "No triggers or API not configured"
```

**Extract:** recent build status, trigger sources, linked repos.

**Signals:** Active builds → CI/CD is in use. No triggers → manual builds or external CI (GitHub Actions).

## Networking

### VPC Networks
```bash
# List networks
gcloud compute networks list --project=PROJECT_ID --format=json

# List subnets
gcloud compute networks subnets list --project=PROJECT_ID --format=json
```

**Extract:** network name, auto/custom mode, routing mode, subnet CIDRs, regions.

### Firewall Rules
```bash
# List all rules
gcloud compute firewall-rules list --project=PROJECT_ID --format=json

# Flag overly-permissive rules
gcloud compute firewall-rules list --project=PROJECT_ID --filter="sourceRanges=0.0.0.0/0 AND direction=INGRESS" --format="table(name,priority,allowed)"
```

**Extract:** rule name, network, direction, priority, source/dest ranges, allowed protocols, target tags/SAs.

**Signals:** Rules with 0.0.0.0/0 source → CRITICAL security risk, flag for iam-sme and vpc-networking-sme. GKE-related rules (target tags with `gke-`) → GKE existed or exists.

### VPC Access Connectors
```bash
# List connectors (check each region where Cloud Run exists)
gcloud compute networks vpc-access connectors list --project=PROJECT_ID --format=json
```

**Extract:** connector name, region, network, machine type, min/max instances, state.

**Signals:** Any connector → vpc-networking-sme needed. Shared connector across multiple services → blast radius risk. e2-micro machine type → potential throughput bottleneck.

### Forwarding Rules & Load Balancers
```bash
# List forwarding rules (ILBs, external LBs)
gcloud compute forwarding-rules list --project=PROJECT_ID --format=json

# List backend services
gcloud compute backend-services list --project=PROJECT_ID --format=json

# List health checks
gcloud compute health-checks list --project=PROJECT_ID --format=json
```

**Extract:** forwarding rule name, IP address, target, load balancing scheme (INTERNAL/EXTERNAL), region.

**Signals:** Internal forwarding rules → internal service VIPs, map to microservices-sme. External LBs → user-facing endpoints.

### Static IPs
```bash
gcloud compute addresses list --project=PROJECT_ID --format=json
```

**Extract:** name, address, type (INTERNAL/EXTERNAL), status, region.

## IAM & Security

### Service Accounts
```bash
# List all SAs
gcloud iam service-accounts list --project=PROJECT_ID --format=json

# For each SA, check keys:
gcloud iam service-accounts keys list --iam-account=SA_EMAIL --format=json
```

**Extract:** SA email, display name, disabled status, key count, key types (USER_MANAGED vs SYSTEM_MANAGED).

**Signals:** Single SA used by multiple services → CRITICAL over-privilege. User-managed keys → key leak risk. Default compute SA with broad roles → immediate remediation.

### Project IAM Policy
```bash
gcloud projects get-iam-policy PROJECT_ID --format=json
```

**Extract:** all bindings (member → role mappings).

**Signals:** External members with broad roles → security review. Single SA with many roles → over-privilege. Owner/Editor roles on service accounts → excessive.

### Secret Manager
```bash
# Check if API is enabled
gcloud services list --enabled --project=PROJECT_ID --filter="name:secretmanager" --format=json

# If enabled, list secrets
gcloud secrets list --project=PROJECT_ID --format=json 2>/dev/null || echo "Secret Manager not enabled"
```

**Signals:** API not enabled → secrets likely in env vars, flag as HIGH risk. Few or no secrets → services may be using hardcoded values.

## Observability

### Cloud Monitoring
```bash
# Alerting policies
gcloud alpha monitoring policies list --project=PROJECT_ID --format=json 2>/dev/null || echo "No alerting policies"

# Dashboards
gcloud monitoring dashboards list --project=PROJECT_ID --format=json

# Uptime checks
gcloud monitoring uptime list-configs --project=PROJECT_ID --format=json

# Notification channels
gcloud alpha monitoring channels list --project=PROJECT_ID --format=json 2>/dev/null || echo "No notification channels"
```

**Extract:** alert policy names/conditions, dashboard names, uptime check targets, notification channel types.

**Signals:** No alerting policies → blind to incidents, CRITICAL gap. No uptime checks → no external availability monitoring. No notification channels → alerts fire but nobody is notified.

## Storage & Data

### Cloud Storage
```bash
gcloud storage buckets list --project=PROJECT_ID --format=json
```

**Extract:** bucket name, location, storage class, lifecycle rules, uniform access.

**Signals:** > 3 buckets or > 10 GB → cloud-storage-sme warranted. CI/CD-related bucket names → tie to Cloud Deploy/Build. No lifecycle policies → unbounded growth.

### Cloud SQL
```bash
gcloud sql instances list --project=PROJECT_ID --format=json 2>/dev/null || echo "Cloud SQL API not enabled or no instances"
```

**Signals:** Any instances → may need a database-sme (flag as uncovered by current templates).

### Pub/Sub
```bash
gcloud pubsub topics list --project=PROJECT_ID --format=json 2>/dev/null || echo "Pub/Sub not enabled or no topics"
gcloud pubsub subscriptions list --project=PROJECT_ID --format=json 2>/dev/null || echo "No subscriptions"
```

**Signals:** Active topics/subscriptions → asynchronous architecture, may need event-system expertise.

### Redis / Memorystore
```bash
gcloud redis instances list --project=PROJECT_ID --format=json 2>/dev/null || echo "Redis API not enabled"
```

**Signals:** Redis instances → caching layer, consider in service dependency mapping.

## Discovery Output Format

Compile all results into a structured inventory:

```yaml
project:
  id: "PROJECT_ID"
  number: "PROJECT_NUMBER"
  name: "PROJECT_NAME"

enabled_apis:
  - run.googleapis.com
  - clouddeploy.googleapis.com
  - ...

resources:
  cloud_run:
    count: N
    services: [...]
  gke:
    count: N
    clusters: [...]
  cloud_deploy:
    count: N
    pipelines: [...]
  # ... etc

cross_region_dependencies:
  - from: {service: "frontend-alt-prod", region: "us-west1"}
    to: {resource: "VIP 10.23.0.10", region: "us-central1"}
    via: "VPC connector west1-default"

security_findings:
  - severity: CRITICAL
    finding: "Single default SA for all workloads"
    affected: ["cloud-run", "cloud-deploy"]
  - severity: CRITICAL
    finding: "Firewall rule allow-ilb-permissive allows 0.0.0.0/0"
    affected: ["vpc-networking"]

uncovered_resources:
  - type: "Compute Engine instances"
    count: N
    note: "No SME template covers standalone VMs"
```
