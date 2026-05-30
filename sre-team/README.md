# SRE Team: boutique-demo-22

**Generated:** 2026-05-30
**Discovery method:** Live gcloud API calls
**Team composition:** Full team (9 agents)
**Regions:** us-central1, us-west1

---

## 1. Discovery Summary

### Project Overview
- **Project ID:** boutique-demo-22
- **Project Number:** 258519306384
- **Created:** 2022-08-25
- **State:** ACTIVE
- **Organization folder:** 491695784879

### What Was Discovered

| Category | Resources Found |
|----------|----------------|
| **Cloud Run** | 3 services: frontend-alt-dev, frontend-alt-stage, frontend-alt-prod (all us-west1) |
| **GKE** | 1 Autopilot cluster: online-boutique-764d49 (us-central1, 3 nodes, v1.35.3) |
| **Cloud Deploy** | 1 pipeline: alt-frontend-demo (dev → stage → prod), 6 targets |
| **Artifact Registry** | 1 Docker repo (us-central1, ~1.6 GB, scanning active) |
| **VPC Connectors** | 2: default-connector (us-central1), west1-default (us-west1) |
| **Firewall Rules** | 14 total: 1 CRITICAL (allow-all), 6 GKE-active, 5 default, 2 stale |
| **Static IPs** | 3: boutique-internal (10.23.0.10), hostname-server-vip (34.111.28.249), workstations PSC |
| **Forwarding Rules** | 1: GKE external LB on 34.46.255.20:80 |
| **Service Accounts** | 1 custom (default compute SA), plus Google-managed agents |
| **Storage** | 8 buckets (4 Cloud Deploy, 2 build, 1 Terraform state, 1 legacy GCR) |
| **Alerting** | 2 policies: Payment Service Health, Product Catalog Latency |
| **Dashboards** | 2: staging tests, Staging Service errors |
| **Uptime Checks** | 0 |
| **Secret Manager** | API enabled, secrets not inventoried |

### Architecture

```
Internet
    │
    ├─→ Cloud Run Frontend (us-west1)
    │       frontend-alt-{dev,stage,prod}
    │       │
    │       └─→ VPC Connector (west1-default)
    │               │
    │               └─→ Internal VIP 10.23.0.10 (us-central1)
    │                       │
    │                       └─→ 9 Backend Microservices (GKE)
    │                           Ad, Cart, Checkout, Currency,
    │                           Email, Payment, Product Catalog,
    │                           Recommendation, Shipping
    │
    └─→ GKE External LB 34.46.255.20:80 (us-central1)
            │
            └─→ GKE Frontend (online-boutique-demo/frontend-external)
```

### Delta from Previous Survey (2026-05-27)

| Change | Detail |
|--------|--------|
| **NEW** | GKE Autopilot cluster `online-boutique-764d49` in us-central1 (was "none running") |
| **NEW** | External forwarding rule 34.46.255.20:80 → GKE frontend |
| **NEW** | 8 new GKE firewall rules for online-boutique cluster |
| **NEW** | Secret Manager API now enabled (was disabled) |
| **NEW** | 2 alerting policies and 2 dashboards (were empty) |
| **NEW** | 4 additional Cloud Deploy storage buckets (total 8, was 4) |
| **NEW** | Terraform state bucket `boutique-demo-22-tf-state` |

---

## 2. Team Composition

### Why Full Team?
- Multi-region architecture (us-west1 + us-central1)
- Both Cloud Run AND GKE active workloads
- 9+ backend microservices
- 3 CRITICAL cross-cutting risks
- Active GKE cluster with service mesh

### Agent Roster

| # | Agent | Priority | Covers | Why Selected |
|---|-------|----------|--------|-------------|
| 1 | **vpc-networking-sme** | P1-critical | VPC connectors, firewall, IPs, cross-region arch | CRITICAL firewall vulnerability; cross-region SPOF |
| 2 | **iam-sme** | P1-critical | Service accounts, IAM policy, cross-project access | Single shared SA; cross-project privilege escalation |
| 3 | **cloud-run-sme** | P1-critical | 3 Cloud Run frontend services | User-facing production services |
| 4 | **microservices-sme** | P1-critical | GKE cluster, 9 backends, external LB | All backend services; shared VIP SPOF |
| 5 | **cloud-deploy-sme** | P2-high | Pipeline, 6 targets, source repo | Controls all production deployments |
| 6 | **cloud-monitoring-sme** | P2-high | Alerting, dashboards, observability gaps | Major monitoring gaps need remediation |
| 7 | **sre-expert** | P2-high | Cross-cutting coordination | Advisory for all agents |
| 8 | **artifact-registry-sme** | P3-medium | Docker registry, scanning, legacy GCR | Supply chain security |
| 9 | **cloud-storage-sme** | P4-low | 8 buckets, Terraform state | Terraform state protection; lifecycle management |

