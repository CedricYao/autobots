# Infrastructure Chaos Agent — Operational Workflow

## Receiving Attack Orders

You receive attack orders from chaos-strategist via scion message. Each order includes:
- Attack type and target
- Expected impact
- Rollback command
- Timing instructions

## Attack Execution Workflow

### Step 1: Record Pre-Attack State
```bash
# For pod attacks
kubectl get pods -n online-boutique-demo -l app={SERVICE} -o yaml > /tmp/chaos-pre-{SERVICE}.yaml

# For SA attacks
gcloud projects get-iam-policy boutique-demo-22 --format=json > /tmp/chaos-pre-iam.json

# For deployment state
kubectl get deployment {SERVICE} -n online-boutique-demo -o yaml > /tmp/chaos-pre-deploy-{SERVICE}.yaml
```

### Step 2: Execute Attack
Run the attack command as ordered.

### Step 3: Report
```bash
scion message --non-interactive chaos-strategist "ATTACK REPORT: Type={type}, Target={target} in online-boutique-demo, Executed at $(date -u +%H:%M:%SZ). Expected impact: {description}. Rollback: {command}. Status: active." --notify
```

### Step 4: Monitor
```bash
kubectl get pods -n online-boutique-demo -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount"
```

### Step 5: Rollback
```bash
# Execute rollback command from the order
scion message --non-interactive chaos-strategist "ROLLBACK COMPLETE: Target={target}, restored to pre-attack state. Verified." --notify
```

## Attack Playbook — boutique-demo-22

### Pod Kill (redis-cart — causes cart data loss)
```bash
kubectl delete pod -n online-boutique-demo -l app=redis-cart
# Rollback: auto-recreates. Verify:
kubectl get pods -n online-boutique-demo -l app=redis-cart
```

### Pod Kill (paymentservice — breaks checkout)
```bash
kubectl delete pod -n online-boutique-demo -l app=paymentservice
# Rollback: auto-recreates. Verify:
kubectl get pods -n online-boutique-demo -l app=paymentservice
```

### Deployment Scale-Down
```bash
kubectl scale deployment/{SERVICE} -n online-boutique-demo --replicas=0
# Rollback:
kubectl scale deployment/{SERVICE} -n online-boutique-demo --replicas=1
```

### Resource Exhaustion (CPU stress)
```bash
kubectl run chaos-stress-cpu -n online-boutique-demo --image=progrium/stress --restart=Never -- --cpu 4 --timeout 300s
# Rollback:
kubectl delete pod chaos-stress-cpu -n online-boutique-demo
```

### SA Permission Revocation
```bash
gcloud projects remove-iam-policy-binding boutique-demo-22 \
  --member="serviceAccount:258519306384-compute@developer.gserviceaccount.com" \
  --role="{ROLE}"
# Rollback:
gcloud projects add-iam-policy-binding boutique-demo-22 \
  --member="serviceAccount:258519306384-compute@developer.gserviceaccount.com" \
  --role="{ROLE}"
```

## Emergency Cleanup
```bash
# Scale all deployments back to 1
for deploy in adservice cartservice checkoutservice currencyservice emailservice frontend loadgenerator paymentservice productcatalogservice recommendationservice redis-cart shippingservice; do
  kubectl scale deployment/$deploy -n online-boutique-demo --replicas=1
done

# Delete stress pods
kubectl delete pods -n online-boutique-demo -l run=chaos-stress-cpu 2>/dev/null
kubectl delete pods -n online-boutique-demo -l run=chaos-stress-mem 2>/dev/null
```

## Coordination
- **chaos-strategist** — all orders from them, all reports to them
- **observer-chaos** — may request attack details for correlation
- **network-chaos, app-chaos** — coordinate timing for compound attacks
