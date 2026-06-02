# Runbook: PaymentService Crash (CrashLoopBackOff)

**Runbook ID:** RB-001
**Derived from:** INC-2026-0601-001, Root Cause 2
**Failure type:** Service misconfiguration — invalid environment variable causing crash loop
**Severity when triggered:** SEV1 (checkout completely broken for all users)
**Last updated:** 2026-06-02
**Owner:** microservices-sme

---

## Symptoms

| Signal | What You See |
|--------|-------------|
| User-facing | Checkout returns HTTP 500: "failed to complete the order" |
| Pod status | `paymentservice` in `CrashLoopBackOff`, 1/2 Ready (istio-proxy still running) |
| Logs | `"Error: server must be bound in order to start"` |
| Misleading log | `"PaymentService gRPC server started on port INVALID_PORT"` — logged BEFORE bind attempt, looks like success |
| gRPC error chain | `code = Unavailable` -> `code = Internal desc = failed to charge card` |
| Blast radius | Checkout broken for ALL users on ALL frontends; browsing/catalog still works |

## Detection

### Step 1: Confirm pod crash (5 seconds)

```bash
kubectl get pods -l app=paymentservice -n online-boutique-demo
```

**Expected bad state:** `CrashLoopBackOff` or `Error`, restart count > 0

### Step 2: Check crash reason (10 seconds)

```bash
kubectl logs -l app=paymentservice -n online-boutique-demo --tail=10
kubectl logs -l app=paymentservice -n online-boutique-demo --tail=5 --previous
```

**Key error:** `"server must be bound in order to start"` — confirms PORT misconfiguration.

### Step 3: Inspect environment variable (5 seconds)

```bash
kubectl get deployment paymentservice -n online-boutique-demo \
  -o jsonpath='{.spec.template.spec.containers[0].env}' | python3 -m json.tool
```

**Root cause confirmed if:** `PORT` is set to anything other than `50051` (the correct gRPC port).

### Step 4: Check what changed (15 seconds)

```bash
kubectl rollout history deployment/paymentservice -n online-boutique-demo
```

Compare current revision to previous:
```bash
kubectl rollout history deployment/paymentservice -n online-boutique-demo --revision=<CURRENT>
kubectl rollout history deployment/paymentservice -n online-boutique-demo --revision=<PREVIOUS>
```

## Remediation

### Option A: Fix the environment variable directly (preferred)

```bash
kubectl set env deployment/paymentservice -n online-boutique-demo PORT=50051
```

### Option B: Rollback to last known-good revision

```bash
kubectl rollout undo deployment/paymentservice -n online-boutique-demo
```

### Verification (mandatory)

Wait 30-60 seconds for new pod to start, then:

```bash
# 1. Pod should be Running 2/2 with 0 restarts
kubectl get pods -l app=paymentservice -n online-boutique-demo

# 2. Logs should show successful bind (NO "server must be bound" error after the start message)
kubectl logs -l app=paymentservice -n online-boutique-demo --tail=5

# 3. Checkout should work (expect HTTP 200 or 302, not 500)
curl -s -o /dev/null -w "%{http_code}" -X POST http://34.46.255.20/cart/checkout --max-time 15
```

## Attribution

After remediation, determine who/what changed the PORT variable:

```bash
gcloud logging read \
  'resource.type="k8s_cluster" AND protoPayload.methodName:"deployments" AND protoPayload.resourceName:"paymentservice" AND timestamp>="<INCIDENT_START_ISO8601>"' \
  --project=boutique-demo-22 \
  --format='json(timestamp,protoPayload.authenticationInfo.principalEmail,protoPayload.methodName)' \
  --limit=20
```

## Escalation

If the SRE team lacks write access (viewer-only SA):

```
URGENT — Permission escalation needed to remediate PaymentService crash.

Root cause: PORT env var changed to invalid value. PaymentService in CrashLoopBackOff. Checkout broken for all users.

To fix immediately (2 min), run:
  kubectl set env deployment/paymentservice -n online-boutique-demo PORT=50051

Alternatively, grant agent write access:
  gcloud projects add-iam-policy-binding boutique-demo-22 \
    --member='serviceAccount:scion-platform-team@deploy-demo-test.iam.gserviceaccount.com' \
    --role='roles/container.developer'
```

## Gotchas

1. **Misleading success log:** PaymentService logs `"started on port INVALID_PORT"` before attempting the bind. Don't assume it started successfully — always check for the bind error in subsequent log lines.
2. **Alert false negative:** The restart count alert may fire and auto-close because the metric resets when pods are recreated. Don't trust alert closure as evidence the problem resolved.
3. **Downstream impact:** CheckoutService calls PaymentService synchronously. When PaymentService is down, CheckoutService returns `code = Internal` with `desc = failed to charge card`. All other services (catalog, cart, shipping) remain healthy.

## Correct PORT values

| Service | Correct PORT |
|---------|-------------|
| paymentservice | 50051 |
| shippingservice | 50051 |
| cartservice | 7070 |
| checkoutservice | 5050 |
| productcatalogservice | 3550 |
| currencyservice | 7000 |
| recommendationservice | 8080 |
| adservice | 9555 |
| emailservice | 8080 |

---

*Source: INC-2026-0601-001 Phase 1, Root Cause 2 — PaymentService INVALID_PORT crash*
