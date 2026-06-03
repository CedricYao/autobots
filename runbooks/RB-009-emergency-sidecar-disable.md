# Runbook: RB-009 — Emergency Istio Sidecar Disable

**Runbook ID:** RB-009
**Derived from:** Battle 2 (2026-06-03) — Istio CRD flood attack (~05:15Z-05:37Z)
**Failure type:** Service mesh used as attack surface (CRD flood causing sidecar CrashLoopBackOff)
**Severity when triggered:** SEV1 — Total backend outage when sidecars crash
**Last updated:** 2026-06-03
**Owner:** microservices-sme

---

## Executive Summary

During Battle 2, the chaos team flooded the cluster with ~11 Istio CRDs every 10 seconds (VirtualServices with fault injection, AuthorizationPolicies with deny-all, DestinationRules, PeerAuthentications, ServiceEntries). This caused xDS configuration churn that put all Istio sidecar proxies into CrashLoopBackOff, creating a total backend outage lasting ~22 minutes.

**The breakthrough:** Disabling Istio sidecar injection on the namespace and performing a rolling restart removed the crashed sidecars entirely, making pods immune to further CRD-based attacks. This restored backend service within minutes.

**Trade-off:** Disabling sidecars sacrifices mTLS, traffic management, and mesh observability. This is an **emergency measure** — use only when the service mesh itself is the attack surface.

---

## When to Use This Runbook

Use this procedure when ALL of the following are true:

| Condition | How to Verify |
|-----------|---------------|
| Multiple pods in CrashLoopBackOff | `kubectl get pods -n ${NAMESPACE}` — look for restart counts climbing |
| Crashed container is `istio-proxy` (sidecar) | `kubectl describe pod <pod> -n ${NAMESPACE}` — check container statuses |
| CRD flood detected | `kubectl get virtualservices,authorizationpolicies,destinationrules -n ${NAMESPACE}` — unusual count |
| CRD purge alone is insufficient | Deleting CRDs doesn't stop the flood (attacker re-injecting faster than cleanup) |
| Backend outage duration exceeds 10 minutes | Standard CRD cleanup has failed to stabilize |

