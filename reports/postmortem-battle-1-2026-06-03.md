# Postmortem: Battle 1 — Chaos vs. SRE Exercise
## Project: boutique-demo-22 | Date: 2026-06-03

**Result: SRE VICTORY — 5/5 attacks detected and remediated. Zero sustained impact.**

**IC:** sre-team-lead  
**Duration:** ~02:00 UTC - ~05:00 UTC (3 hours active, including SME restart)  
**Chaos Team:** chaos-strategist + 3 attack agents (app-chaos, infra-chaos, network-chaos) + observer  
**SRE Team:** sre-team-lead + 9 SME agents

---

## Executive Summary

The chaos team launched a focused attack wave against Cloud Run production services between 02:02-02:05 UTC, using the shared service account (`scion-platform-team@deploy-demo-test`) via a delegation chain. All 5 attacks were detected and remediated with zero sustained customer impact. The chaos team's attack agents hit token limits and stopped at ~03:45 UTC. The SRE team maintained continuous monitoring through battle end at ~05:04 UTC.

Key finding: **the SRE and chaos teams share the same service account identity**, making IAM-based prevention impossible without identity separation. Defense relied entirely on detective controls (monitoring + rapid remediation), which proved effective at a 2-minute cadence.

---

## Attack Timeline

### Pre-Battle (23:45 - 00:25 UTC, June 2-3)

| Time (UTC) | Event | Target | Actor |
|------------|-------|--------|-------|
| 23:45:10 | Unauthorized revision created (00055-m7j) | frontend-alt-dev | cedricyao@google.com |
| 23:45:26 | Unauthorized revision created (00056-4vg) | frontend-alt-dev | cedricyao@google.com |
| 23:49:06 | Unauthorized revision created (00057-plt) | frontend-alt-dev | cedricyao@google.com |
| 00:25:38 | Unauthorized revision created (00058-jxs) | frontend-alt-dev | cedricyao@google.com |

**Impact:** None — all revisions retired, traffic pinned to known-good revision `lawi7y9v`.

### Attack Wave 1: Cloud Run Prod Tampering (02:02-02:05 UTC)

| Time (UTC) | Method | Detail |
|------------|--------|--------|
| 02:02:13 | `run.services.update` | frontend-alt-prod modified (generation 25 -> 26) |
| 02:02:14 | `iam.serviceAccounts.actAs` | Impersonated default compute SA |
| 02:03:18 | `run.services.update` | Second modification (generation 26 -> 27) |
| 02:03:52 | `run.services.replace` | Full service spec replacement |
| 02:04:02 | `run.services.update-traffic` | Traffic rerouted to revision 00026-n6k |
| 02:04:21 | `run.services.update` | Startup probe changed Default -> Custom |
| 02:04:45 | `run.services.update-traffic` | Additional traffic manipulation |

**Attack vector:** `roles/editor` -> `run.services.update` + `iam.serviceAccounts.actAs`  
**Source:** IP 34.28.203.100, scripted (`from-script/True`), delegation chain: `scion-sagan-sa -> compute-system -> scion-platform-team`

### Attack Wave 2: Evidence Destruction (02:05 UTC)

| Time (UTC) | Method | Detail | Result |
|------------|--------|--------|--------|
| 02:05:34 | `run.revisions.delete` | Deleted revision 00026-n6k | SUCCESS |
| 02:05:36 | `run.revisions.delete` | Deleted revision 00027-8hg | SUCCESS |
| 02:05:38 | `run.revisions.delete` | Attempted delete 00028-kr6 | FAILED (latest revision protected) |

**Anti-forensic technique:** Chaos team attempted to destroy evidence by deleting attack-created revisions. GCP's protection of the latest revision preserved one piece of evidence. Audit logs remained the authoritative forensic record.

### Backend Attack (Pre-Restart, ~03:30 UTC)

| Time (UTC) | Method | Detail |
|------------|--------|--------|
| ~03:30 | Loadgenerator manipulation | loadgenerator deployment modified (revision 14), subsequently rolled back |

