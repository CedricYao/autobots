# Chaos Team Builder — Workflow

## Phase 1: Discover Infrastructure

Scan the target GCP project systematically. Use the gcp-chaos-discovery skill for the full command set.

### Scan Order

1. **Compute** — Cloud Run services, GKE clusters and workloads, Cloud Functions
2. **Networking** — VPCs, subnets, firewall rules, VPC connectors, forwarding rules, load balancers
3. **Identity** — Service accounts, IAM bindings, Secret Manager secrets
4. **Pipeline** — Cloud Deploy pipelines, Cloud Build triggers, Artifact Registry repos
5. **Observability** — Alert policies, notification channels, dashboards, uptime checks
6. **Storage** — GCS buckets, Cloud SQL instances

### Output: Infrastructure Inventory

Build a structured inventory:

```yaml
project: <project-id>
region: <primary-region>
infrastructure:
  compute:
    cloud_run: [list of services with regions, SAs, VPC connectors]
    gke: [clusters, namespaces, deployments, services]
  networking:
    vpcs: [networks with subnets]
    firewall_rules: [rules with source/target/action — flag overly permissive]
    vpc_connectors: [connectors with attached services]
    forwarding_rules: [VIPs, backends]
  identity:
    service_accounts: [SAs with role bindings — flag shared/over-privileged]
    secrets: [Secret Manager secrets]
  pipeline:
    cloud_deploy: [pipelines with targets]
    artifact_registry: [repos with image counts]
  observability:
    alert_policies: [policies with notification channel status]
    dashboards: [dashboard names]
  storage:
    buckets: [buckets with lifecycle policies]
```

## Phase 2: Assess Attack Surfaces

Map discovered infrastructure to the three chaos domains.

### Domain Assessment

For each piece of infrastructure, determine:
1. **Which domain(s)** can attack it (infra, network, app)
2. **What attack types** are applicable
3. **What priority** it gets (P1-P4, see system prompt)
4. **What known gaps** exist (cross-cutting risks, prior incidents, missing monitoring)

### Risk Detection Rules

| IF you find... | THEN classify as... | Priority |
|----------------|---------------------|----------|
| Firewall rule with source 0.0.0.0/0 | Network attack surface | P1 |
| Single shared service account across workloads | Infra attack surface | P1 |
| VPC connector with no redundancy | Network SPOF | P2 |
| Alert policies with zero notification channels | Observer advantage | P1 |
| VIP with no visible forwarding rule | Network mystery target | P1 |
| GKE workloads without NetworkPolicy | Network attack surface | P2 |
| Cloud Run service with default SA | Infra attack surface | P2 |
| Pipeline without approval gates | App attack surface | P3 |
| Buckets without lifecycle policies | Infra attack surface | P4 |

## Phase 3: Configure Agent Templates

Generate 5 chaos agent templates, each tailored to the discovered infrastructure.

### Template Generation Rules

For each agent template:

1. **scion-agent.yaml** — standard config (200 turns, 4h for strategist/observer, 100 turns 2h for attack agents)
2. **system-prompt.md** — persona + project-specific context (discovered targets, known gaps)
3. **agents.md** — operational workflow with specific commands for this project
4. **skills/\*/SKILL.md** — attack or observation skills with real commands (not placeholders)

### Per-Agent Configuration

**chaos-strategist:**
- Receives the full infrastructure inventory
- Gets the prioritized attack surface list
- Gets the attack playbook structure (5 phases from research)
- Gets scoring criteria (TTD/TTDIAG/TTR thresholds)

**infra-chaos:**
- Gets compute inventory (instances, pods, SAs to target)
- Gets resource limits and quotas
- Gets SA permission details for manipulation attacks
- Gets storage targets

**network-chaos:**
- Gets network topology (VPCs, subnets, connectors, firewall rules)
- Gets GKE service/pod network info for NetworkPolicy attacks
- Gets VIP/forwarding rule details
- Gets connectivity paths to target

**app-chaos:**
- Gets service configurations (env vars, config maps, deployment specs)
- Gets pipeline details for deployment sabotage
- Gets dependency graph between services
- Gets Artifact Registry info for image attacks

**observer-chaos:**
- Gets monitoring inventory (alert policies, dashboards, notification channels)
- Gets baseline metrics for steady-state definition
- Gets known monitoring gaps
- Gets scoring rubric

## Phase 4: Generate Deployment Kit

### Output Files

```
.scion/templates/
├── chaos-strategist/
│   ├── scion-agent.yaml
│   ├── system-prompt.md
│   ├── agents.md
│   └── skills/attack-planning/SKILL.md
├── infra-chaos/
│   ├── scion-agent.yaml
│   ├── system-prompt.md
│   ├── agents.md
│   └── skills/infrastructure-attacks/SKILL.md
├── network-chaos/
│   ├── scion-agent.yaml
│   ├── system-prompt.md
│   ├── agents.md
│   └── skills/network-attacks/SKILL.md
├── app-chaos/
│   ├── scion-agent.yaml
│   ├── system-prompt.md
│   ├── agents.md
│   └── skills/application-attacks/SKILL.md
└── observer-chaos/
    ├── scion-agent.yaml
    ├── system-prompt.md
    ├── agents.md
    └── skills/chaos-observation/SKILL.md

chaos-team-manifest.yaml  (in project root or scratchpad)
```

### Validation Checklist

Before finalizing, verify:
- [ ] Every gcloud/kubectl command references real project ID, regions, cluster names
- [ ] Every attack has a corresponding rollback command
- [ ] Every attack has abort conditions
- [ ] Observer has baseline metrics defined
- [ ] Strategist has the complete attack surface inventory
- [ ] No placeholder values remain (search for `<`, `TODO`, `PLACEHOLDER`)
- [ ] Manifest has all 5 agents listed with correct template names

### Sync and Report

```bash
scion templates sync --all --non-interactive
```

Report completion to the requesting agent with:
- Number of templates created
- Number of attack surfaces identified per domain
- Top 5 priority targets
- Location of the manifest file
