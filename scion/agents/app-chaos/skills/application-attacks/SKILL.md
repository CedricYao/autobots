---
name: application-attacks
description: >-
  Application-level chaos attack commands: environment variable corruption,
  ConfigMap manipulation, deployment sabotage, health check disruption,
  and dependency failure injection. Includes rollback for each.
---

# Application Attacks

## Environment Variable Corruption

### Cloud Run Env Var

```bash
# Record original
ORIGINAL=$(gcloud run services describe {service} --region={region} --project={project} \
  --format="value(spec.template.spec.containers[0].env[?(@.name=='{VAR}')].value)")
echo "Original {VAR}=$ORIGINAL" > /tmp/chaos-pre-env-{service}-{VAR}.txt

# Attack: set invalid value
gcloud run services update {service} \
  --update-env-vars="{VAR}=CHAOS_INVALID_VALUE" \
  --region={region} --project={project}

# Rollback
gcloud run services update {service} \
  --update-env-vars="{VAR}=$ORIGINAL" \
  --region={region} --project={project}
```

### GKE Deployment Env Var

```bash
# Record original
ORIGINAL=$(kubectl get deployment {deployment} -n {namespace} \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="{VAR}")].value}')
echo "Original {VAR}=$ORIGINAL" > /tmp/chaos-pre-env-{deployment}-{VAR}.txt

# Attack
kubectl set env deployment/{deployment} -n {namespace} {VAR}=CHAOS_INVALID_VALUE

# Rollback
kubectl set env deployment/{deployment} -n {namespace} {VAR}=$ORIGINAL
```

### Remove Required Env Var

```bash
# Record original
kubectl get deployment {deployment} -n {namespace} \
  -o yaml > /tmp/chaos-pre-deploy-{deployment}.yaml

# Attack: remove the env var entirely
kubectl set env deployment/{deployment} -n {namespace} {VAR}-

# Rollback
kubectl set env deployment/{deployment} -n {namespace} {VAR}={original-value}
```

## ConfigMap Corruption

### Patch a ConfigMap Key

```bash
# Record original
kubectl get configmap {configmap} -n {namespace} -o yaml > /tmp/chaos-pre-cm-{configmap}.yaml

# Attack: corrupt a specific key
kubectl patch configmap {configmap} -n {namespace} \
  --type merge -p '{"data":{"{key}":"chaos-corrupted-value"}}'

# Rollback: restore from saved file
kubectl apply -f /tmp/chaos-pre-cm-{configmap}.yaml
```

### Replace ConfigMap Entirely

```bash
# Record original
kubectl get configmap {configmap} -n {namespace} -o yaml > /tmp/chaos-pre-cm-{configmap}.yaml

# Attack: replace with minimal/empty config
kubectl create configmap {configmap} -n {namespace} \
  --from-literal=chaos=active \
  --dry-run=client -o yaml | kubectl replace -f -

# Rollback
kubectl apply -f /tmp/chaos-pre-cm-{configmap}.yaml
```

## Deployment Sabotage

### Deploy Bad Image (Cloud Run)

```bash
# Record current image
CURRENT_IMAGE=$(gcloud run services describe {service} --region={region} --project={project} \
  --format="value(spec.template.spec.containers[0].image)")
echo "Original image: $CURRENT_IMAGE" > /tmp/chaos-pre-image-{service}.txt

# Attack: deploy a non-existent tag (will fail to pull)
gcloud run deploy {service} \
  --image={registry}/{repo}:chaos-nonexistent-tag \
  --region={region} --project={project}

# Rollback
gcloud run deploy {service} \
  --image=$CURRENT_IMAGE \
  --region={region} --project={project}
```

### Deploy Bad Image (GKE)

