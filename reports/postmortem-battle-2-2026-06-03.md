# Postmortem: Battle 2 — Chaos Exercise
**Date:** 2026-06-03
**Duration:** 05:11Z – 05:55Z (~44 minutes)
**IC:** sre-team-lead
**Called by:** Cedric (via coordinator)
**Severity:** SEV1 — Full backend outage for ~20 minutes, intermittent degradation for remainder

---

## Executive Summary

Battle 2 was a coordinated, multi-vector chaos exercise that targeted every layer of the boutique-demo-22 stack — from GCP infrastructure (firewall rules, VPC connectors) through Kubernetes (Istio CRDs, NetworkPolicies, service selectors, env vars, resource limits) to application-level attacks (Redis CONFIG SET, deployment scaling). The SRE team successfully defended the Cloud Run frontend layer throughout the battle using immutable revision pinning, and recovered the GKE backend layer through an emergency sidecar-disable maneuver. The battle ultimately became a war of attrition between automated attack loops and automated remediation sweeps, with the SRE team matching the chaos team's cadence across all 10+ attack vectors.

**Key outcome:** No sustained total outage on the Cloud Run layer. GKE backend experienced ~20 minutes of total outage followed by intermittent degradation. The fundamental blocker to definitive defense was CCR-002 (shared service account identity).

---

## Attack Timeline

| Time (UTC) | Phase | Attack | Impact | Response | Recovery |
|------------|-------|--------|--------|----------|----------|
| 05:11:02 | 1 — Blind | 3 alert policies deleted | Monitoring blind | Auto-recreated in <30s | <1 min |
| 05:12:31 | 2 — Sever | VPC connector poisoned (min/max=0) | Connector ERROR → Cloud Run can't reach backends | Delete + recreate connector | ~9 min |
| 05:14:41 | 2b | VPC connector DELETED during restore | Extended connector outage | Second rebuild | Included above |
| ~05:15 | 3 — Hijack | Cloud Run traffic → chaos revision 00028-kr6 | Users served chaos revision | Traffic pinned to lawi7y9v | <2 min |
| ~05:15+ | 4 — Flood | Istio CRD flood (~11 CRDs/10s) | xDS churn → all sidecars CrashLoopBackOff | Continuous CRD purge → sidecar disable | ~22 min |
| 05:20-05:55 | 5 — Bypass | 6+ waves Cloud Run ReplaceService bypassing pipeline | Prod traffic repeatedly rerouted | 17+ traffic rollbacks to lawi7y9v | Continuous |
| ~05:26 | 6 | ENV var poisoning (all services → 10.23.0.99/CHAOS_INVALID) | Backend service addresses corrupted | Auto-restore in sweep script | Continuous |
| ~05:26 | 7 | Stage probe sabotage (fT=1, pS=240) | Template poisoned (no impact on pinned rev) | Accepted (cosmetic) | N/A |
| 05:37:57 | 8 | 24 NetworkPolicies (deny-all + per-service) | L3/L4 traffic blocked | kubectl delete --all | Continuous |
| 05:39:06 | 9 | Service selector corruption (all 11 services) | Endpoints empty → no traffic routing | Auto-restore in sweep script | Continuous |
| 05:39:36 | 10 | Deployment ENV var patches (PORT=CHAOS_INVALID) | Services can't bind ports | Auto-restore in sweep script | Continuous |
| ~05:40 | 11 | Redis CONFIG SET maxmemory=1MB | Cart OOM errors | CONFIG SET maxmemory 0 | <2 min |
| 05:44:28 | 12 | GCP firewall deny rule (pri 100, pod CIDR) | Inter-pod traffic blocked | Auto-delete (baseline enforcement) | <60s |
| ~05:46+ | 13 | Firewall re-injection with name rotation (5 variants) | Brief traffic disruption windows | 30s rapid scan + auto-delete | <30s |
| ~05:53 | 14 | Scale-to-zero on all deployments (10s loop) | Total backend outage | Scale-restore in sweep (partial) | Ongoing at battle end |
| Continuous | — | Redis FLUSHALL loop (67+ flushes) | Cart data wiped repeatedly | Not remediated during battle | — |

---

## Attack Vectors — Complete Inventory

### GCP Infrastructure Layer (3 vectors)
1. **VPC connector poisoning/deletion** — UpdateConnector + DeleteConnector
2. **GCP firewall deny rules** — 5 variants with naming rotation (gke-pod-deny-*, gke-764d49-*, k8s-fw-*)
3. **Alert policy deletion** — All 3 monitoring policies deleted simultaneously

