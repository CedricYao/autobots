---
name: cloud-deploy
description: >-
  Cloud Deploy delivery pipelines, target definitions, Skaffold configuration,
  promotion workflow, approval gates, and Cloud Run deployment manifests.
  Use when setting up progressive delivery to GCP.
---

# Cloud Deploy

## Delivery Pipeline

```yaml
# clouddeploy.yaml
apiVersion: deploy.cloud.google.com/v1
kind: DeliveryPipeline
metadata:
  name: APP_NAME
description: "Progressive delivery: dev → staging → prod"
serialPipeline:
  stages:
    - targetId: dev
      profiles: [dev]
    - targetId: staging
      profiles: [staging]
    - targetId: prod
      profiles: [prod]
      strategy:
        canary:
          runtimeConfig:
            cloudRun:
              automaticTrafficControl: true
          canaryDeployment:
            percentages: [25, 50, 75]
            verify: false
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: dev
description: "Development environment"
run:
  location: projects/PROJECT_ID/locations/REGION
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: staging
description: "Staging environment"
run:
  location: projects/PROJECT_ID/locations/REGION
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: prod
description: "Production environment"
requireApproval: true
run:
  location: projects/PROJECT_ID/locations/REGION
```

### Register Pipeline and Targets

```bash
# Apply the pipeline and targets (done once, or via Terraform)
gcloud deploy apply \
  --file=clouddeploy.yaml \
  --region=$REGION \
  --project=$PROJECT_ID
```

## Skaffold Configuration

```yaml
# skaffold.yaml
apiVersion: skaffold/v4beta7
kind: Config
metadata:
  name: APP_NAME
build:
  artifacts:
    - image: app
      docker:
        dockerfile: Dockerfile
manifests:
  rawYaml:
    - cloudrun/service.yaml
deploy:
  cloudrun: {}
profiles:
  - name: dev
    manifests:
      rawYaml:
        - cloudrun/service.yaml
    patches:
      - op: replace
        path: /deploy/cloudrun
        value: {}
  - name: staging
    manifests:
      rawYaml:
        - cloudrun/service.yaml
  - name: prod
    manifests:
      rawYaml:
        - cloudrun/service.yaml
```

## Cloud Run Service Manifest

```yaml
# cloudrun/service.yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: APP_NAME
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "0"
        autoscaling.knative.dev/maxScale: "10"
    spec:
      containerConcurrency: 80
      timeoutSeconds: 300
      containers:
        - image: app
          ports:
            - containerPort: 8080
          resources:
            limits:
              cpu: "1"
              memory: 512Mi
          env:
            - name: PORT
              value: "8080"
          startupProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 0
            periodSeconds: 5
            failureThreshold: 12
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            periodSeconds: 15
```

## Release and Promotion Workflow

### Create a Release (from CI)

```bash
# Create release (triggers deployment to first target: dev)
gcloud deploy releases create "release-${COMMIT_SHA}" \
  --project=$PROJECT_ID \
  --region=$REGION \
  --delivery-pipeline=$SERVICE_NAME \
  --images="app=${AR_REPO}/${SERVICE_NAME}:${COMMIT_SHA}" \
  --skaffold-file=skaffold.yaml
```

### Promote to Next Stage

```bash
# Promote from dev → staging
gcloud deploy releases promote \
  --release="release-${COMMIT_SHA}" \
  --project=$PROJECT_ID \
  --region=$REGION \
  --delivery-pipeline=$SERVICE_NAME

# Promote from staging → prod (requires approval if configured)
gcloud deploy releases promote \
  --release="release-${COMMIT_SHA}" \
  --project=$PROJECT_ID \
  --region=$REGION \
  --delivery-pipeline=$SERVICE_NAME
```

### Approve Production Deployment

```bash
# List pending approvals
gcloud deploy rollouts list \
  --release="release-${COMMIT_SHA}" \
  --delivery-pipeline=$SERVICE_NAME \
  --region=$REGION \
  --project=$PROJECT_ID \
  --filter="approvalState=NEEDS_APPROVAL"

# Approve a rollout
gcloud deploy rollouts approve ROLLOUT_NAME \
  --release="release-${COMMIT_SHA}" \
  --delivery-pipeline=$SERVICE_NAME \
  --region=$REGION \
  --project=$PROJECT_ID
```

### Rollback

```bash
# Roll back to previous release
gcloud deploy targets rollback $TARGET \
  --delivery-pipeline=$SERVICE_NAME \
  --region=$REGION \
  --project=$PROJECT_ID

# Or promote a known-good previous release
gcloud deploy releases promote \
  --release="release-${KNOWN_GOOD_SHA}" \
  --project=$PROJECT_ID \
  --region=$REGION \
  --delivery-pipeline=$SERVICE_NAME
```

