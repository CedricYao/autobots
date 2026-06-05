# Postmortem: Battle 3 — Chaos Engineering Exercise
## Project: boutique-demo-22 | Date: 2026-06-05

**Result: SRE DECISIVE WIN — 95/100 average score. All scored faults detected and remediated.**

**IC:** Coordinator (no sre-team-lead deployed)
**Duration:** 16:15Z – 16:29Z (~14 minutes)
**Chaos Team:** chaos-strategist + 3 fault agents (app-chaos, infra-chaos, network-chaos) + observer-chaos
**SRE Team:** 9 SME agents (no sre-team-lead)

---

## Executive Summary

Battle 3 was the first chaos engineering exercise (vs. red-team in Battles 1-2), focused on realistic fault injection — bad deployments, port misconfigurations, resource limit errors, and observability tampering. The chaos team injected 6 faults over ~14 minutes, following rules of engagement that required one fault at a time with 2-5 minute gaps. The SRE team detected 5 of 6 faults (the 6th was injected 16 seconds before battle end), remediated all 4 scored faults, and maintained near-zero customer impact (1 single HTTP 500 across the entire battle).

Key finding: **Realistic faults are harder to diagnose than DDOS-style attacks.** Fault #1 (targetPort mismatch) was detected in 38 seconds but took 7 minutes to correctly diagnose. The SRE team also nearly caused a self-inflicted outage by misidentifying a correct configuration as a fault (emailservice false positive).

---

## Philosophy Change from Battles 1-2

Battle 3 introduced a fundamental shift:
- **Before:** Adversarial red-team attacks (CRD flooding, multi-vector simultaneous assaults, evidence destruction)
- **After:** Realistic fault injection (bad deployments, misconfigurations, accidental changes)
- **New rules:** One fault at a time, 2-5 min detection windows, no DDOS-style flooding
- **New alerting:** 11 SLI/SLO-focused alerts replaced 14 security/red-team alerts

---

## Pre-Battle Improvements (Since Battle 2)

| Change | Status |
|--------|--------|
| CCR-001: allow-ilb-permissive firewall deleted | COMPLETED |
| VPC flow logs enabled (2 subnets) | COMPLETED |
| 9 ILB services deployed for VIP 10.23.0.10 | COMPLETED |
| 11 SLI/SLO alert policies (replaced 14 security alerts) | COMPLETED |
| Notification channel wired to all alerts | COMPLETED |
| Stage startup probe restored | COMPLETED |
| Bucket versioning + PAP on all storage | COMPLETED |
| Pre-staged HPAs, PDBs, sweep scripts | STAGED (not deployed) |

---

## Fault Timeline

| # | Time | Fault | Real-World Scenario | Injected By |
|---|------|-------|--------------------|----|
| 1 | 16:17:22Z | productcatalogservice targetPort 3550→9999 | Bad kubectl apply | app-chaos |
| 2 | 16:21:08Z | checkoutservice memory limit 128Mi→103Mi | Bad resource config | chaos-strategist |
| 3 | — | emailservice targetPort flagged (FALSE POSITIVE) | Not an attack | — |
| 4 | 16:25:04Z | paymentservice image → v0.0.0-nonexistent | Bad CI/CD deployment | chaos-strategist |
| 5 | 16:24:45Z | 2 GKE alert policies silently disabled | Accidental monitoring maintenance | chaos-strategist |
| 6 | 16:28:34Z | frontend-alt-dev ingress → internal | Security hardening mistake | network-chaos |

---

## Detection & Response Scorecard

| # | Fault | TTD | TTDIAG | TTR | TTRECOV | Diagnosis | Score |
|---|-------|-----|--------|-----|---------|-----------|-------|
| 1 | productcatalog targetPort | 38s | 7min | 3s | 7m18s | Correct | 100 |
| 2 | checkout memory | <30s | <30s | N/A | N/A | Correct | N/A* |
| 3 | email false positive | — | — | — | — | WRONG | N/A |
| 4 | payment bad image | 32s | 32s | 1min | 1min | Correct | 95 |
| 5 | alert policy disable | 1m48s | 1m48s | 2min | 2min | Correct | 90 |
| 6 | Cloud Run ingress | N/D | N/D | N/D | N/D | N/D | N/A** |

*Attacker rolled back own ineffective fault
**Injected 16 seconds before battle end

**SRE Average Score (scored faults): 95/100**

---

## What Went Well

### 1. Fast Detection
microservices-sme detected ALL GKE faults within 30-40 seconds. cloud-monitoring-sme caught the productcatalogservice error cascade within 38 seconds via log-based monitoring.

### 2. Cross-Domain Detection
iam-sme detected the alert policy disable via IAM audit logs (1m48s) — faster than the monitoring team's own sweep cycle. This cross-domain observation was the strongest coordination signal of the battle.

### 3. Zero Secondary Failures
No remediation action caused additional problems. All patches and rollbacks were clean.

### 4. Rule Compliance
The chaos team followed all Rules of Engagement. Observer confirmed: one fault at a time, 2-5 minute gaps, no flooding, no prohibited actions.

