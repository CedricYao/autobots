# PSH Incident LYGWHYJ — Blast Radius, Dependencies & Mitigation Plan
**Project:** boutique-demo-22 (258519306384)
**Date:** 2026-06-08T16:00Z
**Prepared by:** SRE Team Lead (coordinating 7 SMEs + SRE Expert)
**Classification:** SEV3 — Resolved GCP VPC incident with limited direct impact

---

## Executive Summary

**PSH Event LYGWHYJ is a RESOLVED Google VPC incident.** Cloud NGFW generated spurious firewall logs for rules that did not have logging enabled, caused by a GCP networking software update. Duration: ~18 hours (Jun 7 13:55 UTC — Jun 8 08:04 UTC). Both our regions (us-west1 and us-central1) were in the 175 affected regions.

**Direct impact on boutique-demo-22: LOW.** No connectivity disruption. Both traffic paths are currently healthy (PATH A: Cloud Run HTTP 200 in 0.76s, PATH B: GKE HTTP 200 in 0.04s). The primary impact was spurious firewall log entries during the incident window.

**Concurrent degradation (UNRELATED to PSH):** Frontend-alt-prod and frontend-alt-stage experienced intermittent HTTP 500s from ~13:06–15:08 UTC today due to redis-cart pod preemption in GKE Autopilot. This is now recovered.

---

## Section 1: Blast Radius Analysis

### Direct PSH Impact (VPC/Cloud NGFW Spurious Logging)

| Component | Affected? | Impact | Severity |
|-----------|-----------|--------|----------|
| VPC Network (default) | Yes | Spurious firewall logs generated for 24 rules without logging enabled | LOW |
| VPC Connector (west1-default) | No | State: READY, functional throughout | NONE |
| VIP 10.23.0.10 (ILB) | No | All 9 forwarding rules intact, cross-region routing unaffected | NONE |
| Cloud Run services | No | Control plane healthy, revisions stable | NONE |
| GKE cluster | No | 4/4 nodes Ready, all 12 pods Running | NONE |
| Cloud Deploy pipeline | No | Dormant, no active deployments | NONE |
| Artifact Registry | No | Repository healthy, images pullable | NONE |
| IAM / Service Accounts | No | IAM policy unchanged (etag `BwZTTqxdPng=`), no unauthorized changes | NONE |

### Indirect/Concurrent Impact (Redis-Cart Preemption — NOT PSH-caused)

Two distinct error bursts (NOT continuous degradation):

| Burst | Window | Duration | Errors | Cause |
|-------|--------|----------|--------|-------|
| **#1** | 14:06:14Z – 14:06:59Z | ~45 seconds | 52 | Transient Redis connectivity loss on old pod (10.91.4.9) |
| **#2** | 15:07:00Z – 15:08:27Z | ~87 seconds | 65 | redis-cart pod PREEMPTED by Autopilot; new pod (10.91.4.11) started at 15:07:52Z |

**Normal operations confirmed between bursts (14:07Z–15:06Z, ~59 minutes).**

| Component | Status | Detail |
|-----------|--------|--------|
| redis-cart pod | RECOVERED | New pod redis-cart-6c7d999768-lhg68, Running, Ready 2/2, 0 restarts. BGSAVE healthy. |
| cartservice | RECOVERED | Pod cartservice-79dcbdbfc-d88bn reconnected via DNS at 15:08:01Z. Healthy 52+ minutes. |
| frontend-alt-prod | RECOVERED | 7 HTTP 500s across both bursts. p99 latency peaked at 6503ms (SLO breach at 5000ms). |
| frontend-alt-stage | RECOVERED | 6 HTTP 500s across both bursts. |
| frontend-alt-dev | HEALTHY | No errors throughout. |

Root cause hypothesis: Node gk3-online-boutique-764d49-pool-3-4a7d2de9-7dhh went NotReady, triggering Autopilot node replacement. Burst 1 was an early symptom; Burst 2 was the preemption itself.

### Blast Radius Verdict by Domain

| Domain | SME | Verdict | Key Finding |
|--------|-----|---------|-------------|
| **IAM & Security** | iam-sme | NO ACTIVE COMPROMISE | Etag unchanged, no user-managed keys, no SetIamPolicy in audit logs. Systemic risk from CCR-002 remains. |
| **VPC & Networking** | vpc-networking-sme | NO CONNECTIVITY IMPACT | Connector READY, cross-region routing functional. Spurious logs are the only PSH artifact. |
| **Backend Services** | microservices-sme | GREEN | All 9 services healthy, VIP reachable on all ports. redis-cart recovered from preemption. |
| **Cloud Run** | cloud-run-sme | RECOVERING | Intermittent 500s from redis-cart timeout, NOT from PSH. VPC connector healthy. |
| **Cloud Deploy** | cloud-deploy-sme | NO IMPACT | Pipeline dormant since Dec 2022. No active deployments. |
| **Artifact Registry** | artifact-registry-sme | NO IMPACT | Repository online, 0 CVEs, SLSA L3 provenance, images intact. |
| **Observability** | cloud-monitoring-sme | MONITORING GAPS | 11 alert policies enabled but: no Redis alerting, no gRPC error rate alerting, uptime threshold at 50% (should be 95%), single notification channel (email SPOF). p99 latency hit 6503ms during redis-cart burst. |