**Do NOT use if:**
- Only one or two pods are affected (targeted issue, not mesh-wide)
- The crash is in the application container, not `istio-proxy`
- mTLS is required for compliance (seek alternative — e.g., isolate the attacker's access)

---

## Prerequisites

- `kubectl` access to the GKE cluster (`online-boutique-764d49`, `us-central1-a`)
- Namespace: `online-boutique-demo` (or target namespace)
- IC approval (this disables security features)

### Auth Bootstrap (if needed)
```bash
gcloud container clusters get-credentials online-boutique-764d49 \
  --zone us-central1-a --project boutique-demo-22
```

---

## Procedure: Disable Sidecars

### Step 1: Confirm sidecar crashes are the problem (30 seconds)

```bash
# Check for CrashLoopBackOff pods
kubectl get pods -n online-boutique-demo \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[1].restartCount,CONTAINER:.status.containerStatuses[1].name,STATE:.status.containerStatuses[1].state'

# Verify it's the istio-proxy container crashing
kubectl get pods -n online-boutique-demo -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.name}={.ready}{" "}{end}{"\n"}{end}'
```

**Confirm:** Multiple pods show `istio-proxy=false` with high restart counts.

### Step 2: Announce to IC

> "EMERGENCY: Disabling Istio sidecar injection on namespace online-boutique-demo. This will sacrifice mTLS, traffic management, and mesh observability. Reason: sidecar proxies in CrashLoopBackOff due to CRD flood — standard CRD cleanup insufficient."

### Step 3: Disable sidecar injection on the namespace (5 seconds)

```bash
kubectl label namespace online-boutique-demo istio-injection=disabled --overwrite
```

### Step 4: Rolling restart all deployments (60-120 seconds)

New pods will start WITHOUT the istio-proxy sidecar.

```bash
# Restart all deployments in the namespace
DEPLOYMENTS=$(kubectl get deployments -n online-boutique-demo -o jsonpath='{.items[*].metadata.name}')
for DEPLOY in $DEPLOYMENTS; do
  echo "[$(date -u +%H:%M:%SZ)] Restarting: $DEPLOY"
  kubectl rollout restart deployment/$DEPLOY -n online-boutique-demo
done
```

### Step 5: Wait for rollout and verify (60-120 seconds)

```bash
# Wait for all rollouts to complete
for DEPLOY in $DEPLOYMENTS; do
  kubectl rollout status deployment/$DEPLOY -n online-boutique-demo --timeout=120s
done

# Verify pods are running with 1/1 containers (no sidecar)
kubectl get pods -n online-boutique-demo \
  -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[*].ready,CONTAINERS:.spec.containers[*].name'
```

**Expected:** Pods show `1/1` ready (application container only, no `istio-proxy`).

### Step 6: Verify service connectivity (30 seconds)

```bash
# Test frontend → backend via VIP
curl -s -o /dev/null -w "%{http_code} %{time_total}s" http://34.46.255.20/ --max-time 15

# Check endpoints are populated for all services
kubectl get endpoints -n online-boutique-demo \
  -o custom-columns='SERVICE:.metadata.name,ENDPOINTS:.subsets[*].addresses[*].ip'
```

### Step 7: Clean up rogue CRDs (now safe — sidecars are gone)

```bash
# Delete all rogue Istio CRDs in the namespace
kubectl delete virtualservices --all -n online-boutique-demo 2>/dev/null
kubectl delete authorizationpolicies --all -n online-boutique-demo 2>/dev/null
kubectl delete destinationrules --all -n online-boutique-demo 2>/dev/null
kubectl delete peerauthentications --all -n online-boutique-demo 2>/dev/null
kubectl delete serviceentries --all -n online-boutique-demo 2>/dev/null
kubectl delete envoyfilters --all -n online-boutique-demo 2>/dev/null
echo "Rogue CRDs cleaned — harmless without sidecars but removing for hygiene"
```

---

## Procedure: Re-Enable Sidecars (Post-Incident)

Only re-enable after the attack vector is neutralized (e.g., attacker's access revoked, RBAC restricted).

### Step 1: Re-enable sidecar injection

```bash
kubectl label namespace online-boutique-demo istio-injection=enabled --overwrite
```

### Step 2: Verify no rogue CRDs exist

```bash
# Must be clean before restarting with sidecars
kubectl get virtualservices,authorizationpolicies,destinationrules,peerauthentications,serviceentries,envoyfilters -n online-boutique-demo
```

**Must return:** No resources found (or only legitimate mesh config).

### Step 3: Rolling restart to inject sidecars

```bash
DEPLOYMENTS=$(kubectl get deployments -n online-boutique-demo -o jsonpath='{.items[*].metadata.name}')
for DEPLOY in $DEPLOYMENTS; do
  echo "[$(date -u +%H:%M:%SZ)] Restarting with sidecar: $DEPLOY"
  kubectl rollout restart deployment/$DEPLOY -n online-boutique-demo
done

# Wait for rollouts
for DEPLOY in $DEPLOYMENTS; do
  kubectl rollout status deployment/$DEPLOY -n online-boutique-demo --timeout=120s
done
```

### Step 4: Verify sidecar injection

```bash
# All pods should show 2/2 (app + istio-proxy)
kubectl get pods -n online-boutique-demo \
  -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[*].ready,CONTAINERS:.spec.containers[*].name'
```

**Expected:** Pods show `2/2` ready with both application and `istio-proxy` containers.

### Step 5: Verify mTLS is active

```bash
# Check PeerAuthentication mode
kubectl get peerauthentication -n online-boutique-demo -o yaml

# Verify mutual TLS connections
istioctl proxy-status 2>/dev/null || echo "istioctl not available — verify via pod logs"
```

---

## Capabilities Lost When Sidecars Are Disabled

| Capability | Impact | Risk Level |
|------------|--------|------------|
| **mTLS** | Pod-to-pod traffic is unencrypted | HIGH — data in transit is plaintext |
| **Traffic management** | VirtualService routing, retries, timeouts not enforced | MEDIUM |
| **Circuit breaking** | DestinationRule circuit breakers inactive | MEDIUM |
| **Mesh observability** | No Istio telemetry, distributed tracing degraded | LOW during incident |
| **Authorization policies** | Mesh-level AuthorizationPolicies not enforced | HIGH if used for access control |
| **Rate limiting** | Envoy-based rate limits inactive | LOW |

**Key judgment:** During an active attack where the mesh itself is weaponized, running without these capabilities is safer than running with crashed sidecars (which provides none of them anyway, plus total outage).

---

## Battle 2 Timeline Reference

```
05:15Z  Istio CRD flood begins (~11 CRDs/10s: VS, AP, DR, PA, SE)
05:15Z  Sidecar proxies begin CrashLoopBackOff from xDS churn
05:15Z  Total backend outage — all services unreachable
05:20Z  CRD purge attempted — insufficient (re-injected faster than deleted)
05:37Z  DECISION: Disable sidecar injection (this runbook)
05:37Z  Namespace labeled istio-injection=disabled
05:38Z  Rolling restart initiated on all deployments
05:40Z  Pods come up 1/1 (no sidecar) — backend connectivity restored
05:40Z  Rogue CRDs now harmless (no sidecars to receive xDS updates)
```

**Total outage duration:** ~22 minutes (05:15Z - 05:37Z)
**Time from decision to recovery:** ~3 minutes

---

## Gotchas

1. **Rolling restart is mandatory.** Just labeling the namespace does not remove existing sidecars — pods must be recreated.
2. **Application networking must work without Istio.** Online Boutique services use gRPC with direct service DNS — they work fine without the mesh. Applications that depend on Istio for service discovery will break.
3. **CRD cleanup is still needed.** Even with sidecars disabled, clean up rogue CRDs to prevent issues when re-enabling.
4. **Re-enablement requires a clean mesh state.** Do NOT re-enable sidecars while rogue CRDs still exist — the sidecars will immediately crash again.
5. **HPA/PDB should be in place before re-enabling** to prevent scale-to-zero attacks during the sidecar restart window.

---

*Source: Battle 2 Chaos Exercise (2026-06-03) — Istio CRD flood attack, 22-minute outage resolved by sidecar disable*
*See also: Battle 2 Postmortem, RB-008 GKE Attack Response*
