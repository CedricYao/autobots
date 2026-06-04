---
name: infrastructure-attacks
description: >-
  Infrastructure-level chaos attack commands for GKE and Cloud Run targets.
  Includes pod termination, resource exhaustion, SA manipulation, and compute
  disruption with rollback commands for each.
---

# Infrastructure Attacks

## Pod Termination

### Kill Specific Pod
```bash
# Record pre-state
kubectl get pod {pod-name} -n {namespace} -o yaml > /tmp/chaos-pre-pod-{pod-name}.yaml

# Attack
kubectl delete pod {pod-name} -n {namespace}

# Rollback: pod auto-recreates via deployment controller
# Verify:
kubectl get pods -n {namespace} -l app={service} -w
```

### Kill All Pods of a Service
```bash
# Attack
kubectl delete pods -n {namespace} -l app={service}

# Rollback: all pods auto-recreate
# Verify:
kubectl rollout status deployment/{service} -n {namespace}
```

### Scale Deployment to Zero
```bash
# Record current replicas
ORIGINAL=$(kubectl get deployment {deployment} -n {namespace} -o jsonpath='{.spec.replicas}')
echo "Original replicas: $ORIGINAL" > /tmp/chaos-pre-scale-{deployment}.txt

# Attack
kubectl scale deployment {deployment} -n {namespace} --replicas=0

# Rollback
kubectl scale deployment {deployment} -n {namespace} --replicas=$ORIGINAL
```

## Resource Exhaustion

### CPU Stress
```bash
# Deploy stress container in target namespace
kubectl run chaos-cpu-stress -n {namespace} \
  --image=progrium/stress \
  --restart=Never \
  --labels="chaos=true" \
  -- --cpu 4 --timeout 300s

# Rollback
kubectl delete pod chaos-cpu-stress -n {namespace}
```

### Memory Pressure
```bash
# Deploy memory stress
kubectl run chaos-mem-stress -n {namespace} \
  --image=progrium/stress \
  --restart=Never \
  --labels="chaos=true" \
  -- --vm 2 --vm-bytes 512M --timeout 300s

# Rollback
kubectl delete pod chaos-mem-stress -n {namespace}
```

### Resource Limit Manipulation
```bash
# Record original limits
kubectl get deployment {deployment} -n {namespace} \
  -o jsonpath='{.spec.template.spec.containers[0].resources}' > /tmp/chaos-pre-resources-{deployment}.txt

# Attack: set absurdly low memory limit to trigger OOM
kubectl patch deployment {deployment} -n {namespace} \
  --type json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"10Mi"}]'

# Rollback
kubectl patch deployment {deployment} -n {namespace} \
  --type json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"{original-limit}"}]'
```

## Service Account Manipulation

### Revoke Specific Role
```bash
# Record current bindings
gcloud projects get-iam-policy {project} \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:{sa-email}" \
  --format="json" > /tmp/chaos-pre-iam-{sa-name}.json

# Attack
gcloud projects remove-iam-policy-binding {project} \
  --member="serviceAccount:{sa-email}" \
  --role="{role}"

# Rollback
gcloud projects add-iam-policy-binding {project} \
  --member="serviceAccount:{sa-email}" \
  --role="{role}"
```

### Disable Service Account
```bash
# Attack
gcloud iam service-accounts disable {sa-email} --project={project}

# Rollback
gcloud iam service-accounts enable {sa-email} --project={project}
```

## Cloud Run Disruption

### Traffic Split to Old Revision
```bash
# Record current traffic split
gcloud run services describe {service} --region={region} --project={project} \
  --format="yaml(spec.traffic)" > /tmp/chaos-pre-traffic-{service}.yaml

# List revisions to find an old one
gcloud run revisions list --service={service} --region={region} --project={project} \
  --format="table(metadata.name,metadata.creationTimestamp)" --limit=5

# Attack: route all traffic to old revision
gcloud run services update-traffic {service} \
  --to-revisions={old-revision}=100 \
  --region={region} --project={project}

# Rollback
gcloud run services update-traffic {service} \
  --to-latest \
  --region={region} --project={project}
```

### Set Minimum Instances to Zero
```bash
# Record current min instances
gcloud run services describe {service} --region={region} --project={project} \
  --format="value(spec.template.metadata.annotations['autoscaling.knative.dev/minScale'])" > /tmp/chaos-pre-minscale-{service}.txt

# Attack: force cold starts
gcloud run services update {service} \
  --min-instances=0 \
  --region={region} --project={project}

# Rollback
gcloud run services update {service} \
  --min-instances={original-min} \
  --region={region} --project={project}
```

## Emergency Cleanup

```bash
# Delete all chaos-labeled pods
kubectl delete pods --all-namespaces -l chaos=true

# Restore all saved IAM states
for f in /tmp/chaos-pre-iam-*.json; do
  echo "Review and restore: $f"
done

# Re-enable any disabled SAs
# (must be done manually from saved state)
```
