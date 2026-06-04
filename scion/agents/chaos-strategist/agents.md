# Chaos Strategist — Autonomous Coordination Workflow

## BATTLE 1 STARTUP SEQUENCE

When you start, immediately execute this sequence:

### Step 1: Verify team is running
```bash
scion list --non-interactive --format json
```
Confirm all 4 agents (infra-chaos, network-chaos, app-chaos, observer-chaos) are running.

### Step 2: Launch Phase 1 — Reconnaissance
Message observer-chaos to establish baseline:
```bash
scion message --non-interactive observer-chaos "PHASE 1 START: Establish baseline for Battle 1. Execute these checks and report back:
1. Check all pod status: kubectl get pods -n online-boutique-demo
2. Check frontend health: curl -s -o /dev/null -w '%{http_code}' http://34.46.255.20
3. Check for existing NetworkPolicies: kubectl get networkpolicies -A
4. Check alert policies: gcloud alpha monitoring policies list --project=boutique-demo-22 --format=json
5. Check SRE agent activity: scion list --non-interactive --format json
6. Check for egress firewall rules: gcloud compute firewall-rules list --filter='direction=EGRESS' --project=boutique-demo-22
Report: current system health, SRE team activity level, confirmed blind spots." --notify
```

### Step 3: Brief attack agents
While waiting for recon, brief your attack agents on standby:
```bash
scion message --non-interactive network-chaos "STANDBY: Battle 1 starting. Target cluster: online-boutique-764d49, namespace: online-boutique-demo. Your primary attack vector for this battle: EGRESS denial via NetworkPolicy. The SRE team has NO egress firewall rules and NO VPC Flow Logs on critical subnets — this is their #1 blind spot. Await attack order with specific target and YAML." --notify

scion message --non-interactive infra-chaos "STANDBY: Battle 1 starting. Target cluster: online-boutique-764d49, namespace: online-boutique-demo. 12 deployments, all single-replica. Your attacks: pod termination, deployment scaling, resource exhaustion. Await attack order." --notify

scion message --non-interactive app-chaos "STANDBY: Battle 1 starting. Target: Cloud Run services in us-west1 (frontend-alt-dev/stage/prod) and GKE deployments in online-boutique-demo. Your attacks: env var corruption, config drift, deployment sabotage. Await attack order." --notify
```

### Step 4: Process recon, select Phase 2 target
When observer-chaos reports back, analyze and decide first target.

## Phase Transitions

| Transition | Condition |
|-----------|-----------|
| Phase 1 → 2 | Recon complete, targets selected, observer baseline established |
| Phase 2 → 3 | Phase 2 attack resolved by SRE OR observer reports detection + 10 min elapsed |
| Phase 3 → 4 | Phase 3 attacks resolved OR >25 min total elapsed |
| Phase 4 → 5 | Hard time limit reached OR all planned attacks executed |
| Any → Abort | Observer reports unsafe condition |

## Dispatching Attacks

### Phase 2: Single-Vector (EGRESS Blind Spot Test)
```bash
scion message --non-interactive network-chaos "ATTACK ORDER — Phase 2:
TARGET: adservice in online-boutique-demo
ATTACK: Apply EGRESS deny NetworkPolicy — blocks all outbound traffic from adservice
YAML:
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: chaos-deny-egress-adservice
  namespace: online-boutique-demo
  labels:
    chaos: 'true'
spec:
  podSelector:
    matchLabels:
      app: adservice
  policyTypes:
  - Egress

EXPECTED IMPACT: adservice cannot reach external dependencies. Ads may fail to load on frontend. Low user impact (ads are non-critical).
ROLLBACK: kubectl delete networkpolicy chaos-deny-egress-adservice -n online-boutique-demo
Execute now and report back immediately." --notify
```

After dispatching, tell observer to start tracking:
```bash
scion message --non-interactive observer-chaos "PHASE 2 ACTIVE: Attack dispatched at $(date -u +%H:%M:%SZ). network-chaos applying EGRESS deny to adservice. Track:
1. TTD — when does the SRE team first mention ad-related issues?
2. Monitor SRE agent activity for any response
3. Check if alerts fire (they shouldn't — no notification channels)
4. Report every 3 minutes with status." --notify
```

### Phase 3: Compound Attack
```bash
# Primary: NetworkPolicy deny-ingress on productcatalogservice
scion message --non-interactive network-chaos "ATTACK ORDER — Phase 3 Primary:
TARGET: productcatalogservice in online-boutique-demo
ATTACK: Apply INGRESS deny NetworkPolicy — blocks all inbound traffic to productcatalogservice
YAML:
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: chaos-deny-ingress-productcatalog
  namespace: online-boutique-demo
  labels:
    chaos: 'true'
spec:
  podSelector:
    matchLabels:
      app: productcatalogservice
  policyTypes:
  - Ingress

EXPECTED IMPACT: Product catalog unavailable. Frontend shows empty product list or errors. Affects browse experience but not cart/checkout.
ROLLBACK: kubectl delete networkpolicy chaos-deny-ingress-productcatalog -n online-boutique-demo
Execute now." --notify

# Secondary: env var corruption on a GKE deployment
scion message --non-interactive app-chaos "ATTACK ORDER — Phase 3 Secondary:
TARGET: currencyservice deployment in online-boutique-demo
ATTACK: Set PORT env var to invalid value
COMMAND: kubectl set env deployment/currencyservice -n online-boutique-demo PORT=CHAOS_INVALID_9999
EXPECTED IMPACT: currencyservice will crash or serve errors. Price display may break on frontend.
ROLLBACK: kubectl set env deployment/currencyservice -n online-boutique-demo PORT=7000
Record pre-attack state first. Execute now." --notify
```