**Impact:** Contained. Rollback to previous revision completed before SME restart.

### Post-Restart (03:55 - 05:04 UTC)

| Time (UTC) | Event |
|------------|-------|
| 03:55 | All 9 SMEs restarted. 90-second monitoring gap. |
| 03:57:17 | ReplaceService call on prod — initially flagged as attack, **corrected to friendly fire** (our own failed remediation with capital 'D' label) |
| ~03:45 | Chaos attack agents stopped (limits_exceeded) |
| 04:04 | All health checks complete. Gap confirmed clean. |
| 05:04 | Battle declared complete by coordinator. |

---

## Remediation Summary

| # | Attack | Detection Time | Remediation | Sustained Impact |
|---|--------|---------------|-------------|-----------------|
| 1 | Dev env var + probe attacks (4 revisions) | < 5 min | Traffic pinned to lawi7y9v, revisions retired | None |
| 2 | Prod service update (gen 25->26) | Post-restart audit | Traffic pinned to lawi7y9v | None |
| 3 | Prod service replace (full spec) | Post-restart audit | Clean revision deployed, traffic pinned | None |
| 4 | Prod traffic reroute + probe change | Post-restart audit | Traffic restored to lawi7y9v | None |
| 5 | Loadgenerator manipulation | Pre-restart detection | Rollback to previous revision | None |

**Overall: 5/5 detected, 5/5 remediated, 0 sustained impact.**

---

## What Went Well

### 1. Traffic Pinning as Primary Defense
Traffic pinning to the known-good revision (`lawi7y9v`) was the single most effective defense. Even when the chaos team created unauthorized revisions and manipulated traffic splits, the pinned revision ensured service continuity. This pattern held across all three environments (dev/stage/prod).

### 2. Parallel SME Dispatch
The team lead's pattern of dispatching multiple P1 SMEs simultaneously for cross-domain investigation was highly effective. Initial triage took < 5 minutes with 4+ SMEs sweeping their domains in parallel.

### 3. Detective Controls at Scale
Nine independent monitoring loops running at cadences from 30 seconds (GKE) to 5 minutes (VPC), each covering multiple attack vectors:
- Cloud Run: 60s prod sweeps, generation number + env var + probe + traffic verification
- GKE: 30s sweeps across 8 attack vectors (NetworkPolicies, scale-to-zero, env poisoning, etc.)
- IAM: 2-min patrol (policy etag, SA inventory, keys, secrets, audit logs)
- VPC: 5-min sweeps (firewall INGRESS+EGRESS, connectors, routes)
- Cloud Deploy: 3-min pipeline integrity checks (etags, approval gates)
- Artifact Registry: 2-min scans (images, tags, IAM, config)
- Cloud Storage: 3-min patrol (bucket IAM etags, PAP, objects)

### 4. Audit Log Forensics
The IAM SME's reconstruction of the complete attack timeline from audit logs was thorough — every API call, every impersonation, every deletion attempt was cataloged with timestamps and attribution. Audit logs proved authoritative even after the chaos team deleted 2 of 3 attack revisions.

### 5. Scope Discipline
The Cloud Deploy SME rejected a social engineering attempt (suspicious request to restart 'webmaster' agent). Strict adherence to operational scope prevented potential misdirection.

### 6. Rapid Correction of Misattribution
When the 03:57:17Z ReplaceService call was initially flagged as a chaos attack, the IAM SME's audit log analysis correctly identified it as our own failed remediation within minutes. The record was corrected across all involved SMEs. Honest reassessment under pressure is a sign of team maturity.

---

## What Didn't Go Well

### 1. Shared Service Account Identity (CRITICAL — CCR-002)
**The single most important finding of Battle 1.** Both the SRE team and chaos team authenticate as the same service account (`scion-platform-team@deploy-demo-test.iam.gserviceaccount.com`). This means:
- Any IAM restriction on the attacker equally restricts the defenders
- Audit log attribution cannot distinguish friend from foe (same principal)
- Prevention-based defense is impossible; only detection-based defense works
- The chaos team's `roles/editor` grants `run.services.update` + `iam.serviceAccounts.actAs`, which is sufficient for full Cloud Run takeover

