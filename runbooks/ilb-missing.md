# Runbook: Missing Internal Load Balancer (VIP 10.23.0.10)

**Runbook ID:** RB-002
**Derived from:** INC-2026-0601-001, Root Cause 1 / CCR-003
**Failure type:** Infrastructure gap — reserved VIP with no forwarding rule or backing service
**Severity when triggered:** SEV1 (total outage for Cloud Run frontend path)
**Last updated:** 2026-06-02
**Owner:** microservices-sme + vpc-networking-sme

---

## Symptoms

| Signal | What You See |
|--------|-------------|
| User-facing | Cloud Run frontends (frontend-alt-dev/stage/prod) return HTTP 500 on ALL pages |
| Cloud Run logs | Backend calls to VIP 10.23.0.10 timeout after 3-20 seconds |
| VPC connector | READY status, but no traffic flowing through |
| GKE frontend | MAY still work (uses ClusterIP routing, bypasses VIP) |
| Blast radius | 100% of Cloud Run frontend traffic; GKE frontend unaffected |

## Architecture Context

```
Cloud Run (us-west1) -> VPC Connector (west1-default) -> Cross-region route
    -> VIP 10.23.0.10 (gke-vip-subnet, us-central1) -> [ILB NEEDED HERE] -> GKE pods
```

The Cloud Run frontend services are configured to route ALL backend gRPC calls through VPC connector `west1-default` to VIP `10.23.0.10`. If no Internal Load Balancer (ILB) serves this VIP, every connection attempt times out silently.

## Detection

### Step 1: Confirm VIP has no forwarding rule (10 seconds)

```bash
gcloud compute forwarding-rules list --project=boutique-demo-22 \
  --filter="IPAddress=10.23.0.10 OR loadBalancingScheme=INTERNAL" \
  --format="table(name,IPAddress,target,loadBalancingScheme)"
```

**Root cause confirmed if:** Empty result or no rule pointing to `10.23.0.10`.

### Step 2: Verify VIP reservation exists (5 seconds)

```bash
gcloud compute addresses list --project=boutique-demo-22 \
  --filter="address=10.23.0.10" \
  --format="table(name,address,purpose,subnetwork,status)"
```

**Expected:** Address `boutique-internal` at `10.23.0.10`, purpose `SHARED_LOADBALANCER_VIP`, status `RESERVED`.

### Step 3: Verify no K8s LoadBalancer Services exist (5 seconds)

```bash
kubectl get svc -n online-boutique-demo -o wide | grep LoadBalancer
```

**Root cause confirmed if:** No services of type `LoadBalancer`, or none targeting `10.23.0.10`.

### Step 4: Verify infrastructure path is healthy (10 seconds)

```bash
# VPC connector status
gcloud compute networks vpc-access connectors describe west1-default \
  --region=us-west1 --project=boutique-demo-22 \
  --format="table(state,machineType,minInstances,maxInstances)"

# Subnet route exists
gcloud compute routes list --project=boutique-demo-22 \
  --filter="destRange:10.23.0.0" \
  --format="table(name,destRange,nextHopNetwork,priority)"

# GKE cluster running
gcloud container clusters list --project=boutique-demo-22 \
  --format="table(name,status,currentNodeCount,currentMasterVersion)"
```

## Remediation

### Option A: Apply ILB Kubernetes Services (recommended)

The validated ILB YAML is maintained at `/workspace/reports/ilb-design-vip-10.23.0.10.yaml`. It creates 9 K8s Services of type `LoadBalancer`, one per backend microservice, all sharing VIP `10.23.0.10` on different ports.

```bash
kubectl apply -f /workspace/reports/ilb-design-vip-10.23.0.10.yaml
```

### Port mapping (VIP 10.23.0.10)

| Service | VIP Port | Target Port | Notes |
|---------|----------|-------------|-------|
| adservice-ilb | 9555 | 9555 | |
| cartservice-ilb | 7070 | 7070 | |
| checkoutservice-ilb | 5050 | 5050 | |
| currencyservice-ilb | 7000 | 7000 | |
| emailservice-ilb | 5000 | 8080 | Port remap |
| paymentservice-ilb | 50052 | 50051 | Port remap (avoids conflict with shippingservice) |
| productcatalogservice-ilb | 3550 | 3550 | |
| recommendationservice-ilb | 8080 | 8080 | |
| shippingservice-ilb | 50051 | 50051 | |

### Verification (mandatory)

ILB provisioning takes 1-3 minutes:

```bash
# 1. Check services have external IPs assigned (should show 10.23.0.10)
kubectl get svc -n online-boutique-demo -l networking.gke.io/load-balancer-type=Internal

# 2. Check forwarding rules now exist
gcloud compute forwarding-rules list --project=boutique-demo-22 \
  --filter="IPAddress=10.23.0.10" \
  --format="table(name,IPAddress,target,loadBalancingScheme)"

# 3. Test Cloud Run frontend connectivity
curl -s -o /dev/null -w "%{http_code} %{time_total}s" \
  https://frontend-alt-prod-HASH-uw.a.run.app/ --max-time 15
```

### Option B: Interim mitigation — redirect users to GKE frontend

If ILB cannot be deployed immediately, the GKE frontend at `34.46.255.20` serves the same application via ClusterIP routing (does not depend on the VIP):

```
GKE frontend working: http://34.46.255.20/
Cloud Run frontend broken: https://frontend-alt-prod-*.run.app/
```

Communicate the GKE URL to affected users as a temporary workaround.

## Escalation

If the SRE team lacks write access:

```
URGENT — ILB missing for VIP 10.23.0.10. Cloud Run frontends completely down.

To fix (2 min), run:
  kubectl apply -f /workspace/reports/ilb-design-vip-10.23.0.10.yaml

Interim mitigation: GKE frontend at http://34.46.255.20/ is serving users.

Alternatively, grant agent write access:
  gcloud projects add-iam-policy-binding boutique-demo-22 \
    --member='serviceAccount:scion-platform-team@deploy-demo-test.iam.gserviceaccount.com' \
    --role='roles/container.developer'
```

## Gotchas

1. **Silent outage:** Cloud Run frontends show zero errors when there's zero traffic. The VPC connector is READY, routes exist, firewall passes — everything looks healthy. The only signal is that backend connections silently time out.
2. **Cross-region latency:** VPC connector is in us-west1, GKE pods in us-central1. Even with a healthy ILB, expect 20-40ms additional latency from cross-region routing.
3. **Shared VIP limitation:** All 9 services share one VIP on different ports. If the VIP goes down, ALL backends are unreachable from Cloud Run simultaneously. This is a known SPOF (CCR-003).
4. **ILB provisioning time:** GKE-provisioned ILBs take 1-3 minutes to become healthy. Don't assume immediate recovery after `kubectl apply`.
5. **allow-ilb-permissive firewall:** The current firewall rule allows 0.0.0.0/0 on all protocols (CCR-001). The ILB will work but is not properly firewalled. Plan scoped firewall rules as a follow-up.

## Related CCRs

| CCR | Relevance |
|-----|-----------|
| CCR-001 | allow-ilb-permissive firewall rule (0.0.0.0/0) — ILB traffic is not properly scoped |
| CCR-003 | VIP 10.23.0.10 has no backing — this runbook addresses the gap |

---

*Source: INC-2026-0601-001 Phase 1, Root Cause 1 — Missing ILB for VIP 10.23.0.10*
