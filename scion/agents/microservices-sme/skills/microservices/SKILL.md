---
name: microservices
description: >-
  Backend microservices expertise: kubectl operations, GKE cluster management,
  gRPC debugging, container diagnostics, resource tuning, service dependency
  mapping, Istio/ASM operations, and Online Boutique service graph for
  boutique-demo-22.
---

# Backend Microservices Operations

## View Commands (READ — safe at any time)

### Cluster & Node Status
```bash
# List GKE clusters
gcloud container clusters list --project=boutique-demo-22 --format="table(name,location,status,currentNodeCount,currentMasterVersion)"

# Get cluster credentials
gcloud container clusters get-credentials CLUSTER_NAME --region=REGION --project=boutique-demo-22

# Node status
kubectl get nodes -o wide
kubectl describe node NODE_NAME
kubectl top nodes
```

### Pod Status
```bash
# All pods in namespace
kubectl get pods -n online-boutique-demo -o wide

# Pods sorted by restart count (find crashers)
kubectl get pods -n online-boutique-demo --sort-by='.status.containerStatuses[0].restartCount'

# Pod details (events, conditions, containers)
kubectl describe pod POD_NAME -n online-boutique-demo

# Pod resource usage
kubectl top pods -n online-boutique-demo --sort-by=cpu
kubectl top pods -n online-boutique-demo --sort-by=memory
```

### Service & Deployment Status
```bash
# Services (endpoints, ports, type)
kubectl get services -n online-boutique-demo -o wide

# Deployments (desired vs ready replicas)
kubectl get deployments -n online-boutique-demo

# Deployment details
kubectl describe deployment SERVICE_NAME -n online-boutique-demo

# Rollout history
kubectl rollout history deployment/SERVICE_NAME -n online-boutique-demo
kubectl rollout status deployment/SERVICE_NAME -n online-boutique-demo
```

### HPA (Horizontal Pod Autoscaler)
```bash
# List HPAs
kubectl get hpa -n online-boutique-demo

# HPA details (current vs target metrics)
kubectl describe hpa SERVICE_NAME -n online-boutique-demo
```

### Events
```bash
# Recent events (sorted by time)
kubectl get events -n online-boutique-demo --sort-by='.lastTimestamp' | tail -30

# Events for specific pod
kubectl get events -n online-boutique-demo --field-selector involvedObject.name=POD_NAME

# Warning events only
kubectl get events -n online-boutique-demo --field-selector type=Warning --sort-by='.lastTimestamp'
```

### Logs
```bash
# Current pod logs
kubectl logs POD_NAME -n online-boutique-demo --tail=100

# Previous container logs (after crash)
kubectl logs POD_NAME -n online-boutique-demo --previous --tail=100

# Logs by label (all pods of a service)
kubectl logs -l app=SERVICE_NAME -n online-boutique-demo --tail=50

# Container-specific logs (multi-container pods, e.g., with Istio sidecar)
kubectl logs POD_NAME -c SERVICE_NAME -n online-boutique-demo --tail=100

# Cloud Logging (longer retention)
gcloud logging read 'resource.type="k8s_container" AND resource.labels.namespace_name="online-boutique-demo" AND resource.labels.container_name="SERVICE_NAME" AND severity>=ERROR' --project=boutique-demo-22 --limit=50 --format=json --freshness=1h
```

### Service Mesh (Istio/ASM)
```bash
# VirtualServices
kubectl get virtualservices -n online-boutique-demo -o yaml

# DestinationRules
kubectl get destinationrules -n online-boutique-demo -o yaml

# Sidecar proxy status
istioctl proxy-status

# Envoy config dump for a pod
istioctl proxy-config cluster POD_NAME.online-boutique-demo
```

### VIP Investigation
```bash
# Find what backs VIP 10.23.0.10
gcloud compute forwarding-rules list --filter="IPAddress=10.23.0.10" --project=boutique-demo-22 --format=yaml

# Check backend services
gcloud compute backend-services list --project=boutique-demo-22 --format="table(name,backends.group,protocol,healthChecks)"

# Internal load balancer details
gcloud compute forwarding-rules describe FWD_RULE_NAME --region=us-central1 --project=boutique-demo-22 --format=yaml
```

## Modify Commands (WRITE — require operator access)