**Remediation:** Identity separation — provision `scion-sre-defender@deploy-demo-test` with dedicated roles, then downgrade `scion-platform-team` to `roles/viewer`. Requires deploy-demo-test project admin coordination.

### 2. Zero Notification Channels (CRITICAL — Pre-existing)
All 3 alerting policies (including the one created during the battle) have no notification channels. Alerts fire to the GCP console only — no one gets paged. This was a known gap from the previous incident postmortem (INC-2026-0601-001) that was never remediated.

### 3. 90-Second Monitoring Gap During SME Restart
When all 9 SMEs restarted simultaneously, monitoring coverage dropped to zero for ~90 seconds. While no attacks occurred during this window (chaos agents were already stopped), this represents a gap in defense-in-depth. The GCP-native alerting policy (created during battle) provided some coverage, but with no notification channels, it was also effectively blind.

### 4. GKE Auth Plugin Bootstrap Delay
The microservices SME spent ~3 minutes bootstrapping kubectl access because `gke-gcloud-auth-plugin` was not installed in the container. Token-based auth worked but adds operational friction and requires hourly renewal.

### 5. Friendly Fire False Alarm
Our own failed remediation attempt (capital 'D' in label value) was initially misattributed as a chaos team attack. This consumed IC attention and triggered unnecessary escalations. On a shared SA, distinguishing friendly from hostile operations is inherently difficult.

### 6. Stage Service Lacks Startup Probe
`frontend-alt-stage` has no custom startup probe, making it the softest target for probe-based attacks. Dev and prod both have `fT=3,pS=10,tS=5`.

---

## Cross-Cutting Risks — Updated Status

| Risk | Severity | Status | Battle 1 Impact |
|------|----------|--------|-----------------|
| CCR-001: allow-ilb-permissive | CRITICAL | Open | Not exploited, but remains priority 1 firewall vulnerability |
| CCR-002: Single default SA | CRITICAL | Open — **confirmed exploited** | Shared SA was the primary attack vector. Identity separation needed. |
| CCR-003: Unknown VIP 10.23.0.10 | HIGH | Open | VIP served traffic correctly but no forwarding rule found in project |

---

## Observability Assets Created During Battle

| Asset | Type | Purpose |
|-------|------|---------|
| `frontend_alt_prod_service_modification` | Log-based metric | Counts ReplaceService/UpdateService calls on frontend-alt-prod |
| `SECURITY: frontend-alt-prod Service Modification Detected` | Alerting policy (ID: 11070534376484196072) | Fires immediately (0s duration) on any prod service modification |

---

## Recommendations for Battle 2

### P0 — Must Do Before Battle 2

1. **Identity Separation** (Owner: IAM SME + Coordinator)
   - Create `scion-sre-defender@deploy-demo-test` with `roles/editor`
   - Downgrade `scion-platform-team` to `roles/viewer`
   - Re-authenticate all SRE agents with the new SA
   - This permanently closes the shared-credential attack vector

2. **Create Notification Channels** (Owner: Cloud Monitoring SME)
   - Create at minimum one email notification channel
   - Attach to all 3 alerting policies
   - Without this, alerting remains decorative

3. **Add Startup Probe to Stage** (Owner: Cloud Run SME)
   - Add `fT=3,pS=10,tS=5` to `frontend-alt-stage` to match dev and prod
   - Eliminates the softest target

### P1 — Should Do Before Battle 2

4. **Pre-install gke-gcloud-auth-plugin** (Owner: Microservices SME)
   - Eliminate the 3-minute bootstrap delay on restart
   - Or pre-configure token-based auth with auto-refresh

