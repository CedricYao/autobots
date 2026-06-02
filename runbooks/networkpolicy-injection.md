# Runbook: NetworkPolicy Injection (Deny-All Ingress)

**Runbook ID:** RB-003
**Derived from:** INC-2026-0601-001, Phase 2 (Root Cause 4) + INC-2026-0528 (Pattern 1)
**Failure type:** Rogue or accidental NetworkPolicy blocking critical service traffic
**Severity when triggered:** SEV1 (total site outage if targeting a critical-path service)
**Last updated:** 2026-06-02
**Owner:** microservices-sme

---

## Symptoms

| Signal | What You See |
|--------|-------------|
| User-facing | Site completely unresponsive — pages timeout after 15-60 seconds |
| curl | `000` (timeout) or HTTP 500 with "context canceled" |
| Pod status | ALL pods show Running 2/2, low CPU, 0 restarts — **pods appear perfectly healthy** |
| Why pods look healthy | Kubelet health probes operate at node level and are NOT blocked by pod-to-pod NetworkPolicies |
| Logs | Upstream services show `code = Canceled desc = context canceled` (60s timeout hit) |
| Blast radius | Depends on target service; CartService affects ALL pages (every page calls cart for header count) |

## Why This Is Dangerous

Kubernetes NetworkPolicies are **default-deny when applied**. Once ANY NetworkPolicy selects a pod with `policyTypes: [Ingress]` and defines NO ingress rules, it blocks ALL inbound pod-to-pod traffic to that pod. This is the highest-blast-radius Kubernetes resource because:

1. It causes total traffic blackout with zero visible errors on the target pod
2. Health probes continue passing (they bypass NetworkPolicy)
3. The affected pod reports as Running and Ready
4. All diagnosis tools (pod status, resource usage, logs on the target) look normal

The failure is only visible from **upstream** services that time out trying to reach the target.

## Detection

### Step 1: Check for NetworkPolicies (5 seconds) — DO THIS FIRST

```bash
kubectl get networkpolicy -n online-boutique-demo
```

**Incident confirmed if:** Any NetworkPolicy exists, especially one created recently (check `AGE` column).

Known malicious/accidental patterns:
- `block-cart-ingress` — blocks CartService, takes down entire site
- Any policy with `policyTypes: [Ingress]` and empty/missing `ingress:` rules

### Step 2: Inspect the policy (5 seconds)

```bash
kubectl get networkpolicy <POLICY_NAME> -n online-boutique-demo -o yaml
```

**Red flags:**
- `policyTypes: [Ingress]` with NO `ingress:` rules = deny-all inbound
- `podSelector` matching a critical-path service (cartservice, frontend, checkoutservice)

### Step 3: Verify pods are healthy but traffic-blocked (10 seconds)

```bash
# Pods look healthy
kubectl get pods -n online-boutique-demo

# But upstream services are timing out
kubectl logs -l app=frontend -n online-boutique-demo --tail=10 | grep -i "canceled\|timeout\|unavailable"
```

### Step 4: Attribution — who created it (15 seconds)

```bash
gcloud logging read \
  'resource.type="k8s_cluster" AND protoPayload.methodName="io.k8s.networking.v1.networkpolicies.create" AND protoPayload.resourceName:"<POLICY_NAME>"' \
  --project=boutique-demo-22 \
  --format='json(timestamp,protoPayload.authenticationInfo.principalEmail,protoPayload.requestMetadata.callerIp,protoPayload.requestMetadata.callerSuppliedUserAgent)' \
  --limit=5
```

## Remediation

### Step 1: Delete the rogue NetworkPolicy (immediate)

```bash
kubectl delete networkpolicy <POLICY_NAME> -n online-boutique-demo
```

### Step 2: Restart the affected service (CRITICAL — don't skip)

**Deleting the NetworkPolicy is NOT sufficient for full recovery.** The target service's Istio envoy sidecar retains stale connection state from the prolonged deny period. Existing connection pools and circuit breakers need to be reset:

```bash
kubectl rollout restart deployment/<AFFECTED_SERVICE> -n online-boutique-demo
```

Wait ~60 seconds for the new pod to reach Ready (2/2).

### Step 3: Verify recovery (mandatory)

```bash
# 1. Site responds
curl -s -o /dev/null -w "%{http_code} %{time_total}s" http://34.46.255.20/ --max-time 15

# 2. Target pod is healthy
kubectl get pods -l app=<AFFECTED_SERVICE> -n online-boutique-demo

# 3. No NetworkPolicies remain
kubectl get networkpolicy -n online-boutique-demo

# 4. Upstream errors have stopped
kubectl logs -l app=frontend -n online-boutique-demo --tail=5 | grep -i "canceled\|timeout"
```

## Critical-Path Services

If a NetworkPolicy targets any of these services, the impact is site-wide:

| Service | Why It's Critical | Impact If Blocked |
|---------|-------------------|-------------------|
| cartservice | Every page calls it for cart item count in header | ALL pages timeout/500 |
| frontend | Entry point for all traffic | Total outage |
| checkoutservice | Orchestrates 6 downstream services | Checkout broken |
| productcatalogservice | Homepage, product pages, recommendations depend on it | Most pages broken |
| currencyservice | Called by frontend for every price display | Pages very slow or broken |

## Incident Change Control

This failure type was caused by a responder applying an unreviewed change during an active incident. To prevent recurrence:

### Before applying any NetworkPolicy during an incident:

1. **Announce to IC:** "I'm about to apply NetworkPolicy X targeting service Y"
2. **State the rollback:** "Rollback command: `kubectl delete networkpolicy X -n online-boutique-demo`"
3. **Assess blast radius:** "Service Y is on the critical/interim path: YES/NO"
4. **Get IC approval** if the service is on the active serving path
5. **Verify after applying:** Check site health within 60 seconds
6. **Do NOT walk away** without verifying

### Never apply a NetworkPolicy that:
- Targets a service on the current critical/interim serving path
- Has `policyTypes: [Ingress]` with no explicit ingress allow rules
- You haven't tested in a non-production environment first

## Escalation

If the SRE team lacks write access:

```
URGENT — Rogue NetworkPolicy blocking <SERVICE>. Site is DOWN.

To fix immediately (30 seconds), run:
  kubectl delete networkpolicy <POLICY_NAME> -n online-boutique-demo
  kubectl rollout restart deployment/<SERVICE> -n online-boutique-demo

The policy was created by <EMAIL> at <TIMESTAMP> (from audit logs).
```

## Gotchas

1. **Pods look healthy:** This is the #1 misdirection. All standard pod health checks pass. The failure is only visible at the network/traffic level.
2. **Delete is not enough:** After deleting the policy, you MUST restart the affected service's pod to clear Istio sidecar stale state. Without the restart, traffic may remain broken for 5-15 minutes.
3. **Multiple NetworkPolicies compound:** If multiple policies select the same pod, ALL policies must allow the traffic. Deleting one may not restore access if another restrictive policy exists.
4. **NetworkPolicy scope:** Policies are namespace-scoped. Check `kubectl get networkpolicy -A` if you suspect cross-namespace policies.
5. **Default Kubernetes behavior:** Without ANY NetworkPolicy, all pod-to-pod traffic is allowed. The moment you apply ONE policy selecting a pod, that pod switches to deny-all-except-explicitly-allowed for that policy type.

---

*Source: INC-2026-0601-001 Phase 2 — Responder-induced secondary outage via NetworkPolicy `block-cart-ingress`*
*Also: INC-2026-0528 patterns 1 and 5 — NetworkPolicy deny-all (solo and compound)*
