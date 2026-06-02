# Chaos vs. SRE Exercise Debrief
## 2026-06-02 | boutique-demo-22

**Exercise window:** 23:26Z – 23:42Z (16 minutes)
**SRE Team:** sre-team-lead (IC) + 9 SME agents
**Adversary:** Chaos team using cedricyao@google.com credentials

---

## What We Detected

### Phase 1 — Cloud Run Poisoning (23:26:01Z) ✅ DETECTED in 2m34s
- `PRODUCT_CATALOG_SERVICE_ADDR` poisoned to `10.99.99.99:3550` on frontend-alt-dev
- Startup probe sabotaged: `failureThreshold=1, periodSeconds=240, timeoutSeconds=240`
- Unauthorized revision `frontend-alt-dev-00052-mbg` created
- Labels injected: `revision-test=foo, environment=dev`
- **Detected by:** cloud-run-sme (first SME to report attack)

### Phase 1b — Additional Poisoned Revisions (23:36:38Z) ✅ DETECTED in 2m23s
- Two more revisions created (00053-7d2, 00054-wsw) — rapid-fire, 5 seconds apart
- Env var poison self-reverted by attacker (covering tracks)
- Startup probe sabotage persisted
- **Detected by:** cloud-run-sme during Phase 2 sweep

### Phase 2 — IAM Privilege Strip (23:37:46Z) ✅ DETECTED in 1m17s
- `roles/run.developer` removed from default compute SA
- Effect: Cloud Deploy pipelines to Cloud Run broken
- Combined with Phase 1 = denial-of-remediation
- **Detected by:** cloud-monitoring-sme via audit logs

### Phase 3 — Firewall Egress Block (23:38:51Z) ❌ MISSED
- Firewall rule `chaos-block-connector` created
- Direction: EGRESS, Action: DENY ALL, Destination: 10.23.0.0/24, Priority: 0
- Effect: ALL VPC traffic to backend subnet severed — total frontend→backend disconnect
- Rule lived only ~2m15s (deleted at 23:41:06Z during attacker cleanup)
- **Missed by:** vpc-networking-sme and cloud-monitoring-sme

---

## Why We Missed the Firewall Rule

### Root Cause 1: Timing Race
The Phase 2 triage sweep executed at ~23:38:00-23:38:30Z. The firewall rule was created at 23:38:51Z — **seconds after our sweep completed.** By the time vpc-networking-sme reported "no changes found," the rule had just appeared.

### Root Cause 2: Egress Blind Spot
Our triage runbook and mental model focused on INGRESS rules (matching INC-2026-0601-001 patterns). We listed all rules but did not specifically filter for or highlight EGRESS DENY rules as a distinct threat. An egress deny targeting the backend subnet is a novel vector not covered in our runbooks.

### Root Cause 3: No Continuous Monitoring
We used point-in-time snapshots (list + audit log queries) rather than continuous monitoring. A short-lived rule (~2m15s) can be created and deleted between sweeps without detection.

### Root Cause 4: Audit Log Ingestion Delay
Cloud Audit Logs have a small ingestion delay. The Phase 2 audit log query may have been evaluated before the firewall create event was searchable.

### Root Cause 5: No Re-Sweep
After the initial Phase 2 sweep, we did not schedule a follow-up sweep to catch late-arriving events. A T+2 minute re-sweep would have caught the rule.

---

## What Worked Well

1. **Fast initial detection:** Phase 1 attack found in 2m34s, Phase 2 in 1m17s
2. **Parallel SME dispatch:** 4 SMEs investigating simultaneously gave broad coverage
3. **Domain isolation:** Clean reports from microservices-sme and vpc-networking-sme quickly narrowed the search space
4. **Audit log correlation:** cloud-monitoring-sme confirmed single attacker identity and attack timeline
5. **Pattern recognition:** Recognized the 1-2 punch (poison + deny remediation) as a coordinated strategy
6. **No false positives:** We correctly identified Autopilot node scheduling as routine, not an attack

## What Didn't Work