## Monitoring Releases

```bash
# View pipeline status
gcloud deploy delivery-pipelines describe $SERVICE_NAME \
  --region=$REGION \
  --project=$PROJECT_ID

# List recent releases
gcloud deploy releases list \
  --delivery-pipeline=$SERVICE_NAME \
  --region=$REGION \
  --project=$PROJECT_ID \
  --limit=10

# View rollout details
gcloud deploy rollouts describe ROLLOUT_NAME \
  --release=RELEASE_NAME \
  --delivery-pipeline=$SERVICE_NAME \
  --region=$REGION \
  --project=$PROJECT_ID
```

## Bootstrap Script Pattern

```bash
#!/usr/bin/env bash
# bootstrap.sh — One-command setup for new GCP projects
set -euo pipefail

echo "=== GCP CI/CD Bootstrap ==="

# Check prerequisites
for cmd in gcloud terraform gh; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd not found"; exit 1; }
done

# Get configuration
PROJECT_ID="${GCP_PROJECT_ID:-}"
REGION="${GCP_REGION:-us-central1}"
REPO="${GITHUB_REPOSITORY:-}"

if [ -z "$PROJECT_ID" ]; then
  read -rp "GCP Project ID: " PROJECT_ID
fi
if [ -z "$REPO" ]; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  if [ -z "$REPO" ]; then
    read -rp "GitHub repo (owner/name): " REPO
  fi
fi

REPO_OWNER="${REPO%%/*}"
REPO_NAME="${REPO##*/}"
SERVICE_NAME="${SERVICE_NAME:-$REPO_NAME}"

echo ""
echo "Configuration:"
echo "  GCP Project:  $PROJECT_ID"
echo "  Region:       $REGION"
echo "  GitHub Repo:  $REPO"
echo "  Service:      $SERVICE_NAME"
echo ""
read -rp "Continue? (y/N) " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || exit 0

# Set active project
gcloud config set project "$PROJECT_ID"

# Enable baseline APIs
echo "Enabling GCP APIs..."
gcloud services enable \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  run.googleapis.com \
  clouddeploy.googleapis.com \
  artifactregistry.googleapis.com

# Create Terraform state bucket
STATE_BUCKET="tf-state-${PROJECT_ID}"
if ! gsutil ls "gs://${STATE_BUCKET}" &>/dev/null; then
  echo "Creating Terraform state bucket..."
  gsutil mb -p "$PROJECT_ID" -l "$REGION" "gs://${STATE_BUCKET}"
  gsutil versioning set on "gs://${STATE_BUCKET}"
fi

# Write terraform.tfvars
cat > terraform/terraform.tfvars <<EOF
project_id   = "${PROJECT_ID}"
region       = "${REGION}"
repo_owner   = "${REPO_OWNER}"
repo_name    = "${REPO_NAME}"
service_name = "${SERVICE_NAME}"
EOF

# Update backend config
sed -i "s/PROJECT_ID/${PROJECT_ID}/g" terraform/versions.tf

# Run Terraform
echo "Provisioning GCP resources..."
cd terraform
terraform init
terraform apply -auto-approve
cd ..

# Set GitHub repository variables from Terraform outputs
echo "Configuring GitHub repository variables..."
cd terraform
gh variable set GCP_PROJECT_ID --body "$PROJECT_ID" --repo "$REPO"
gh variable set GCP_REGION --body "$REGION" --repo "$REPO"
gh variable set SERVICE_NAME --body "$SERVICE_NAME" --repo "$REPO"
gh variable set WIF_PROVIDER --body "$(terraform output -raw wif_provider)" --repo "$REPO"
gh variable set WIF_SERVICE_ACCOUNT --body "$(terraform output -raw wif_service_account)" --repo "$REPO"
gh variable set AR_REPO --body "$(terraform output -raw artifact_registry_repo)" --repo "$REPO"
cd ..

# Apply Cloud Deploy pipeline
echo "Setting up Cloud Deploy pipeline..."
sed -e "s/PROJECT_ID/${PROJECT_ID}/g" -e "s/REGION/${REGION}/g" -e "s/APP_NAME/${SERVICE_NAME}/g" \
  clouddeploy.yaml | gcloud deploy apply --file=- --region="$REGION" --project="$PROJECT_ID"

echo ""
echo "=== Bootstrap complete ==="
echo "Push to main to trigger your first deployment."
echo ""
echo "Cloud Run URLs:"
terraform -chdir=terraform output -json cloud_run_urls
```