---

## Section 2: Dependency Map

### Architecture (Verified Live)

```
                         TRAFFIC PATHS

  PATH A (Cloud Run — us-west1):                    PATH B (GKE Direct — us-central1):
  ================================                  ==================================
  Internet                                          Internet
    |                                                 |
    v                                                 v
  Cloud Run Frontend (us-west1)                     External LB 34.46.255.20:80
  frontend-alt-{dev,stage,prod}                       |
    |                                                 v
    v                                              GKE Frontend (us-central1)
  VPC Connector west1-default                      online-boutique-demo/frontend
  (e2-micro, 2-10 instances)                          |
    |                                                 |
    | CROSS-REGION (us-west1 → us-central1)           | IN-CLUSTER
    |                                                 |
    v                                                 v
  =====================================================
  Internal VIP 10.23.0.10 (gke-vip-subnet, us-central1)
  ILB with 9 forwarding rules (allowGlobalAccess=true)
  =====================================================
    |
    v
  GKE Autopilot: online-boutique-764d49 (us-central1, 4 nodes)
  Namespace: online-boutique-demo

  ┌──────────────────┬──────────────────┬──────────────────┐
  │ checkoutservice   │ cartservice      │ productcatalog   │
  │ :5050             │ :7070            │ :3550            │
  ├──────────────────┼──────────────────┼──────────────────┤
  │ paymentservice    │ shippingservice  │ currencyservice  │
  │ :50052            │ :50051           │ :7000            │
  ├──────────────────┼──────────────────┼──────────────────┤
  │ emailservice      │ recommendservice │ adservice        │
  │ :5000             │ :8080            │ :9555            │
  └──────────────────┴──────────────────┴──────────────────┘
                          |
                     redis-cart:6379
                  (in-cluster, Autopilot-managed)
```

### Critical Dependencies & SPOFs

| # | Component | Type | Blast Radius if Failed | Current Status |
|---|-----------|------|----------------------|----------------|
| 1 | **VPC Connector west1-default** | SPOF | ALL Cloud Run frontends (dev/stage/prod) lose backend access | READY |
| 2 | **VIP 10.23.0.10** | SPOF | ALL 9 backend services unreachable from both paths | HEALTHY (9 ILB rules confirmed) |
| 3 | **Cross-region link (west1→central1)** | SPOF | PATH A total failure (PATH B unaffected) | FUNCTIONAL |
| 4 | **GKE cluster online-boutique-764d49** | SPOF | ALL backend services down | RUNNING (4/4 nodes) |
| 5 | **redis-cart** | SPOF | Cart + checkout flow broken | RECOVERED |
| 6 | **Default Compute SA** | Shared identity | Compromise = all workloads compromised | ACTIVE, not compromised |

### Service Account Dependencies

| Service Account | Used By | Roles | Risk |
|----------------|---------|-------|------|
| 258519306384-compute@developer.gserviceaccount.com | ALL Cloud Run services, ALL GKE workloads, Cloud Deploy targets | roles/editor | CRITICAL: No isolation (CCR-002) |
| scion-platform-team@deploy-demo-test.iam.gserviceaccount.com | Platform operations | roles/editor, roles/viewer | HIGH: Can disable monitoring |
| scion-autobot-engineer@deploy-demo-test.iam.gserviceaccount.com | Automation | roles/editor + projectIamAdmin + SA admin + WIF admin + run.admin | CRITICAL: Full project takeover capability |

---

## Section 3: Structured Mitigation Plan

### Phase 1: Immediate Actions (NOW — Completed)

| # | Action | Status | Finding |
|---|--------|--------|---------|
| 1 | Fetch PSH incident details | DONE | RESOLVED VPC/NGFW spurious logging incident |
| 2 | Validate PATH A (Cloud Run) | DONE | HTTP 200 in 0.76s |
| 3 | Validate PATH B (GKE) | DONE | HTTP 200 in 0.04s |
| 4 | Verify IAM policy integrity | DONE | Etag unchanged: BwZTTqxdPng= |
| 5 | Verify no user-managed SA keys | DONE | Only SYSTEM_MANAGED keys |
| 6 | Verify VPC connector state | DONE | READY |
| 7 | Verify VIP forwarding rules | DONE | 9 ILB rules confirmed |
| 8 | Check audit logs for unauthorized changes | DONE | No SetIamPolicy changes, only GKE actAs operations |
| 9 | Verify firewall rule baseline | DONE | 27 rules present, `allow-ilb-permissive` NOT in current list (verify with vpc-networking-sme) |

