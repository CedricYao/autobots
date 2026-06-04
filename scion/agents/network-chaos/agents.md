# Network Chaos Agent — Operational Workflow

## Receiving Attack Orders

You receive attack orders from chaos-strategist via scion message. Each order includes:
- Attack type and target service
- Exact YAML or command to execute
- Expected impact on traffic paths
- Rollback command
- Timing instructions

## Attack Execution Workflow

### Step 1: Record Pre-Attack State

```bash
# Existing NetworkPolicies (should be zero for Battle 1)
kubectl get networkpolicies -n online-boutique-demo -o yaml 2>/dev/null > /tmp/chaos-pre-netpol.yaml

# Target pod status
kubectl get pods -n online-boutique-demo -l app={SERVICE} -o wide

# Verify connectivity to target
kubectl exec -n online-boutique-demo deploy/frontend -- wget -q -O /dev/null -T 5 http://{SERVICE}:{PORT} 2>&1 || echo "connectivity check baseline"
```

### Step 2: Execute Attack

Apply the network disruption as ordered. Use heredoc for NetworkPolicy:

```bash
cat <<'EOF' | kubectl apply -f -
{YAML from attack order}
EOF
```

### Step 3: Report to Strategist

```bash
scion message --non-interactive chaos-strategist "ATTACK REPORT: Type={type}, Target={service}, Namespace=online-boutique-demo, Executed at $(date -u +%H:%M:%SZ). Expected traffic impact: {description}. Rollback: kubectl delete networkpolicy {policy-name} -n online-boutique-demo. Status: active." --notify
```

### Step 4: Monitor Blast Radius

```bash
# Check if other services affected
kubectl get pods -n online-boutique-demo -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount"

# Check events for network errors
kubectl get events -n online-boutique-demo --sort-by=.lastTimestamp | tail -10
```

### Step 5: Rollback (on order or abort)

```bash
# Delete specific policy
kubectl delete networkpolicy {policy-name} -n online-boutique-demo

# OR delete all chaos policies
kubectl delete networkpolicy -n online-boutique-demo -l chaos=true

scion message --non-interactive chaos-strategist "ROLLBACK COMPLETE: NetworkPolicy {name} deleted from online-boutique-demo. Connectivity verified." --notify
```

## EGRESS Denial Attacks (Battle 1 Primary)

### EGRESS Deny — adservice (Low Impact, Phase 2 calibration)
```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: chaos-deny-egress-adservice
  namespace: online-boutique-demo
  labels:
    chaos: "true"
spec:
  podSelector:
    matchLabels:
      app: adservice
  policyTypes:
  - Egress
EOF

# Rollback:
kubectl delete networkpolicy chaos-deny-egress-adservice -n online-boutique-demo
```

### EGRESS Deny — checkoutservice (High Impact, Phase 4)
```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: chaos-deny-egress-checkout
  namespace: online-boutique-demo
  labels:
    chaos: "true"
spec:
  podSelector:
    matchLabels:
      app: checkoutservice
  policyTypes:
  - Egress
EOF

# Rollback:
kubectl delete networkpolicy chaos-deny-egress-checkout -n online-boutique-demo
```

### EGRESS Deny — cartservice (Medium Impact)
```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: chaos-deny-egress-cartservice
  namespace: online-boutique-demo
  labels:
    chaos: "true"
spec:
  podSelector:
    matchLabels:
      app: cartservice
  policyTypes:
  - Egress
EOF

# Rollback:
kubectl delete networkpolicy chaos-deny-egress-cartservice -n online-boutique-demo
```

## INGRESS Denial Attacks

### INGRESS Deny — productcatalogservice (Medium Impact, Phase 3)
```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: chaos-deny-ingress-productcatalog
  namespace: online-boutique-demo
  labels:
    chaos: "true"
spec:
  podSelector:
    matchLabels:
      app: productcatalogservice
  policyTypes:
  - Ingress
EOF

# Rollback:
kubectl delete networkpolicy chaos-deny-ingress-productcatalog -n online-boutique-demo
```

## Firewall Rule Attacks

### Block VPC Connector Traffic
```bash
gcloud compute firewall-rules create chaos-block-connector \
  --network=default \
  --action=DENY \
  --rules=tcp \
  --source-ranges=10.22.0.0/28 \
  --priority=100 \
  --project=boutique-demo-22

# Rollback:
gcloud compute firewall-rules delete chaos-block-connector --project=boutique-demo-22 --quiet
```

## Emergency Cleanup

```bash
# Delete ALL chaos NetworkPolicies
kubectl delete networkpolicy -n online-boutique-demo -l chaos=true

# Delete ALL chaos firewall rules
for rule in $(gcloud compute firewall-rules list --filter="name~^chaos-" --format="value(name)" --project=boutique-demo-22 2>/dev/null); do
  gcloud compute firewall-rules delete "$rule" --project=boutique-demo-22 --quiet
done
```

## Coordination
- **chaos-strategist** — all orders come from them, all reports go to them
- **observer-chaos** — may request attack timing details
- **infra-chaos, app-chaos** — coordinate timing for compound attacks when ordered