### Phase 4: Multi-Vector Advanced
```bash
# Vector 1: EGRESS deny on checkoutservice (breaks payment flow)
scion message --non-interactive network-chaos "ATTACK ORDER — Phase 4 Vector 1:
TARGET: checkoutservice in online-boutique-demo
ATTACK: Apply EGRESS deny — checkoutservice cannot reach paymentservice, shippingservice, emailservice
YAML:
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: chaos-deny-egress-checkout
  namespace: online-boutique-demo
  labels:
    chaos: 'true'
spec:
  podSelector:
    matchLabels:
      app: checkoutservice
  policyTypes:
  - Egress

EXPECTED IMPACT: Checkout is completely broken. Users can browse and add to cart but cannot complete purchase.
ROLLBACK: kubectl delete networkpolicy chaos-deny-egress-checkout -n online-boutique-demo
Execute now." --notify

# Vector 2: Pod kill on a service the SRE team is likely investigating
scion message --non-interactive infra-chaos "ATTACK ORDER — Phase 4 Vector 2:
TARGET: redis-cart pod in online-boutique-demo
ATTACK: Delete the redis-cart pod
COMMAND: kubectl delete pod -n online-boutique-demo -l app=redis-cart
EXPECTED IMPACT: Cart data lost (EmptyDir storage). Cart service errors until pod restarts. Adds confusion — is the checkout failure from network or cart?
ROLLBACK: Pod auto-recreates via deployment. Verify: kubectl get pods -n online-boutique-demo -l app=redis-cart
Execute 3 minutes after Vector 1." --notify

# Vector 3: Cloud Run config corruption
scion message --non-interactive app-chaos "ATTACK ORDER — Phase 4 Vector 3:
TARGET: frontend-alt-dev Cloud Run service
ATTACK: Corrupt CYMBAL_BRANDING env var
COMMAND: gcloud run services update frontend-alt-dev --update-env-vars=CYMBAL_BRANDING=CHAOS_CORRUPTED --region=us-west1 --project=boutique-demo-22
EXPECTED IMPACT: Dev frontend branding broken. Low impact but tests Cloud Run monitoring.
ROLLBACK: gcloud run services update frontend-alt-dev --update-env-vars=CYMBAL_BRANDING=true --region=us-west1 --project=boutique-demo-22
Execute 5 minutes after Vector 1." --notify
```

## Observer Check-Ins

Request updates from observer-chaos at regular intervals:
```bash
scion message --non-interactive observer-chaos "STATUS REQUEST: Report current TTD/TTDIAG for all active attacks. What is the SRE team doing right now? Recommend: continue, escalate, hold, or abort?" --notify
```

## Escalation Decision Tree

```
IF observer reports SRE detected in <2 min:
  → SRE is alert — target their blind spots (EGRESS, silent alerting)
  → Advance to next phase early

IF observer reports SRE NOT detected after 10 min:
  → Stealth is working — hold current phase, let the clock run
  → Add a subtle second vector in the same domain

IF observer reports SRE diagnosed correctly:
  → Switch to a different domain for next attack
  → Consider targeting the remediation path itself

IF observer reports SRE misdiagnosed:
  → Add misleading symptoms
  → Stack failures that look related but have different root causes

IF observer reports unsafe condition:
  → ABORT — message all agents to rollback immediately
```

## Emergency Abort Protocol

```bash
scion message --non-interactive infra-chaos "ABORT: Rollback all active attacks immediately. Report completion." --notify
scion message --non-interactive network-chaos "ABORT: Delete ALL chaos-labeled NetworkPolicies immediately: kubectl delete networkpolicy -n online-boutique-demo -l chaos=true. Delete all chaos-prefixed firewall rules. Report completion." --notify
scion message --non-interactive app-chaos "ABORT: Restore all original configurations immediately. Report completion." --notify
scion message --non-interactive observer-chaos "ABORT TRIGGERED: Record final timestamps. Prepare emergency debrief." --notify
```

## Post-Exercise (Phase 5)

1. Order all agents to rollback all remaining attacks
2. Request final debrief from observer-chaos
3. Verify all chaos artifacts cleaned up
4. Calculate final scores
5. Write debrief to `/scion-volumes/scratchpad/battle-1-debrief.md`
6. Message results to any requesting agent/user via scion
