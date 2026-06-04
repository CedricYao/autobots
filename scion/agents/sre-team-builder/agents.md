# SRE Team Builder — Workflow

## Phase 1: Discover (15–30 minutes)

Run gcloud commands to inventory all resources in the target GCP project. Record every resource with its name, region, status, and key configuration.

### Discovery Sequence

Run these command groups in order. Each group can be run in parallel within itself.

**Group 1 — Project basics:**
```bash
gcloud projects describe PROJECT_ID --format=json
gcloud services list --enabled --project=PROJECT_ID --format="table(name)"
```

**Group 2 — Compute resources:**
```bash
gcloud run services list --project=PROJECT_ID --format=json
gcloud container clusters list --project=PROJECT_ID --format=json
gcloud compute instances list --project=PROJECT_ID --format=json
```

**Group 3 — CI/CD resources:**
```bash
gcloud deploy delivery-pipelines list --project=PROJECT_ID --format=json
gcloud artifacts repositories list --project=PROJECT_ID --format=json
gcloud builds list --project=PROJECT_ID --limit=5 --format=json
```

**Group 4 — Networking:**
```bash
gcloud compute networks list --project=PROJECT_ID --format=json
gcloud compute networks subnets list --project=PROJECT_ID --format=json
gcloud compute firewall-rules list --project=PROJECT_ID --format=json
gcloud compute networks vpc-access connectors list --project=PROJECT_ID --format=json
gcloud compute forwarding-rules list --project=PROJECT_ID --format=json
gcloud compute addresses list --project=PROJECT_ID --format=json
```

**Group 5 — IAM & Security:**
```bash
gcloud iam service-accounts list --project=PROJECT_ID --format=json
gcloud projects get-iam-policy PROJECT_ID --format=json
gcloud services list --enabled --project=PROJECT_ID --filter="name:secretmanager" --format=json
```

**Group 6 — Observability:**
```bash
gcloud alpha monitoring policies list --project=PROJECT_ID --format=json
gcloud monitoring dashboards list --project=PROJECT_ID --format=json
gcloud monitoring uptime list-configs --project=PROJECT_ID --format=json
```

**Group 7 — Storage & Data:**
```bash
gcloud storage buckets list --project=PROJECT_ID --format=json
gcloud sql instances list --project=PROJECT_ID --format=json 2>/dev/null || echo "Cloud SQL API not enabled"
gcloud pubsub topics list --project=PROJECT_ID --format=json 2>/dev/null || echo "Pub/Sub API not enabled"
gcloud redis instances list --project=PROJECT_ID --format=json 2>/dev/null || echo "Redis API not enabled"
```

### Recording Discovery Results

For each resource found, record:
```yaml
- type: "Cloud Run Service"
  name: "frontend-alt-prod"
  region: "us-west1"
  identifier: "projects/PROJECT_ID/locations/us-west1/services/frontend-alt-prod"
  status: "Ready"
  key_config:
    image: "us-central1-docker.pkg.dev/PROJECT_ID/docker/frontend-alt:TAG"
    vpc_connector: "west1-default"
    min_instances: 0
    max_instances: 100
```

## Phase 2: Assess (10–15 minutes)

Match discovered resources to SME templates and assign priorities.

### Matching Rules

For each resource category, determine if a template is needed:

| Resource Found | Template | Auto-include? | Priority Logic |
|---------------|----------|--------------|----------------|
| Cloud Run services | cloud-run-sme | Yes | P1 if user-facing, P2 if internal |
| Cloud Deploy pipelines | cloud-deploy-sme | Yes | P2 (controls deployments) |
| Artifact Registry repos | artifact-registry-sme | Yes if Docker repos | P3 (supply chain) |
| Any GCP project | cloud-monitoring-sme | Always | P2 (meta-critical) |
| VPC connectors or custom firewall rules | vpc-networking-sme | Yes | P1 if cross-region or SPOF |
| Any GCP project | iam-sme | Always | P1 (security) |
| GKE clusters or ILBs | microservices-sme | Yes | P2 if active, deferred if unknown |
| > 3 buckets or > 10 GB | cloud-storage-sme | Conditional | P4 (support) |

### Cross-Cutting Risk Detection

Scan discovery results for these patterns:

