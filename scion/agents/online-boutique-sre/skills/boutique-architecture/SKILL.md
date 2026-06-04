---
name: boutique-architecture
description: >-
  Architecture reference for the Online Boutique application in boutique-demo-22.
  Use as a quick reference for service dependencies, infrastructure components,
  and known failure modes.
---

# Online Boutique Architecture Reference

## Infrastructure

| Component | Details |
|-----------|---------|
| GCP Project | `boutique-demo-22` |
| GKE Cluster | `online-boutique-764d49` (Autopilot, us-central1, v1.35.3) |
| Namespace | `online-boutique-demo` |
| Service Mesh | Anthos Service Mesh (Istio, managed mode) |
| Production URL | http://34.46.255.20/ |
| Internal VIP | 10.23.0.10 (backend services) |
| Load Generator | Locust, 10 concurrent users |

## Service Dependency Graph

```
External Traffic → 34.46.255.20 (LoadBalancer)
  └→ frontend (Go, port 80)
       ├→ adservice (Java, :9555)
       ├→ productcatalogservice (Go, :3550)
       ├→ currencyservice (Node.js, :7000)
       ├→ cartservice (C#, :7070)
       ├→ recommendationservice (Python, :8080)
       │    └→ productcatalogservice (Go, :3550)
       ├→ shippingservice (Go, :50051)
       └→ checkoutservice (Go, :5050)
            ├→ cartservice (C#, :7070)
            ├→ productcatalogservice (Go, :3550)
            ├→ currencyservice (Node.js, :7000)
            ├→ shippingservice (Go, :50051)
            ├→ paymentservice (Node.js, :50051)
            └→ emailservice (Python, :8080)
```

All inter-service communication uses gRPC.

## Cloud Run Services (Dormant)

| Service | Region | Pipeline |
|---------|--------|----------|
| frontend-alt-dev | us-west1 | alt-frontend-demo |
| frontend-alt-stage | us-west1 | alt-frontend-demo |
| frontend-alt-prod | us-west1 | alt-frontend-demo |

Last deployed December 2022. Connect to backends via VIP 10.23.0.10.

## Observability Posture (Mana 310/700)

| Category | Score | Status |
|----------|-------|--------|
| Metrics | 95/100 | Strong — Istio + K8s + Cloud Monitoring |
| Logs | 85/85 | Excellent — structured JSON, 3 buckets |
| Traces | 20/50 | Weak — API enabled but no data visible |
| Deploy | 15/80 | Critical gap — no CI/CD pipeline for GKE |
| K8s | 40/65 | Moderate — container.developer, auth plugin gap |
| Alerting | 5/25 | Critical gap — 2 policies, zero notification channels |

## Known Failure Scenarios

### 1. Latency Injection
- **Target:** productcatalogservice
- **Mechanism:** CPU throttling + artificial delay
- **Impact:** p95 latency spike cascading to frontend, recommendationservice
- **Remediation:** Rollback productcatalogservice deployment

### 2. Connectivity Block
- **Target:** cartservice
- **Mechanism:** NetworkPolicy blocking ingress
- **Impact:** Cart operations fail, checkout broken
- **Remediation:** Delete offending NetworkPolicy

### 3. Crash Injection
- **Target:** paymentservice
- **Mechanism:** Invalid PORT environment variable
- **Impact:** CrashLoopBackOff, checkout failures
- **Remediation:** Patch PORT env var to correct value

## Alert Policies

| Alert | Condition | Notification |
|-------|-----------|-------------|
| Payment Service Health | restart_count > 0 OR node not Ready | NONE (no channels) |
| Product Catalog Latency | p95 > 1.5s | NONE (no channels) |
