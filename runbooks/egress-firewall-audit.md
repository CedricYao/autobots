# Runbook: Egress Firewall Rule Audit

**Runbook ID:** RB-005
**Derived from:** Chaos vs. SRE Exercise 2026-06-02 — missed firewall egress deny attack
**Failure type:** Rogue egress deny firewall rule severing frontend→backend connectivity
**Severity when triggered:** SEV1 (total frontend→backend disconnect if targeting backend subnet)
**Last updated:** 2026-06-02
**Owner:** vpc-networking-sme

---

## Key Lesson

> During the Chaos vs. SRE exercise, the SRE team detected 3 of 4 attack vectors but **completely missed a priority-0 egress deny rule** (`chaos-block-connector`) that blocked all traffic to the backend subnet 10.23.0.0/24. The rule existed for only 2 minutes and 15 seconds. It was missed because our triage runbooks only scanned for ingress rule changes — egress deny was a blind spot.

**Egress deny rules are the firewall equivalent of NetworkPolicy injection** — they silently sever connectivity with no visible error on the affected pods. All pods appear healthy; all health checks pass. The failure is only visible as timeouts from upstream services.

---

## Symptoms

| Signal | What You See |
|--------|-------------|
| User-facing | Pages timeout or return HTTP 500 (backend unreachable) |
| Cloud Run | All backend calls through VPC connector timeout |
| GKE pods | ALL pods Running 2/2, healthy, low CPU — **appear perfectly normal** |
| NetworkPolicies | NONE — this is NOT a Kubernetes-level block |
| VPC connector | READY status, but traffic not flowing |
| Key differentiator | If pods are healthy AND no NetworkPolicies exist AND frontend→backend times out, check EGRESS firewall rules |

## When to Use This Runbook

Use this runbook when you see frontend→backend timeout symptoms and:
- All GKE pods are healthy (Running 2/2, 0 restarts)
- No NetworkPolicies exist in the namespace
- VPC connector shows READY
- Routes to backend subnet exist
- The issue affects ALL services, not just one (VPC-level block)

---

## Detection

### Step 1: Check for egress firewall rules (5 seconds) — THE CRITICAL CHECK

```bash
gcloud compute firewall-rules list \
  --project=boutique-demo-22 \
  --filter="direction=EGRESS" \
  --format="table(name,priority,denied[].map().firewall_rule().list(),destinationRanges.list(),targetTags.list(),creationTimestamp)"
```

**Incident confirmed if:** ANY egress rule exists, especially:
- Direction: EGRESS with Action: DENY
- Destination ranges including `10.23.0.0/24` (backend subnet) or `10.8.0.0/28` (VPC connector subnet)
- Priority 0 or very low number (highest priority, overrides everything)
- Recently created (check `creationTimestamp`)

### Step 2: Inspect the suspicious rule (5 seconds)

```bash
gcloud compute firewall-rules describe <RULE_NAME> \
  --project=boutique-demo-22 \
  --format=json
```

**Red flags:**
- `direction: EGRESS` + `denied: [{IPProtocol: all}]` = deny ALL outbound traffic
- `destinationRanges` containing internal subnets (10.x.x.x)
- `priority: 0` — highest possible, overrides all other rules
- No `targetTags` or `targetServiceAccounts` — applies to ALL instances in VPC
- `logConfig.enable: false` — attacker hiding tracks

### Step 3: Check for ingress rules too (comprehensive sweep)

```bash
# Full firewall audit — both directions
gcloud compute firewall-rules list \
  --project=boutique-demo-22 \
  --format="table(name,direction,priority,sourceRanges.list(),destinationRanges.list(),allowed[].map().firewall_rule().list(),denied[].map().firewall_rule().list(),targetTags.list(),creationTimestamp)" \
  --sort-by=creationTimestamp
```

### Step 4: Attribution — who created it (15 seconds)

```bash
gcloud logging read \
  'protoPayload.serviceName="compute.googleapis.com" AND protoPayload.methodName:"firewalls" AND timestamp>="<INCIDENT_START_ISO8601>"' \
  --project=boutique-demo-22 \
  --limit=20 \
  --format='json(timestamp,protoPayload.methodName,protoPayload.resourceName,protoPayload.authenticationInfo.principalEmail,protoPayload.requestMetadata.callerIp)'
```

---

## Suspicious Indicators

### High-Confidence Attack Signals

| Indicator | Why It's Suspicious |
|-----------|-------------------|
| Priority 0 | Highest possible — overrides all other rules including `allow-ilb-permissive` |
| EGRESS + DENY ALL | Blocks all outbound protocols — overkill for any legitimate use |
| Destination is internal subnet | Legitimate egress denies target external IPs, not internal subnets |
| No target tags | Applies to ALL instances — legitimate rules are scoped to specific workloads |
| Logging disabled | Attacker hiding evidence |
| Created during an active incident | Change during incident without IC coordination |
| Rule name contains "block", "deny", "chaos", "test" | Obvious but check anyway |

### Lower-Confidence (May Be Legitimate)

| Indicator | Why It Might Be OK |
|-----------|-------------------|
| EGRESS deny to external IPs (0.0.0.0/0) | Could be a legitimate security hardening rule |
| Scoped with target tags | Intentional restriction on specific workloads |
| Created during maintenance window | Planned network change |
| Logging enabled | Operator who wants visibility |

---

## Remediation

### Step 1: Delete the rogue egress rule (immediate)

```bash
gcloud compute firewall-rules delete <RULE_NAME> \
  --project=boutique-demo-22 \
  --quiet
```

### Step 2: Verify traffic restoration (30 seconds)