1. **Missed the firewall rule entirely** — our highest-severity detection gap
2. **Remediation script had a bad flag** (`--clear-startup-probe` doesn't exist — correct syntax: `--startup-probe=""`)
3. **No continuous audit log tailing** — point-in-time snapshots miss ephemeral changes
4. **Egress rules not in triage checklist** — all runbooks focused on ingress patterns
5. **No scheduled re-sweep** — single sweep per phase left a timing gap
6. **iam-sme refused activation** — held to Cedric's standby directive, reducing IAM coverage (cloud-monitoring-sme covered the gap)

---

## Runbook Changes Required

### Immediate Updates

| Runbook | Change | Priority |
|---------|--------|----------|
| All triage runbooks | Add explicit EGRESS DENY check: `gcloud compute firewall-rules list --filter='direction=EGRESS' --format=json` | P0 |
| networkpolicy-injection.md | Add firewall egress deny as an equivalent network-layer attack pattern | P1 |
| All triage runbooks | Add T+2 minute re-sweep step after initial triage | P1 |
| exercise-remediation script | Fix `--clear-startup-probe` → `--startup-probe=""` | P0 |
| Triage playbook | Add audit log filter excluding system lease heartbeats to prevent crowding | P1 |

### New Runbook Needed

**RB-005: Firewall Egress Deny Attack**
- Symptoms: Frontend→backend timeout with all pods healthy, no NetworkPolicies
- Detection: `gcloud compute firewall-rules list --filter='direction=EGRESS AND action=DENY'`
- Key differentiator: Similar symptoms to NetworkPolicy injection but at VPC level, not K8s level
- Affects ALL services sharing the VPC, not just one namespace

### Infrastructure Changes Needed

| Change | Why | Priority |
|--------|-----|----------|
| Enable firewall rule create/delete/update audit log alert | Real-time detection, not polling | P0 |
| Enable VPC Flow Logs on gke-vip-subnet and connector subnet | Can't debug what we can't see | P1 |
| Enable firewall rule logging on all rules | Packet-level visibility during attacks | P1 |
| Org Policy: restrict priority-0 firewall rules | Prevent highest-priority override attacks | P2 |
| Restrict compute.securityAdmin role | Limit who can create/delete firewall rules | P2 |

---

## Exercise Scorecard

| Metric | Value | Assessment |
|--------|-------|------------|
| Attack vectors injected | 4 | — |
| Attack vectors detected | 3 | 75% detection rate |
| Attack vectors missed | 1 (firewall egress deny) | Gap in egress monitoring |
| Phase 1 TTD | 2m34s | Good |
| Phase 2 TTD | 1m17s | Excellent (improved on second sweep) |
| Phase 3 TTD | MISSED | Failure |
| TTDIAG (full picture) | ~4m30s per phase | Good for detected attacks |
| Remediation script quality | 1 bug (bad flag) | Needs testing |
| False positives | 0 | Excellent |
| SME coordination | 4/4 P1 SMEs responsive | Good |
| Cross-domain synthesis | Strong | Correctly identified 1-2 punch pattern |

---

## Key Takeaways

### 1. Point-in-time snapshots are insufficient for adversarial detection
An adversary who times their actions between sweeps can evade detection entirely. We need continuous audit log monitoring with real-time alerting on infrastructure mutations.

### 2. Egress deny is a potent and underappreciated attack vector
A single priority-0 egress deny rule can sever all frontend→backend communication at the VPC level. This bypasses all Kubernetes-level monitoring. Our runbooks were blind to it.

### 3. Ephemeral attacks require persistent telemetry
The firewall rule existed for only 2m15s. Without audit log alerting or flow logs, an ephemeral rule leaves zero trace in infrastructure state — it can only be reconstructed forensically from audit logs after the fact.

### 4. Remediation commands must be tested before exercises
The `--clear-startup-probe` flag error would have cost time during a real incident. Remediation scripts should be validated against `gcloud` help or `--dry-run` before inclusion in runbooks.

---

*Debrief prepared by: sre-team-lead*
*Date: 2026-06-02*
*Exercise: Chaos vs. SRE — boutique-demo-22*