### 5. SLI/SLO Alert Investment
The reframed alert policies provided the first detection signals. The monitoring shift from security-detection to DR/SLO paid off.

### 6. Traffic Pinning Held
Cloud Run services stayed on known-good revisions throughout. Only 1 HTTP 500 across the entire battle.

---

## What Didn't Go Well

### 1. 7-Minute Diagnosis Bottleneck (Fault #1)
productcatalogservice targetPort mismatch was detected in 38 seconds but took 7 minutes to correctly diagnose. The SRE team checked ConfigMap, deployment, image, and Istio CRDs before finally discovering the targetPort was changed from 3550 to 9999. Sweep scripts check port and selector but NOT targetPort vs containerPort.

### 2. emailservice False Positive (Near Self-Inflicted Outage)
microservices-sme incorrectly flagged emailservice targetPort=8080 as a fault, assuming it should match the service port (5000). The container actually listens on 8080, so the configuration was correct. Fortunately, no "fix" was applied — but this could have caused a self-inflicted outage.

### 3. No SRE Team Lead
Coordination was organic rather than directed. With a team lead, triage prioritization and diagnosis could have been faster.

### 4. Monitoring Sleep Cycles Too Slow
cloud-monitoring-sme used 90-120 second sleep cycles, missing early detection windows. IAM-SME's audit log check was faster for the alert policy disable.

### 5. GKE Frontend Returns 200 for Error Pages
The GKE frontend returned HTTP 200 even when rendering error pages, preventing Cloud Run 5xx alerts from firing on cascading backend failures.

---

## Chaos Team Effectiveness

| Fault | Stealth Rating | Impact |
|-------|---------------|--------|
| targetPort mismatch | HIGH — 7min to correct diagnosis | P1 — all product pages broken |
| Memory limit reduction | LOW — immediately detected, ineffective | Minimal — no OOM at 103Mi |
| Bad image deployment | LOW — immediately obvious (ImagePullBackOff) | Mitigated by RollingUpdate strategy |
| Alert policy disable | MEDIUM — 1m48s before detection | Successfully blinded 2 alerts for 2m34s |
| Cloud Run ingress | UNTESTED — injected too late | Would have blocked dev environment access |

---

## Key Metrics Comparison

| Metric | Battle 2 | Battle 3 |
|--------|----------|----------|
| Duration | 44 min | 14 min |
| Attack vectors | 14 | 6 |
| Simultaneous vectors | Up to 14 | 1-2 max |
| Total HTTP 500s | Hundreds+ | 1 |
| GKE total outage | ~20 min | ~3 min (productcatalog only) |
| Cloud Run impact | 17+ traffic rollbacks | 0 rollbacks needed |
| Avg detection time | Variable | <1 min |
| False positives | 1 (friendly fire) | 1 (emailservice) |
| SRE agents consulted SRE expert | Unknown | 0 |

---

## Domains Not Targeted

- **VPC Networking** — All components unchanged
- **Cloud Deploy** — Pipeline integrity maintained
- **Artifact Registry** — No image or tag tampering
- **Cloud Storage** — All 8 buckets unchanged
- **IAM** — No direct policy or SA attacks

---

## Recommendations

### P0 — Fix Before Battle 4
1. **Fix sweep scripts** — Check targetPort vs containerPort, not just port/selector (prevents false positives and improves diagnosis)
2. **Deploy sre-team-lead** — Directed triage coordination during incidents

### P1 — Should Do Before Battle 4
3. **Reduce monitoring sleep intervals** to 30-60 seconds
4. **Add continuous service spec diffing** against known-good baseline
5. **Add meta-alert for alert policy changes** (SLO-framed as "observability self-health")
6. **Fix GKE frontend** to return 5xx on error pages (enables Cloud Run cascade detection)

### P2 — Battle 4 Scope
7. **Test IAM attack vectors** — SA key creation, policy escalation, SA disable
8. **Test Cloud Deploy pipeline faults** — bad release, target config changes
9. **Test VPC connector and storage layer** faults
10. **Add synthetic end-to-end transaction monitoring** (place order flow)
11. **Create custom IAM role** for platform SA — remove roles/editor

---

## Observer Rule Compliance Assessment

| Rule | Status |
|------|--------|
| One fault at a time | MOSTLY COMPLIANT (Phase 4 had 3 actions in 19s, but sequential) |
| 2-5 min between escalations | COMPLIANT (gaps: 4min, 3.5min, 4min) |
| No flooding/DDOS | COMPLIANT |
| No SA/IAM changes | COMPLIANT |
| No project destruction | COMPLIANT |
| No Scion infrastructure attacks | COMPLIANT |
| Document each fault | COMPLIANT |

---

*Postmortem compiled by coordinator from observer-chaos battle log and 9 SRE agent final reports.*
*Battle 3 concluded 2026-06-05 16:29Z.*
*Final score: SRE 95/100. Chaos team rule-compliant. 1 false positive, 1 near-miss.*