```bash
# Record current image
CURRENT_IMAGE=$(kubectl get deployment {deployment} -n {namespace} \
  -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "Original image: $CURRENT_IMAGE" > /tmp/chaos-pre-image-{deployment}.txt

# Attack
kubectl set image deployment/{deployment} -n {namespace} \
  {container}={registry}/{repo}:chaos-nonexistent-tag

# Rollback
kubectl set image deployment/{deployment} -n {namespace} \
  {container}=$CURRENT_IMAGE
```

### Traffic Split Manipulation (Cloud Run)

```bash
# Record current traffic config
gcloud run services describe {service} --region={region} --project={project} \
  --format="yaml(spec.traffic)" > /tmp/chaos-pre-traffic-{service}.yaml

# List available revisions
gcloud run revisions list --service={service} --region={region} --project={project} \
  --format="table(metadata.name,metadata.creationTimestamp)" --sort-by=~metadata.creationTimestamp --limit=5

# Attack: send all traffic to oldest revision
gcloud run services update-traffic {service} \
  --to-revisions={oldest-revision}=100 \
  --region={region} --project={project}

# Rollback
gcloud run services update-traffic {service} \
  --to-latest \
  --region={region} --project={project}
```

## Health Check Disruption

### Change Readiness Probe Path

```bash
# Record original probe
kubectl get deployment {deployment} -n {namespace} \
  -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' > /tmp/chaos-pre-probe-{deployment}.txt

# Attack: point probe to non-existent path
kubectl patch deployment {deployment} -n {namespace} \
  --type json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/chaos-nonexistent-healthz"}]'

# Rollback
kubectl patch deployment {deployment} -n {namespace} \
  --type json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"{original-path}"}]'
```

### Shorten Probe Timeouts

```bash
# Attack: make probes fail by setting impossibly short timeout
kubectl patch deployment {deployment} -n {namespace} \
  --type json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/timeoutSeconds","value":1},{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/periodSeconds","value":1},{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/failureThreshold","value":1}]'

# Rollback: restore from saved deployment
kubectl apply -f /tmp/chaos-pre-deploy-{deployment}.yaml
```

## Dependency Failure Injection

### Redirect Backend URL

```bash
# Attack: point service at non-existent backend
kubectl set env deployment/{deployment} -n {namespace} \
  {BACKEND_URL_VAR}=http://chaos-black-hole:9999

# Rollback
kubectl set env deployment/{deployment} -n {namespace} \
  {BACKEND_URL_VAR}={original-url}
```

### Invalidate API Key

```bash
# Record original
kubectl get secret {secret} -n {namespace} -o yaml > /tmp/chaos-pre-secret-{secret}.yaml

# Attack: replace API key with invalid value
kubectl patch secret {secret} -n {namespace} \
  --type merge -p '{"data":{"{key}":"'$(echo -n "CHAOS_INVALID_KEY" | base64)'"}}'

# Rollback
kubectl apply -f /tmp/chaos-pre-secret-{secret}.yaml
```

## Emergency Cleanup

```bash
# Restore all saved pre-attack states
for f in /tmp/chaos-pre-cm-*.yaml /tmp/chaos-pre-deploy-*.yaml /tmp/chaos-pre-secret-*.yaml; do
  if [ -f "$f" ]; then
    echo "Restoring: $f"
    kubectl apply -f "$f" 2>/dev/null
  fi
done

# Restore Cloud Run services from saved traffic configs
for f in /tmp/chaos-pre-traffic-*.yaml; do
  if [ -f "$f" ]; then
    SERVICE=$(echo "$f" | sed 's|.*chaos-pre-traffic-\(.*\)\.yaml|\1|')
    echo "Restoring traffic for: $SERVICE"
    gcloud run services update-traffic "$SERVICE" --to-latest --region={region} --project={project}
  fi
done

# Restore Cloud Run env vars from saved files
for f in /tmp/chaos-pre-env-*-*.txt; do
  if [ -f "$f" ]; then
    echo "Review and restore: $f"
    cat "$f"
  fi
done
```
