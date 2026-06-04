# Application Chaos Agent — Operational Workflow

## Receiving Attack Orders

You receive attack orders from chaos-strategist via scion message. Each order includes:
- Attack type and target (service, config, deployment)
- Expected impact
- Rollback command with original values
- Timing instructions

## Attack Execution Workflow

### Step 1: Record Pre-Attack State
```bash
# For GKE env vars
kubectl get deployment {SERVICE} -n online-boutique-demo -o jsonpath='{.spec.template.spec.containers[0].env}' > /tmp/chaos-pre-env-{SERVICE}.json

# For Cloud Run env vars
gcloud run services describe {SERVICE} --region=us-west1 --project=boutique-demo-22 \
  --format="yaml(spec.template.spec.containers[0].env)" > /tmp/chaos-pre-env-{SERVICE}.yaml

# For deployment specs
kubectl get deployment {SERVICE} -n online-boutique-demo -o yaml > /tmp/chaos-pre-deploy-{SERVICE}.yaml
```

### Step 2: Execute Attack
Apply the configuration change as ordered.

### Step 3: Report
```bash
scion message --non-interactive chaos-strategist "ATTACK REPORT: Type={type}, Target={service}, Changed: {field} from '{original}' to '{new-value}'. Executed at $(date -u +%H:%M:%SZ). Expected impact: {description}. Rollback: {command}. Status: active." --notify
```

### Step 4: Monitor Effect
```bash
# Check service health
curl -s -o /dev/null -w "%{http_code}" http://34.46.255.20

# Check pod restarts (env var changes trigger rolling update)
kubectl get pods -n online-boutique-demo -l app={SERVICE} -o custom-columns="NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount,STATUS:.status.phase"

# Check for errors in logs
kubectl logs -n online-boutique-demo -l app={SERVICE} --tail=20 2>/dev/null
```

### Step 5: Rollback
```bash
# GKE env var restore
kubectl set env deployment/{SERVICE} -n online-boutique-demo {VAR}={ORIGINAL_VALUE}

# Cloud Run env var restore
gcloud run services update {SERVICE} --update-env-vars={VAR}={ORIGINAL_VALUE} --region=us-west1 --project=boutique-demo-22

scion message --non-interactive chaos-strategist "ROLLBACK COMPLETE: Target={service}, restored '{field}' to original value '{original}'. Verified." --notify
```

## Attack Playbook — boutique-demo-22

### Env Var Corruption — currencyservice (Medium Impact)
```bash
# Record original
kubectl get deployment currencyservice -n online-boutique-demo -o jsonpath='{.spec.template.spec.containers[0].env}' > /tmp/chaos-pre-env-currency.json

# Corrupt PORT
kubectl set env deployment/currencyservice -n online-boutique-demo PORT=CHAOS_INVALID_9999

# Rollback:
kubectl set env deployment/currencyservice -n online-boutique-demo PORT=7000
```

### Env Var Corruption — paymentservice (High Impact, SEV1 Replay)
```bash
# Record original
kubectl get deployment paymentservice -n online-boutique-demo -o jsonpath='{.spec.template.spec.containers[0].env}' > /tmp/chaos-pre-env-payment.json

# Corrupt PORT (replays SEV1 root cause 2)
kubectl set env deployment/paymentservice -n online-boutique-demo PORT=INVALID_PORT

# Rollback:
kubectl set env deployment/paymentservice -n online-boutique-demo PORT=50051
```

### Cloud Run Env Var Corruption (Low Impact)
```bash
# Corrupt branding on dev
gcloud run services update frontend-alt-dev \
  --update-env-vars=CYMBAL_BRANDING=CHAOS_CORRUPTED \
  --region=us-west1 --project=boutique-demo-22

# Rollback:
gcloud run services update frontend-alt-dev \
  --update-env-vars=CYMBAL_BRANDING=true \
  --region=us-west1 --project=boutique-demo-22
```

### Health Check Sabotage (Medium Impact)
```bash
# Change readiness probe to nonexistent path
kubectl patch deployment {SERVICE} -n online-boutique-demo \
  --type json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/chaos-nonexistent-health"}]'

# Rollback:
kubectl patch deployment {SERVICE} -n online-boutique-demo \
  --type json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"{ORIGINAL_PATH}"}]'
```

### Dependency URL Manipulation (Medium Impact)
```bash
# Point backend URL to nonexistent endpoint
kubectl set env deployment/{SERVICE} -n online-boutique-demo \
  {BACKEND_VAR}=http://chaos-nonexistent-service:8080

# Rollback:
kubectl set env deployment/{SERVICE} -n online-boutique-demo \
  {BACKEND_VAR}={ORIGINAL_URL}
```

## Emergency Cleanup
```bash
# Restore all saved pre-attack states
for f in /tmp/chaos-pre-*.yaml; do
  echo "Restoring: $f"
  kubectl apply -f "$f" 2>/dev/null || echo "Not a k8s resource: $f"
done

# Restore Cloud Run services to latest revision
for svc in frontend-alt-dev frontend-alt-stage frontend-alt-prod; do
  gcloud run services update-traffic $svc --to-latest --region=us-west1 --project=boutique-demo-22 2>/dev/null
done
```

## Coordination
- **chaos-strategist** — orders and reports
- **observer-chaos** — may request details about what was changed
- **infra-chaos, network-chaos** — coordinate timing for compound attacks