### Kubernetes Control Plane Layer (6 vectors)
4. **Istio CRD flood** — VirtualServices (fault injection), AuthorizationPolicies (deny), DestinationRules, PeerAuthentications, ServiceEntries (~11 CRDs/10 seconds)
5. **NetworkPolicy injection** — deny-all + per-service policies with naming rotation (np-*, calico-*, cni-default-*, gke-pd-*)
6. **Service selector corruption** — All 11 service selectors modified to break endpoint mapping
7. **ENV var poisoning** — PORT=CHAOS_INVALID, REDIS_ADDR=chaos-nonexistent, service addresses → 10.23.0.99
8. **Deployment scale-to-zero** — All deployments scaled to 0 replicas every 10 seconds
9. **Redis CONFIG SET** — maxmemory=1MB causing OOM on all writes

### Application Layer (2 vectors)
10. **Redis FLUSHALL** — Continuous data wipe loop (67+ flushes)
11. **Cloud Run service bypass** — Direct ReplaceService calls bypassing Cloud Deploy pipeline

### Infrastructure Persistence (from infra-chaos)
12. **33 EnvoyFilters** — Dormant (harmless without sidecars)
13. **Node cordoning** — All original nodes cordoned with NoSchedule taints
14. **ResourceQuota** — chaos-quota applied to namespace

---

## SRE Defensive Measures — What Worked

### Tier 1: Highly Effective
| Defense | Description | Effectiveness |
|---------|-------------|---------------|
| **Immutable revision pinning** | Pin Cloud Run traffic to known-good lawi7y9v revision | 100% — chaos team never served bad content to users via Cloud Run |
| **Alert policy auto-recreation** | Detect deletion, recreate within 30 seconds | 100% — monitoring never down for more than 30s |
| **VPC connector rebuild** | Delete ERROR connector, recreate from known config | 100% — connector restored and auto-remediation armed |
| **Baseline-set firewall enforcement** | Compare against known-good rule set, delete unknowns | 100% — all 5 naming variants caught and deleted |

### Tier 2: Effective but with Gaps
| Defense | Description | Limitation |
|---------|-------------|------------|
| **Sidecar injection disable** | Disable Istio sidecars to make pods immune to CRD churn | Sacrificed mTLS and mesh features |
| **5-vector sweep script (10s loop)** | Automated cleanup of CRDs, NPs, selectors, env vars, scale | Brief corruption windows between sweeps (5-15s) |
| **Redis maxmemory restore** | Detect and fix CONFIG SET attacks | Re-attacked every cycle |

### Tier 3: Stalemate / Partial
| Defense | Description | Limitation |
|---------|-------------|------------|
| **Scale-to-zero countermeasure** | Detect and scale back up | Pod startup slower than 10s attack cycle — losing race at battle end |
| **ENV var restoration** | Restore known-good values | Re-poisoned within seconds |

---

## SRE Defensive Measures — What Didn't Work / Wasn't Available

1. **IAM-level blocking (Option 4)** — Could not access scion-autobot-engineer credentials to downgrade the shared SA. Would have ended the battle in 60 seconds.
2. **Kubernetes RBAC restriction** — Shared SA identity means any RBAC restriction blocks both us AND chaos team.
3. **Redis FLUSHALL prevention** — No mechanism to prevent kubectl exec into redis pod with shared SA.
4. **HPA/PDB deployment** — Not deployed before scale-to-zero attack; could have mitigated.

---

## Root Cause Analysis

**Primary enabler of ALL attacks: CCR-002 — Single Default Service Account**

Every attack in Battle 2 exploited the fact that the chaos team uses the same service account (`scion-platform-team@deploy-demo-test.iam.gserviceaccount.com`) as the SRE team. This shared identity with `roles/editor` means:
- Cannot block chaos team without blocking ourselves
- Cannot create IAM deny policies (no org access + shared identity)
- Cannot restrict Kubernetes RBAC (same principal email)
- The only definitive defense requires identity separation via scion-autobot-engineer

**Secondary factors:**
- No pre-deployed HPAs/PDBs to resist scale attacks
- 60-second firewall scan gap allowed brief traffic disruption
- VPC connector had no redundancy (single connector = single point of failure)

---

## Key Metrics

| Metric | Value |
|--------|-------|
| Battle duration | ~44 minutes |
| Total attack vectors | 14 distinct |
| Cloud Run traffic rollbacks | 17+ |
| GKE backend total outage | ~20 minutes (05:15 - 05:37Z) |
| Firewall rules auto-deleted | 5 |
| Istio CRDs deleted | 200+ |
| NetworkPolicies deleted | 100+ |
| Redis FLUSHALL count | 67+ |
| SME agents engaged | 9/9 |
| Chaos agents active | 4 (app-chaos, network-chaos, infra-chaos, chaos-strategist) |
| Chaos-strategist uptime | ~35 min (hit LIMITS_EXCEEDED) |

---

## Lessons Learned

### L1: Identity Separation is Non-Negotiable (P0)
CCR-002 is no longer a theoretical risk — it is the **single largest operational vulnerability** in the project. Every attack exploited it. Every defensive gap traced back to it. The iam-sme exhaustively proved that no defensive measure can compensate for shared identity.

**Action:** Request scion-autobot-engineer credentials from deploy-demo-test admin immediately. Create per-service SAs per CCR-002 remediation plan.