### Deployment Operations
```bash
# Rollback deployment
kubectl rollout undo deployment/SERVICE_NAME -n online-boutique-demo
# Risk: low | Reversible: undo again

# Scale deployment
kubectl scale deployment/SERVICE_NAME --replicas=N -n online-boutique-demo
# Risk: low | Reversible: scale back

# Restart deployment (rolling)
kubectl rollout restart deployment/SERVICE_NAME -n online-boutique-demo
# Risk: low | Reversible: automatic (new pods replace old)
```

### Resource Tuning
```bash
# Set CPU/memory limits
kubectl set resources deployment/SERVICE_NAME -n online-boutique-demo --requests=cpu=250m,memory=256Mi --limits=cpu=1000m,memory=512Mi
# Risk: medium (affects scheduling) | Reversible: set again

# Update HPA
kubectl autoscale deployment/SERVICE_NAME -n online-boutique-demo --min=2 --max=10 --cpu-percent=70
# Risk: medium | Reversible: update again
```

### Pod Operations
```bash
# Delete unhealthy pod (Kubernetes recreates it)
kubectl delete pod POD_NAME -n online-boutique-demo
# Risk: low | Reversible: automatic recreation

# Exec into pod (debugging)
kubectl exec -it POD_NAME -n online-boutique-demo -- /bin/sh
# Risk: low (read-only actions) | Risk: HIGH (if modifying state)
```

### Emergency
```bash
# Cordon a node (prevent new pods scheduling)
kubectl cordon NODE_NAME
# Risk: medium | Reversible: uncordon

# Drain a node (move all pods off)
kubectl drain NODE_NAME --ignore-daemonsets --delete-emptydir-data
# Risk: HIGH (disrupts pods) | Reversible: uncordon
# Approval: REQUIRED
```

## Change Records

### Kubernetes Events
```bash
kubectl get events -n online-boutique-demo --sort-by='.lastTimestamp'
```
Captures: pod scheduling, scaling, image pull, health check failures. Retention: 1 hour (default).

### Deployment History
```bash
kubectl rollout history deployment/SERVICE_NAME -n online-boutique-demo
```
Captures: revision number, image changes. Limitation: no WHO or WHY.

### Audit Logs
```bash
gcloud logging read 'logName="projects/boutique-demo-22/logs/cloudaudit.googleapis.com%2Factivity" AND protoPayload.serviceName="container.googleapis.com"' --project=boutique-demo-22 --limit=20 --format=json --freshness=7d
```
Captures: GKE API calls (cluster operations). Retention: 400 days.

## Alert Signals

### P1 (page immediately)
- **P1 service CrashLoopBackOff** — checkout, payment, productcatalog, or cart service crashing.
- **VIP 10.23.0.10 unreachable** — all frontend→backend traffic fails.
- **Multiple services down simultaneously** — potential cluster-level issue.

### P2 (alert, investigate within 15 minutes)
- **P2 service CrashLoopBackOff** — ad, currency, or shipping service crashing.
- **Error rate > 1% on any P1 service** — degraded user experience.
- **Pod OOM kills** — memory leak or insufficient limits.
- **HPA at max replicas + latency increasing** — capacity insufficient.

### P3 (track, business hours)
- **P3 service issues** — recommendation or email service.
- **Pod restarts > 3 in 1 hour** — intermittent failure.
- **CPU/memory > 80% sustained** — right-sizing needed.

## Service Dependency Graph

```
frontend (Cloud Run)
  ├── productcatalogservice (gRPC) — product listing/details
  ├── cartservice (gRPC) — cart operations
  ├── recommendationservice (gRPC) → productcatalogservice
  ├── adservice (gRPC) — ad serving
  ├── shippingservice (gRPC) — shipping quotes
  ├── currencyservice (gRPC) — currency conversion
  └── checkoutservice (gRPC)
        ├── productcatalogservice
        ├── cartservice
        ├── shippingservice
        ├── paymentservice (gRPC)
        ├── emailservice (gRPC)
        └── currencyservice
```

### Failure Propagation Analysis
- **productcatalogservice down:** Frontend can't display products. Checkout fails. Recommendations fail. Cascade: most severe.
- **cartservice down:** Cart operations fail. Checkout fails. Cascade: severe.
- **paymentservice down:** Checkout fails at payment step. Cascade: moderate (browsing still works).
- **currencyservice down:** Prices display in wrong currency. Checkout uses wrong prices. Cascade: moderate.
- **emailservice down:** No order confirmations. Cascade: low (order still processes).
- **recommendationservice down:** No recommendations shown. Cascade: low (browsing unaffected).
- **adservice down:** No ads displayed. Cascade: negligible.
