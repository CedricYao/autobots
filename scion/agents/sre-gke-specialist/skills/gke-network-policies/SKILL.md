---
name: gke-network-policies
description: >-
  Diagnose Kubernetes NetworkPolicy issues affecting service-to-service communication
  in the Online Boutique application. Use when investigating connectivity failures
  between microservices.
---

# GKE Network Policy Diagnostics

Diagnose NetworkPolicy-related connectivity issues in the Online Boutique environment.

## Service Communication Map

All inter-service communication uses gRPC. The expected connectivity:

```
frontend (port 80, LoadBalancer) ← external traffic
  ├→ adservice:9555
  ├→ productcatalogservice:3550
  ├→ currencyservice:7000
  ├→ cartservice:7070
  ├→ recommendationservice:8080
  ├→ shippingservice:50051
  └→ checkoutservice:5050
       ├→ cartservice:7070
       ├→ productcatalogservice:3550
       ├→ currencyservice:7000
       ├→ shippingservice:50051
       ├→ paymentservice:50051
       └→ emailservice:8080

recommendationservice:8080
  └→ productcatalogservice:3550
```

## Diagnosing NetworkPolicy Issues

### 1. List Active Policies
```bash
kubectl get networkpolicy -n online-boutique-demo
kubectl get networkpolicy -n online-boutique-demo -o yaml
```

### 2. Identify Blocking Policies

A NetworkPolicy that blocks cartservice ingress (known failure scenario):
- **Symptom:** Frontend shows "failed to get cart" errors; checkout fails
- **Root cause:** An ingress policy on cartservice denying traffic from frontend/checkoutservice
- **Diagnosis:** Check if cartservice has a NetworkPolicy with a restrictive `ingress` section

```bash
kubectl describe networkpolicy -n online-boutique-demo | grep -A 20 cartservice
```

### 3. Test Connectivity

```bash
# From a debug pod, test if a service is reachable
kubectl run debug-net --rm -it --image=busybox --restart=Never -n online-boutique-demo -- wget -qO- --timeout=5 http://cartservice:7070 2>&1 || echo "Connection failed"
```

### 4. Remediation

```bash
# Delete the offending NetworkPolicy
# Risk: LOW — removing a policy opens traffic, does not block it
kubectl delete networkpolicy POLICY_NAME -n online-boutique-demo
```

## Istio/ASM Interaction

With Anthos Service Mesh active, both Kubernetes NetworkPolicies and Istio AuthorizationPolicies can affect traffic:
- NetworkPolicies operate at L3/L4 (IP/port level)
- Istio AuthorizationPolicies operate at L7 (HTTP/gRPC level)
- A connectivity failure could be caused by either — check both

```bash
# Check Istio authorization policies
kubectl get authorizationpolicy -n online-boutique-demo
kubectl get peerauthentication -n online-boutique-demo
```
