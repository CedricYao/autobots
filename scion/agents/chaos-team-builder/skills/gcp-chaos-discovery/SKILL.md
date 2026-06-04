---
name: gcp-chaos-discovery
description: >-
  GCP infrastructure discovery commands for chaos engineering targeting.
  Scans compute, networking, identity, pipelines, observability, and storage
  to build an attack surface inventory.
---

# GCP Chaos Discovery

## Pre-Flight

Verify authentication and project access:

```bash
gcloud auth list 2>&1 | head -5
gcloud config get-value project
gcloud projects describe $(gcloud config get-value project) --format="value(projectId,name,lifecycleState)"
```

If no project is set, the scan cannot proceed.

## Compute Discovery

### Cloud Run

```bash
# All services with regions, SAs, VPC connectors
gcloud run services list --format="table(metadata.name,metadata.labels,status.url,spec.template.spec.serviceAccountName,spec.template.metadata.annotations['run.googleapis.com/vpc-access-connector'])" --project=$(gcloud config get-value project)

# Per-service details (env vars, resource limits, scaling)
for svc in $(gcloud run services list --format="value(metadata.name)" --project=$(gcloud config get-value project)); do
  echo "=== $svc ==="
  gcloud run services describe "$svc" --format="yaml(spec.template.spec.containers)" --project=$(gcloud config get-value project) --region=REGION
done
```

**Chaos signals:**
- Services sharing a VPC connector → network SPOF
- Services using default SA → infra attack surface
- Services with single revision → no traffic split fallback
- Env vars with secrets → app attack surface

### GKE

```bash
# Clusters
gcloud container clusters list --format="table(name,location,currentMasterVersion,currentNodeCount,status)" --project=$(gcloud config get-value project)

# Workloads (requires cluster credentials)
CLUSTER=<cluster-name>
ZONE=<zone-or-region>
gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project=$(gcloud config get-value project)

# Namespaces
kubectl get namespaces

# Deployments with replicas and images
kubectl get deployments --all-namespaces -o wide

# Services with types and cluster IPs
kubectl get services --all-namespaces -o wide

# Pods with status
kubectl get pods --all-namespaces -o wide

# NetworkPolicies (existing)
kubectl get networkpolicies --all-namespaces

# Resource limits
kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: {.spec.template.spec.containers[0].resources}{"\n"}{end}'

# HPA status
kubectl get hpa --all-namespaces
```

**Chaos signals:**
- No NetworkPolicies → network attack surface (can inject policies for isolation)
- Single-replica deployments → infra fragility
- No resource limits → resource exhaustion target
- Services with ClusterIP only → internal-only, harder to observe externally

## Networking Discovery

### VPC and Subnets

```bash
gcloud compute networks list --format="table(name,mode,IPv4Range)" --project=$(gcloud config get-value project)
gcloud compute networks subnets list --format="table(name,region,ipCidrRange,network,privateIpGoogleAccess,enableFlowLogs)" --project=$(gcloud config get-value project)
```

**Chaos signals:**
- Flow logs disabled → observability blindness during network attacks
- Subnets in single region → no regional failover

### Firewall Rules

```bash
gcloud compute firewall-rules list --format="table(name,network,direction,priority,sourceRanges,destinationRanges,allowed,targetTags)" --project=$(gcloud config get-value project)
```

**Chaos signals:**
- Source range 0.0.0.0/0 → overly permissive, P1 known gap
- Broad allowed protocols → attack surface amplification
- No deny rules → defense-in-depth weakness

### VPC Connectors

```bash
gcloud compute networks vpc-access connectors list --format="table(name,region,network,ipCidrRange,state,machineType,minThroughput,maxThroughput)" --project=$(gcloud config get-value project)
```

**Chaos signals:**
- Single connector serving multiple services → network SPOF
- Low throughput limits → saturation attack target

### Forwarding Rules and Load Balancers

```bash
gcloud compute forwarding-rules list --format="table(name,region,IPAddress,IPProtocol,portRange,target)" --project=$(gcloud config get-value project)
gcloud compute target-pools list --project=$(gcloud config get-value project) 2>/dev/null
gcloud compute backend-services list --project=$(gcloud config get-value project) 2>/dev/null
```

**Chaos signals:**
- VIPs with no visible forwarding rule → mystery backend (P1)
- Single backend → no failover

## Identity Discovery

### Service Accounts

```bash
gcloud iam service-accounts list --format="table(email,displayName,disabled)" --project=$(gcloud config get-value project)

# Per-SA role bindings
for sa in $(gcloud iam service-accounts list --format="value(email)" --project=$(gcloud config get-value project)); do
  echo "=== $sa ==="
  gcloud projects get-iam-policy $(gcloud config get-value project) --flatten="bindings[].members" --filter="bindings.members:serviceAccount:$sa" --format="table(bindings.role)" 2>/dev/null
done
```

**Chaos signals:**
- Single SA used by multiple workloads → shared blast radius
- SA with broad roles (editor, owner) → over-privileged
- Default compute SA in use → infra attack surface

### Secret Manager

```bash
gcloud secrets list --format="table(name,replication.automatic,createTime)" --project=$(gcloud config get-value project) 2>/dev/null
```

## Pipeline Discovery

### Cloud Deploy

```bash
gcloud deploy delivery-pipelines list --format="table(name,description)" --region=REGION --project=$(gcloud config get-value project)
gcloud deploy targets list --format="table(name,description,gke,run)" --region=REGION --project=$(gcloud config get-value project)
```

**Chaos signals:**
- Pipeline without approval gates → deploy sabotage vector
- Single pipeline for all environments → blast radius amplification

### Artifact Registry

```bash
gcloud artifacts repositories list --format="table(name,format,location,sizeBytes)" --project=$(gcloud config get-value project)
gcloud artifacts docker images list REGION-docker.pkg.dev/PROJECT/REPO --format="table(package,version,createTime)" --limit=20 --project=$(gcloud config get-value project) 2>/dev/null
```

## Observability Discovery

### Alert Policies

```bash
gcloud alpha monitoring policies list --format="json" --project=$(gcloud config get-value project) 2>/dev/null | python3 -c "
import json, sys
policies = json.load(sys.stdin)
for p in policies:
    name = p.get('displayName', 'unnamed')
    channels = p.get('notificationChannels', [])
    enabled = p.get('enabled', False)
    print(f'{name}: enabled={enabled}, channels={len(channels)}')
" 2>/dev/null
```

**Chaos signals:**
- Alert with zero notification channels → P1 silent alerting gap
- Alert disabled → monitoring blind spot
- No alert policies at all → complete observability gap

### Notification Channels

```bash
gcloud alpha monitoring channels list --format="table(displayName,type,enabled)" --project=$(gcloud config get-value project) 2>/dev/null
```

### Dashboards

```bash
gcloud monitoring dashboards list --format="table(displayName,name)" --project=$(gcloud config get-value project) 2>/dev/null
```

### Uptime Checks

```bash
gcloud monitoring uptime list-configs --format="table(displayName,monitoredResource.type)" --project=$(gcloud config get-value project) 2>/dev/null
```

## Storage Discovery

```bash
gsutil ls -p $(gcloud config get-value project) 2>/dev/null
# Per-bucket details
for bucket in $(gsutil ls -p $(gcloud config get-value project) 2>/dev/null); do
  echo "=== $bucket ==="
  gsutil lifecycle get "$bucket" 2>/dev/null
done
```
