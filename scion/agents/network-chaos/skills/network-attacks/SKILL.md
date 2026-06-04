---
name: network-attacks
description: >-
  Network-level chaos attack commands: NetworkPolicy injection, firewall rule
  manipulation, VPC connector disruption, and latency injection. Includes
  YAML templates and rollback commands.
---

# Network Attacks

## NetworkPolicy Injection

### Deny All Ingress to a Service

Blocks all incoming traffic to the targeted service. Highest-impact single action.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: chaos-deny-ingress-{service}
  namespace: {namespace}
  labels:
    chaos: "true"
    chaos-type: "deny-ingress"
spec:
  podSelector:
    matchLabels:
      app: {service}
  policyTypes:
  - Ingress
EOF

# Rollback
kubectl delete networkpolicy chaos-deny-ingress-{service} -n {namespace}

# Verify rollback
kubectl get networkpolicy -n {namespace} | grep chaos
```

### Deny All Egress from a Service

Blocks outbound traffic — service can receive requests but cannot reach dependencies.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: chaos-deny-egress-{service}
  namespace: {namespace}
  labels:
    chaos: "true"
    chaos-type: "deny-egress"
spec:
  podSelector:
    matchLabels:
      app: {service}
  policyTypes:
  - Egress
EOF

# Rollback
kubectl delete networkpolicy chaos-deny-egress-{service} -n {namespace}
```

### Selective Port Block

Allows some ports but blocks others — creates subtle partial failures.

```bash
# Example: allow HTTP (80) but implicitly block gRPC (50051)
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: chaos-selective-{service}
  namespace: {namespace}
  labels:
    chaos: "true"
    chaos-type: "selective-port"
spec:
  podSelector:
    matchLabels:
      app: {service}
  policyTypes:
  - Ingress
  ingress:
  - ports:
    - port: 80
      protocol: TCP
EOF

# Rollback
kubectl delete networkpolicy chaos-selective-{service} -n {namespace}
```

### Namespace Isolation

Isolate an entire namespace from cross-namespace traffic.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: chaos-isolate-namespace
  namespace: {namespace}
  labels:
    chaos: "true"
    chaos-type: "namespace-isolation"
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector: {}
  egress:
  - to:
    - podSelector: {}
EOF

# Rollback
kubectl delete networkpolicy chaos-isolate-namespace -n {namespace}
```

## Firewall Rule Manipulation

### Insert High-Priority Deny Rule

```bash
# Attack: block specific traffic with highest priority
gcloud compute firewall-rules create chaos-deny-{name} \
  --network={network} \
  --action=DENY \
  --rules=tcp:{port} \
  --source-ranges={source-cidr} \
  --priority=100 \
  --description="Chaos exercise - deny rule" \
  --project={project}

# Rollback
gcloud compute firewall-rules delete chaos-deny-{name} --project={project} --quiet
```

### Block VPC Connector Traffic

```bash
# Identify connector subnet CIDR
CONNECTOR_CIDR=$(gcloud compute networks vpc-access connectors describe {connector} \
  --region={region} --format="value(ipCidrRange)" --project={project})

# Attack: block traffic from connector to backends
gcloud compute firewall-rules create chaos-block-connector \
  --network={network} \
  --action=DENY \
  --rules=all \
  --source-ranges="$CONNECTOR_CIDR" \
  --priority=100 \
  --description="Chaos exercise - block VPC connector" \
  --project={project}

# Rollback
gcloud compute firewall-rules delete chaos-block-connector --project={project} --quiet
```

### Block Inter-Service Communication

```bash
# Block traffic between two specific service CIDRs
gcloud compute firewall-rules create chaos-block-service-{service} \
  --network={network} \
  --action=DENY \
  --rules=tcp:{port} \
  --source-ranges={source-service-cidr} \
  --destination-ranges={dest-service-cidr} \
  --priority=100 \
  --description="Chaos exercise - block inter-service" \
  --project={project}

# Rollback
gcloud compute firewall-rules delete chaos-block-service-{service} --project={project} --quiet
```

## Connectivity Testing

### Verify Attack Impact

```bash
# Test connectivity from within a pod
kubectl exec -n {namespace} {pod} -- curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://{target-service}:{port}/

# Test connectivity from Cloud Run
curl -s -o /dev/null -w "%{http_code}" --max-time 5 {cloud-run-url}

# Check for connection refused vs timeout (different failure modes)
kubectl exec -n {namespace} {pod} -- timeout 5 nc -zv {target-ip} {port} 2>&1
```

### Monitor Network Events

```bash
# Watch for pod connectivity events
kubectl get events --all-namespaces --sort-by=.lastTimestamp --field-selector reason=NetworkNotReady 2>/dev/null

# Check NetworkPolicy enforcement
kubectl get networkpolicy --all-namespaces -o wide
```

## Emergency Cleanup

```bash
# Delete ALL chaos NetworkPolicies across all namespaces
for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
  kubectl delete networkpolicy -n "$ns" -l chaos=true 2>/dev/null
done

# Delete ALL chaos firewall rules
for rule in $(gcloud compute firewall-rules list \
  --filter="name~^chaos-" \
  --format="value(name)" \
  --project={project} 2>/dev/null); do
  echo "Deleting firewall rule: $rule"
  gcloud compute firewall-rules delete "$rule" --project={project} --quiet
done

# Verify cleanup
echo "Remaining chaos NetworkPolicies:"
kubectl get networkpolicy --all-namespaces -l chaos=true 2>/dev/null || echo "None"
echo "Remaining chaos firewall rules:"
gcloud compute firewall-rules list --filter="name~^chaos-" --format="table(name)" --project={project} 2>/dev/null || echo "None"
```