```bash
# Test frontend→backend connectivity
curl -s -o /dev/null -w "%{http_code} %{time_total}s" http://34.46.255.20/ --max-time 15

# If Cloud Run path, test VPC connector→VIP connectivity
# (from a VM or Cloud Shell with VPC access)
curl -s -o /dev/null -w "%{http_code}" http://10.23.0.10:3550/ --max-time 10
```

### Step 3: Verify no other rogue rules remain

```bash
# Should return empty or only legitimate rules
gcloud compute firewall-rules list \
  --project=boutique-demo-22 \
  --filter="direction=EGRESS AND action=DENY" \
  --format="table(name,priority,denied,destinationRanges)"
```

### Step 4: Check if the rule was part of a multi-vector attack

Egress deny rules are often combined with other attacks (this was the case in the exercise):
- Check Cloud Run services for config poisoning (see RB-001, RB-002)
- Check IAM for privilege stripping (see RB-004)
- Check NetworkPolicies (see RB-003)

---

## Rollback Patterns

### If a legitimate egress rule was accidentally deleted

```bash
# Recreate with the original specification
gcloud compute firewall-rules create <RULE_NAME> \
  --project=boutique-demo-22 \
  --direction=EGRESS \
  --action=DENY \
  --rules=<PROTOCOL:PORT> \
  --destination-ranges=<CIDR> \
  --priority=<ORIGINAL_PRIORITY> \
  --target-tags=<TAGS> \
  --network=default
```

### If you need to temporarily block egress (legitimate use)

Always use scoped rules, never blanket deny:

```bash
# GOOD — scoped to specific workloads and destinations
gcloud compute firewall-rules create block-external-egress \
  --project=boutique-demo-22 \
  --direction=EGRESS \
  --action=DENY \
  --rules=all \
  --destination-ranges=0.0.0.0/0 \
  --target-tags=restricted-egress \
  --priority=1000 \
  --network=default \
  --enable-logging

# BAD — unscoped, affects everything
gcloud compute firewall-rules create block-all \
  --direction=EGRESS --action=DENY --rules=all \
  --destination-ranges=10.23.0.0/24 --priority=0
```

---

## Integration with Triage Protocol

### Add to ALL incident triage checklists (Step 0)

Before checking pods, services, or application config, run:

```bash
# Quick egress rule check — 5 seconds
gcloud compute firewall-rules list --project=boutique-demo-22 \
  --filter="direction=EGRESS" \
  --format="table(name,priority,denied,destinationRanges,creationTimestamp)"
```

If ANY egress deny rule exists targeting internal subnets — investigate immediately before proceeding to application-layer triage.

### Add continuous monitoring

Set up a Cloud Monitoring alert on firewall mutation audit logs:

```bash
# Alert on any firewall rule create/delete/update
gcloud alpha monitoring policies create \
  --project=boutique-demo-22 \
  --display-name="Firewall Rule Change Alert" \
  --condition-display-name="Firewall rule created, deleted, or modified" \
  --condition-filter='metric.type="logging.googleapis.com/log_entry_count" AND resource.type="gce_firewall_rule"' \
  --condition-threshold-value=0 \
  --condition-threshold-comparison=COMPARISON_GT \
  --condition-threshold-duration=0s \
  --notification-channels="${CHANNEL_ID}" \
  --documentation="A firewall rule was created, deleted, or modified. Verify this was an authorized change."
```

### Add re-sweep protocol

After initial triage sweep, schedule a re-sweep at T+2 minutes to catch:
- Timing races (rules created between sweep and report)
- Audit log ingestion delays
- Multi-phase attacks where later vectors follow initial distraction

---

## Exercise Context

During the Chaos vs. SRE exercise on 2026-06-02, the chaos team executed a 4-phase attack:

| Phase | Time | Vector | Detected? |
|-------|------|--------|-----------|
| 1 | 23:26Z | Cloud Run env var poisoning + startup probe sabotage | YES (2m34s) |
| 1b | 23:36Z | Additional poisoned revisions + track covering | YES (2m23s) |
| 2 | 23:37Z | IAM roles/run.developer stripped from compute SA | YES (1m17s) |
| 3 | 23:38Z | **Egress deny rule `chaos-block-connector`** | **MISSED** |

The firewall rule was the most impactful attack — it would have severed ALL frontend→backend connectivity across ALL environments. It was also the stealthiest: 2m15s lifetime, logging disabled, and our triage protocol had no egress check.

**This runbook exists because we missed it.**

---

## Gotchas

1. **Egress rules affect ALL resources in the VPC** unless scoped with target tags. A single rule can break every service simultaneously.
2. **Priority 0 overrides everything** — including `allow-ilb-permissive` (priority 1) and all other allow rules. There is no firewall rule that can counteract a priority-0 deny.
3. **Ephemeral rules leave no infrastructure trace.** Once deleted, the only evidence is in Cloud Audit Logs. If audit logs are not being actively monitored, the attack is invisible.
4. **VPC Flow Logs must be enabled** on affected subnets to see packet-level evidence of denied traffic. Currently disabled on both `gke-vip-subnet` and `serverless-connector` subnets.
5. **Egress deny is NOT the same as NetworkPolicy.** NetworkPolicies operate at the pod level within Kubernetes. Firewall rules operate at the VPC level and affect all traffic, including VPC connector traffic from Cloud Run. Different detection, different remediation.

---

*Source: Chaos vs. SRE Exercise 2026-06-02 — missed Phase 3 attack*
*See also: /workspace/runbooks/exercise-debrief-2026-06-02.md*