### Phase 2: Short-Term (Next 24 Hours)

| # | Action | Owner | Priority | Rationale |
|---|--------|-------|----------|-----------|
| 1 | Add Redis connectivity failure alert | cloud-monitoring-sme | P1 | Root cascade signal (RedisConnectionException) has NO alert — this burst was invisible to alerting |
| 2 | Tighten uptime check threshold from 50% to 95% | cloud-monitoring-sme | P1 | 90% degradation did NOT trigger the current 50% threshold |
| 3 | Add backup notification channel (Slack/PagerDuty) | cloud-monitoring-sme | P1 | Single email channel is a delivery SPOF |
| 4 | Deploy PodDisruptionBudgets on critical services | microservices-sme | P1 | Prevent simultaneous preemption — redis-cart replicas=1 is root fragility |
| 5 | Set min-instances=2 on frontend-alt-prod | cloud-run-sme | P1 | Prevent cold-start delays during recovery scenarios |
| 6 | Confirm allow-ilb-permissive removal status | vpc-networking-sme | P1 | Live data shows it's not in firewall rules — verify CCR-001 status |
| 7 | Review spurious firewall logs from PSH window | cloud-monitoring-sme | P2 | Determine if spurious logs polluted dashboards |
| 8 | Add graceful cart degradation to frontend | cloud-run-sme | P2 | Render page without cart instead of returning 500 |
| 9 | Consider Redis HA or Memorystore migration | microservices-sme | P2 | Single-replica Redis with no persistence guarantees is a recurring risk |

### Phase 3: Medium-Term Hardening (1-2 Weeks)

| # | Action | Owner | Priority | CCR |
|---|--------|-------|----------|-----|
| 1 | Create dedicated SAs per workload | iam-sme | P0 | CCR-002 |
| 2 | Migrate Cloud Run to dedicated SA | cloud-run-sme + iam-sme | P0 | CCR-002 |
| 3 | Scale P1 backend services to replicas >=2 | microservices-sme | P1 | — |
| 4 | Deploy HPAs on checkout/payment/cart/productcatalog | microservices-sme | P1 | — |
| 5 | Scope down scion-autobot-engineer SA | iam-sme | P1 | CCR-002 |
| 6 | Enable VPC Flow Logs on gke-vip-subnet | vpc-networking-sme | P2 | CCR-013 |
| 7 | Enable Cloud Trace on all services | cloud-monitoring-sme | P2 | CCR-011 |
| 8 | Upgrade VPC connector from e2-micro to e2-standard | vpc-networking-sme | P2 | — |
| 9 | Validate Cloud Deploy pipeline end-to-end | cloud-deploy-sme | P3 | — |
| 10 | Rebuild container images on current Alpine base | artifact-registry-sme | P3 | — |

---

## Section 4: CCR Status Update

| Risk | Previous Status | Current Finding | Updated Status |
|------|----------------|-----------------|----------------|
| **CCR-001**: allow-ilb-permissive | CRITICAL / Open | Rule NOT in current firewall list (27 rules checked). **Needs confirmation from vpc-networking-sme.** | POTENTIALLY RESOLVED |
| **CCR-002**: Single default SA | CRITICAL / Open | Confirmed: all workloads still share default compute SA with roles/editor. No progress. | CRITICAL / Open |
| **CCR-003**: Unknown VIP backing | HIGH / Open | **RESOLVED.** VIP 10.23.0.10 has 9 ILB forwarding rules, one per backend service. Created 2026-06-04. | RESOLVED |

---

## Section 5: Key Positive Findings

1. **CCR-003 is RESOLVED** — VIP 10.23.0.10 now has 9 fully-configured ILB forwarding rules with allowGlobalAccess=true
2. **CCR-001 may be RESOLVED** — `allow-ilb-permissive` not found in current firewall rules
3. **IAM policy is clean** — No unauthorized changes detected since Battle 3
4. **Supply chain is clean** — Deployed images have 0 CVEs, SLSA L3 provenance, BinAuthz attestation
5. **Both traffic paths are operational** — PATH A and PATH B returning HTTP 200

---

## Appendix: PSH Incident Details

- **Event ID:** LYGWHYJ
- **Product:** Virtual Private Cloud (VPC)
- **Category:** CONFIRMED_INCIDENT
- **State:** RESOLVED
- **Duration:** 2026-06-07T13:55Z — 2026-06-08T08:04Z (~18 hours)
- **Regions:** 175 (global), including us-west1 and us-central1
- **Description:** Cloud NGFW generated firewall events and exported logs for firewall rules that did not have logging enabled
- **Root Cause:** Update to GCP networking software
- **Resolution:** GCP engineering deployed a fix

---

*Report compiled from parallel investigations by: iam-sme, vpc-networking-sme, microservices-sme, cloud-run-sme, cloud-deploy-sme, artifact-registry-sme, sre-expert. Live diagnostics executed by SRE Team Lead.*
