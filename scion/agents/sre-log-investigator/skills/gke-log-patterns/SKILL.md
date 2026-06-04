---
name: gke-log-patterns
description: >-
  Reference patterns for identifying common GKE failure modes through Cloud Logging.
  Use when investigating pod crashes, OOM kills, scheduling failures, or network issues
  on GKE Autopilot clusters.
---

# GKE Log Patterns

Common log signatures for GKE failure modes on the Online Boutique application.

## CrashLoopBackOff

**Log query:**
```
resource.type="k8s_cluster"
jsonPayload.reason="BackOff"
resource.labels.cluster_name="online-boutique-764d49"
```

**What to look for:**
- Container exit codes (exit code 1 = application error, 137 = OOMKilled, 143 = SIGTERM)
- Rapidly increasing restart counts
- Configuration errors in environment variables (e.g., invalid PORT)

## OOMKilled

**Log query:**
```
resource.type="k8s_cluster"
jsonPayload.reason="OOMKilling"
```

**What to look for:**
- Memory limit vs actual usage
- Memory leak patterns (gradual increase before kill)
- Which container in the pod was killed

## Network Connectivity Failures

**Log query (application-level):**
```
resource.type="k8s_container"
resource.labels.namespace_name="online-boutique-demo"
(textPayload=~"connection refused" OR textPayload=~"context deadline exceeded" OR textPayload=~"unavailable")
```

**What to look for:**
- NetworkPolicy blocking ingress (cartservice connectivity scenario)
- DNS resolution failures
- gRPC connection errors between services
- Upstream service call failures propagating downstream

## Latency Issues

**Log query:**
```
resource.type="k8s_container"
resource.labels.namespace_name="online-boutique-demo"
(textPayload=~"deadline exceeded" OR textPayload=~"timeout" OR textPayload=~"slow")
```

**What to look for:**
- CPU throttling indicators
- Increased gRPC call duration
- Cascading timeouts from productcatalogservice to frontend

## Service Dependency Map

For correlating errors across services:

```
frontend -> adservice, productcatalogservice, currencyservice, cartservice, recommendationservice, shippingservice, checkoutservice
checkoutservice -> cartservice, productcatalogservice, currencyservice, shippingservice, paymentservice, emailservice
recommendationservice -> productcatalogservice
```