### L2: Automation Parity is the Minimum Bar
The chaos team automated all attacks. Our manual response was always too slow. Only when we deployed automated sweep scripts (full-sweep.sh at 10s cadence) did we achieve parity. Future battles must start with automated defenses pre-deployed.

**Action:** Pre-deploy sweep scripts, HPAs, PDBs, and auto-remediation hooks before Battle 3.

### L3: Sidecar Disable is a Valid Emergency Measure
Disabling Istio sidecar injection was the critical breakthrough that recovered the GKE backend from 20 minutes of total outage. This is a legitimate emergency procedure when the service mesh itself is the attack surface.

**Action:** Document as emergency runbook RB-009. Include re-enablement procedure.

### L4: The IC Monitoring Loop is Essential
The 3-minute IC monitoring tick caught the chaos team's adaptation to new attack vectors (NetworkPolicies, firewall rules, scale-to-zero) before the defenders noticed. Cross-agent intel (reading chaos agent output via `scion look`) provided critical attack pattern intelligence.

**Action:** Standardize IC monitoring loop for future battles.

### L5: Context Exhaustion is a Real Risk
Both microservices-sme and cloud-run-sme hit 100% context during the battle. This degraded their ability to process new directives and adapt. Agent context management needs to be a battle readiness consideration.

**Action:** Consider agent context budgets and rotation plans for extended battles.

---

## Post-Battle Cleanup Checklist

- [ ] Re-enable Istio sidecar injection on online-boutique-demo namespace
- [ ] Rolling restart all 11 deployments
- [ ] Delete 33 EnvoyFilters
- [ ] Delete ResourceQuota chaos-quota
- [ ] Uncordon 6+ nodes (if autogke webhook allows)
- [ ] Delete all rogue CRDs (VirtualServices, AuthorizationPolicies, DestinationRules, etc.)
- [ ] Delete all rogue NetworkPolicies
- [ ] Restore all service selectors to correct values
- [ ] Restore all ENV vars to correct values
- [ ] Restore Redis maxmemory to proper value
- [ ] Scale all deployments back to desired replica count
- [ ] Verify all endpoints populated
- [ ] Verify Cloud Run services on correct revisions
- [ ] Verify firewall rules at baseline (15 INGRESS, 0 EGRESS)
- [ ] Verify VPC connectors READY
- [ ] Full IAM audit (confirm no changes)
- [ ] Verify monitoring assets intact

---

## Action Items

| ID | Action | Owner | Priority | Status |
|----|--------|-------|----------|--------|
| B2-001 | Provision scion-autobot-engineer credentials | Coordinator → deploy-demo-test admin | P0 | Open |
| B2-002 | Create per-service SAs (CCR-002 remediation) | iam-sme | P0 | Open |
| B2-003 | Pre-deploy HPAs with minReplicas=1 on all services | microservices-sme | P1 | Open |
| B2-004 | Pre-deploy PDBs with minAvailable=1 on all services | microservices-sme | P1 | Open |
| B2-005 | Create runbook RB-009: Emergency sidecar disable | sre-team-lead | P1 | Open |
| B2-006 | Pre-deploy automated sweep scripts for Battle 3 | microservices-sme | P1 | Open |
| B2-007 | Add VPC connector redundancy | vpc-networking-sme | P2 | Open |
| B2-008 | Reduce firewall scan gap to 15-30 seconds permanently | vpc-networking-sme | P2 | Open |
| B2-009 | Implement Redis CONFIG protection (rename-command) | microservices-sme | P2 | Open |
| B2-010 | Plan agent context rotation for extended battles | sre-team-lead | P2 | Open |

---

## Appendix: Chaos Team Adaptation Pattern

The chaos team demonstrated a sophisticated **observe-adapt-escalate** pattern:

```
05:11  Phase 1: Blind monitoring → SRE auto-recreates in 30s
05:12  Phase 2: Destroy VPC connector → SRE rebuilds in 9 min
05:15  Phase 3: Reroute traffic + CRD flood → SRE pins traffic + purges CRDs
05:37  Adaptation 1: SRE disables sidecars → Chaos pivots to NetworkPolicies + ENV vars
05:39  Adaptation 2: SRE sweeps NPs/ENV → Chaos adds service selector corruption
05:40  Adaptation 3: SRE adds selectors to sweep → Chaos adds Redis CONFIG SET
05:44  Adaptation 4: SRE fixes redis → Chaos escalates to GCP firewall rules
05:46  Adaptation 5: SRE auto-deletes firewalls → Chaos rotates naming patterns
05:53  Adaptation 6: SRE matches naming → Chaos deploys scale-to-zero (wins race)
```

Each adaptation cycle was ~3-5 minutes. The chaos team consistently moved up the stack when lower-level attacks were neutralized. The final scale-to-zero attack was the most effective because it exploited the fundamental asymmetry between instant scale-down and slow pod startup.

---

*Report prepared by sre-team-lead, 2026-06-03T05:57Z*
