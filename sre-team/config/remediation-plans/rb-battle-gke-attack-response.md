# Runbook: RB-008 — GKE Backend Attack Response
## Trigger: Anomalous GKE deployment changes or pod behavior detected

### Overview
Respond to attacks targeting the 12 GKE microservices in the online-boutique cluster.

### 8-Vector Quick Scan
```bash
# 1. NetworkPolicies (deny-all injection)
kubectl get networkpolicies -A

# 2. Scale-to-zero
kubectl get deployments -n default -o custom-columns='NAME:.metadata.name,REPLICAS:.spec.replicas'

# 3. CrashLoopBackOff
kubectl get pods -n default --field-selector=status.phase!=Running

# 4. Env var poisoning (check payment service address)
kubectl get deploy paymentservice -n default -o jsonpath='{.spec.template.spec.containers[0].env}' | grep PAYMENT

# 5. Load amplification
kubectl get deploy loadgenerator -n default -o jsonpath='{.spec.template.spec.containers[0].env}' | python3 -c "import json,sys; [print(e['name'],e['value']) for e in json.load(sys.stdin) if e['name'] in ['USERS','RATE']]"

# 6. Rogue pods
kubectl get pods -n default --show-labels

# 7. Init containers (busybox on loadgenerator is LEGITIMATE)
kubectl get pods -n default -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.initContainers[*]}{.name}:{.image}{" "}{end}{"\n"}{end}'

# 8. Unusual replica counts
kubectl get deployments -n default -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas'
```

### Remediation by Attack Type

#### NetworkPolicy Injection
```bash
kubectl delete networkpolicy <policy-name> -n default
```

#### Scale-to-Zero
```bash
kubectl scale deployment <name> -n default --replicas=1
```

#### Env Var Poisoning
```bash
kubectl rollout undo deployment/<name> -n default
# Or patch directly:
kubectl set env deployment/<name> -n default PAYMENT_SERVICE_ADDR=paymentservice:50051
```

#### Load Amplification
```bash
kubectl set env deployment/loadgenerator -n default USERS=10 RATE=1
```

#### Rogue Pod
```bash
kubectl delete pod <rogue-pod-name> -n default
kubectl delete deployment <rogue-deployment> -n default  # if deployment-backed
```

### Known-Good Baseline
- 12 deployments, all with images `v0.10.5`
- loadgenerator: USERS=10, RATE=1
- PAYMENT_SERVICE_ADDR=paymentservice:50051
- All pods: 2/2 containers (app + istio-proxy)
- Busybox init container on loadgenerator is LEGITIMATE (frontend-check)

### Auth Bootstrap (if kubectl not configured)
```bash
# Token-based auth (when gke-gcloud-auth-plugin is not available)
gcloud container clusters get-credentials online-boutique-764d49 \
  --zone us-central1-a --project boutique-demo-22
# If plugin missing, export token manually:
TOKEN=$(gcloud auth print-access-token)
kubectl config set-credentials user --token=$TOKEN
```
Note: Token expires after 1 hour. Auto-refresh required for long-running monitoring.