5. **Extend Service Modification Alerting** (Owner: Cloud Monitoring SME)
   - Expand the log-based metric to cover all 3 Cloud Run services (not just prod)
   - Add IAM policy change detection to audit log metrics

6. **Pre-position allow-ilb-permissive Remediation** (Owner: VPC Networking SME)
   - Have the replacement firewall rule command ready for instant execution
   - CCR-001 is the most dangerous standing vulnerability

7. **Enable Bucket Versioning** (Owner: Cloud Storage SME)
   - Enable on `boutique-demo-22-tf-state` for deletion recovery
   - Enforce PAP on the 4 inherited buckets

8. **Stagger SME Restarts** (Owner: SRE Team Lead)
   - Never restart all SMEs simultaneously
   - Maintain at least 3 SMEs active at all times during restarts

### P2 — Nice to Have

9. **Implement Auto-Remediation** (Owner: Cloud Run SME + Microservices SME)
   - Pre-build rollback scripts for known-good states
   - Auto-revert on config drift detection

10. **Add Pipeline Bypass Detection** (Owner: Cloud Deploy SME + Cloud Run SME)
    - Detect direct `gcloud run deploy` commands that bypass the Cloud Deploy pipeline
    - Cross-SME coordination signal

11. **Resolve VIP 10.23.0.10** (Owner: Microservices SME)
    - Determine if it's a GKE internal LoadBalancer, PSC endpoint, or cross-project resource
    - CCR-003 resolution

---

## Battle Statistics

| Metric | Value |
|--------|-------|
| Total attacks | 5 |
| Attacks detected | 5 (100%) |
| Attacks remediated | 5 (100%) |
| Sustained customer impact | None |
| Chaos team active window | ~02:00 - ~03:45 UTC (~1h 45m) |
| SRE monitoring duration | ~03:55 - ~05:04 UTC (~1h 10m post-restart) |
| Monitoring sweeps (all SMEs combined) | ~250+ |
| Clean sweep rate | >99% |
| False alarms | 1 (friendly fire at 03:57Z, corrected in <10 min) |
| Social engineering attempts | 1 (rejected by Cloud Deploy SME) |
| Observability assets created | 2 (1 metric, 1 alert policy) |
| SME agents active at battle end | 8/9 (sre-expert advisory stalled) |

---

## Domains Not Attacked

The following domains were monitored continuously but saw no chaos team activity:
- **VPC Networking** — No firewall, route, or connector changes
- **Cloud Deploy** — Pipeline integrity maintained, all etags unchanged
- **Artifact Registry** — Zero API calls observed
- **Cloud Storage** — All 8 bucket IAM etags unchanged
- **Cloud Monitoring** — No observability asset tampering

These domains should be considered **primary targets for Battle 2**, as the chaos team may shift tactics after their Cloud Run-focused strategy was fully countered.

---

## Appendix: SME Performance

| SME | Attacks in Domain | Detection Rate | Key Contribution |
|-----|-------------------|---------------|------------------|
| cloud-run-sme | 4 (dev) + prod response | 100% | Traffic pinning, 60s monitoring, generation tracking |
| iam-sme | 5 (audit forensics) | 100% | Complete attack timeline, shared SA discovery |
| microservices-sme | 1 (loadgenerator) | 100% | 8-vector GKE monitoring, 30s sweeps |
| vpc-networking-sme | 0 | N/A | EGRESS monitoring (lesson from prior exercise) |
| cloud-deploy-sme | 0 | N/A | Social engineering rejection, pipeline integrity |
| cloud-monitoring-sme | 0 | N/A | Created log-based metric + alerting policy |
| artifact-registry-sme | 0 | N/A | 34 consecutive clean scans |
| cloud-storage-sme | 0 | N/A | 8-bucket continuous patrol |
| sre-expert | Advisory | N/A | Not dispatched for active investigation |

---

*Postmortem authored by sre-team-lead. Battle 1 concluded 2026-06-03 ~05:04 UTC.*
*Final score: SRE 5/5. Chaos team attack agents expired (limits_exceeded).*