---

## 3. Cross-Cutting Risks

### CRITICAL (Immediate Action Required)

| ID | Risk | Owner |
|----|------|-------|
| CCR-001 | **`allow-ilb-permissive` firewall rule** — Priority 1, allows ALL protocols from 0.0.0.0/0 to all instances. Effectively no firewall. | vpc-networking-sme |
| CCR-002 | **Single default Compute SA with Editor role** — Used by all Cloud Run services, Cloud Deploy, and build. Compromise of any = compromise of all. | iam-sme |
| CCR-003 | **Cross-project SA privilege escalation** — `scion-autobot-engineer@deploy-demo-test` has Editor + IAM Admin + Project IAM Admin. Can escalate its own privileges. | iam-sme |

### HIGH

| ID | Risk | Owner |
|----|------|-------|
| CCR-004 | Cross-region dependency: Cloud Run (us-west1) → backends (us-central1). Inter-region failure severs frontend from all backends. | vpc-networking-sme |
| CCR-005 | Shared VIP 10.23.0.10 is SPOF for all 9 backend microservices. | microservices-sme |
| CCR-006 | Zero alerting for Cloud Run; no uptime checks anywhere. | cloud-monitoring-sme |
| CCR-007 | 11 project owners — excessive privilege distribution. | iam-sme |
| CCR-008 | GKE frontend serves HTTP only (port 80) — no TLS termination. | microservices-sme |

### MEDIUM

| ID | Risk | Owner |
|----|------|-------|
| CCR-009 | All environments run identical image tag — no env differentiation. | cloud-deploy-sme |
| CCR-010 | Stale firewall rules and orphaned resources from deleted GKE clusters. | vpc-networking-sme |
| CCR-011 | Distributed tracing disabled on Cloud Run frontend (DISABLE_TRACING=1). | cloud-run-sme |

### LOW

| ID | Risk | Owner |
|----|------|-------|
| CCR-012 | No lifecycle policies on storage buckets — unbounded cost growth. | cloud-storage-sme |

---

## 4. How to Start the Team

```bash
cd /scion-volumes/scratchpad/sre-team
./start-sre-team.sh
```

The script starts all 9 agents in priority order (P1 first, P4 last). Each agent receives its project-specific configuration overlay from the `config/` directory.

---

## 5. How to Verify

```bash
# Check agent status
scion list --non-interactive

# Inspect a specific agent
scion look <agent-name>

# View agent logs
scion look <agent-name>
```

### Expected Initial Actions by Agent

| Agent | First Action |
|-------|-------------|
| vpc-networking-sme | Audit allow-ilb-permissive rule; assess cross-region risk |
| iam-sme | Inventory SA usage; assess cross-project SA permissions |
| cloud-run-sme | Health check all 3 services; verify backend connectivity via VIP |
| microservices-sme | Connect to GKE cluster; verify all 9 backend services are running |
| cloud-deploy-sme | Verify pipeline health; check last successful release |
| cloud-monitoring-sme | Identify alerting gaps; propose uptime checks |
| artifact-registry-sme | Scan for vulnerabilities; check cleanup policies |
| cloud-storage-sme | Verify Terraform state bucket access controls and versioning |
| sre-expert | Review cross-cutting risks; coordinate remediation priorities |

---

## 6. File Inventory

```
sre-team/
├── sre-team-manifest.yaml          # Team manifest — agents, priorities, risks
├── start-sre-team.sh               # Launch script (executable)
├── README.md                       # This file
└── config/
    ├── cloud-run-sme.yaml          # 3 Cloud Run services, backend deps
    ├── cloud-deploy-sme.yaml       # Pipeline, targets, source repo
    ├── artifact-registry-sme.yaml  # Docker repo, scanning, legacy GCR
    ├── cloud-monitoring-sme.yaml   # Alerts, dashboards, gaps
    ├── vpc-networking-sme.yaml     # VPCs, connectors, firewall, IPs
    ├── iam-sme.yaml                # SAs, owners, cross-project access
    ├── microservices-sme.yaml      # GKE cluster, backends, external LB
    ├── cloud-storage-sme.yaml      # 8 buckets, Terraform state
    └── cross-cutting-risks.yaml    # 12 risks spanning multiple agents
```