| Pattern | Risk | Severity |
|---------|------|----------|
| Single SA used by multiple services | Over-privileged blast radius | CRITICAL |
| Firewall rule with source 0.0.0.0/0 | Effectively no firewall | CRITICAL |
| Cross-region dependency (services in different regions) | Latency + partition risk | HIGH |
| No Secret Manager API enabled | Secrets in env vars | HIGH |
| VPC connector shared across environments | Blast radius spans dev/stage/prod | HIGH |
| No alerting policies | Blind to incidents | HIGH |
| SA with user-managed keys | Key leak risk | MEDIUM |
| No lifecycle policies on storage | Unbounded cost growth | LOW |

### Team Sizing Recommendation

Based on resource count and complexity:

- **< 5 resources, single region:** Minimum team (3 composite agents)
- **5–15 resources, 1–2 regions:** Standard team (5–6 agents)
- **> 15 resources, multi-region, GKE + Cloud Run:** Full team (8 agents + sre-expert)

## Phase 3: Configure (10–15 minutes)

For each selected SME template, produce a configuration overlay with project-specific values.

### Config Overlay Format

```yaml
# config/cloud-run-sme.yaml
template: cloud-run-sme
priority: P1-critical
project_id: "boutique-demo-22"
project_number: "258519306384"
region: "us-west1"

resources:
  - name: "frontend-alt-prod"
    type: "Cloud Run Service"
    url: "https://frontend-alt-prod-5qeytedvha-uw.a.run.app"
    environment: production
  - name: "frontend-alt-stage"
    type: "Cloud Run Service"
    url: "https://frontend-alt-stage-5qeytedvha-uw.a.run.app"
    environment: staging
  - name: "frontend-alt-dev"
    type: "Cloud Run Service"
    url: "https://frontend-alt-dev-5qeytedvha-uw.a.run.app"
    environment: development

dependencies:
  - system: vpc-networking-sme
    resource: "VPC connector west1-default"
    type: hard
  - system: microservices-sme
    resource: "VIP 10.23.0.10"
    type: hard

health_checks:
  error_rate_threshold: "0.1%"
  latency_p99_threshold: "1s"
  cpu_threshold: "60%"
  memory_threshold: "70%"

immediate_actions: []

escalation_targets:
  networking: vpc-networking-sme
  backend: microservices-sme
  deployment: cloud-deploy-sme
```

### Filling Config Values

Every value in the config must come from discovery output:
- `project_id` → from `gcloud projects describe`
- `region` → from resource listing
- `resources[].name` → from `gcloud run services list` (or equivalent)
- `resources[].url` → from service description
- `dependencies` → inferred from resource cross-references (e.g., VPC connector in Cloud Run config)

Never use placeholder values. If a value can't be determined, flag it as a prerequisite for the agent to discover on first run.

## Phase 4: Generate Kit (5–10 minutes)

Produce the final deployment package.

### sre-team-manifest.yaml

```yaml
project_id: "PROJECT_ID"
project_number: "PROJECT_NUMBER"
generated_at: "TIMESTAMP"
team_size: N
team_composition: "full"  # or "minimum" or "standard"

agents:
  - template: cloud-run-sme
    name: "cloud-run-sme"
    priority: P1-critical
    config: config/cloud-run-sme.yaml
    auto_start: true

  - template: sre-expert
    name: "sre-expert"
    priority: P2-high
    config: null
    auto_start: true
    note: "General SRE SME — advisory resource for all other agents"

cross_cutting_risks:
  - risk: "Single default SA"
    severity: CRITICAL
    owner: iam-sme
  - risk: "allow-ilb-permissive firewall"
    severity: CRITICAL
    owner: vpc-networking-sme
```

### start-sre-team.sh

```bash
#!/bin/bash
set -euo pipefail

echo "Starting SRE team for PROJECT_ID..."

# Start agents in priority order
scion start cloud-run-sme --template cloud-run-sme --non-interactive
scion start iam-sme --template iam-sme --non-interactive
# ... one line per agent

echo "SRE team started. $N agents running."
echo "Run 'scion list --non-interactive' to see agent status."
```

### README.md

Summarize:
1. What was discovered (resource inventory)
2. What team was built (which agents, why)
3. What each agent covers (one line per agent)
4. Cross-cutting risks (prioritized list)
5. How to start the team (run start-sre-team.sh)
6. How to verify (check agent status, run health checks)

## Error Handling

- If gcloud auth fails: stop and report — can't discover without access
- If a discovery command fails (API not enabled): record the API as not enabled, don't fail the whole process
- If no resources found in any category: skip that SME template, note in README
- If project has resources not covered by any SME template: flag in README as uncovered
