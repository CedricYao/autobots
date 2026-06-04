---
name: github-actions-gcp
description: >-
  GitHub Actions workflows for GCP: Workload Identity Federation setup, OIDC
  token exchange, gcloud auth, CI/CD triggers, matrix builds, artifact caching,
  and Artifact Registry push. Use when writing GitHub Actions that deploy to GCP.
---

# GitHub Actions for GCP

## Workload Identity Federation (WIF) — Keyless Auth

WIF lets GitHub Actions authenticate to GCP without storing service account keys. The flow:

```
GitHub Actions runner
  → requests OIDC token from GitHub (built-in)
  → exchanges token with GCP STS (Security Token Service)
  → receives short-lived GCP access token
  → authenticates as the bound service account
```

### WIF Authentication Step

```yaml
- name: Authenticate to Google Cloud
  id: auth
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ vars.WIF_PROVIDER }}
    service_account: ${{ vars.WIF_SERVICE_ACCOUNT }}

- name: Set up Cloud SDK
  uses: google-github-actions/setup-gcloud@v2
```

### Required GitHub Repository Variables

Set these via `gh variable set` or GitHub UI → Settings → Variables:

| Variable | Example | Source |
|----------|---------|--------|
| `GCP_PROJECT_ID` | `my-project-123` | User's GCP project |
| `GCP_REGION` | `us-central1` | Deployment region |
| `WIF_PROVIDER` | `projects/123/locations/global/workloadIdentityPools/github/providers/github-actions` | Terraform output |
| `WIF_SERVICE_ACCOUNT` | `github-actions@my-project.iam.gserviceaccount.com` | Terraform output |
| `AR_REPO` | `us-central1-docker.pkg.dev/my-project/app` | Terraform output |

### Required Workflow Permission

```yaml
permissions:
  contents: read
  id-token: write  # Required for OIDC token request
```

## CI Workflow Template

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up language runtime
        uses: actions/setup-node@v4  # or setup-python, setup-go, etc.
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Lint
        run: npm run lint

      - name: Test
        run: npm test

      - name: Build (verify)
        run: npm run build

  docker-build:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v4

      - name: Build Docker image (verify only)
        run: docker build -t app:test .
```

## CD Workflow Template

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: false  # Don't cancel in-progress deployments

permissions:
  contents: read
  id-token: write

env:
  SERVICE_NAME: ${{ vars.SERVICE_NAME || 'app' }}
  REGION: ${{ vars.GCP_REGION || 'us-central1' }}

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production

    steps:
      - uses: actions/checkout@v4

      - name: Authenticate to Google Cloud
        id: auth
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ vars.WIF_PROVIDER }}
          service_account: ${{ vars.WIF_SERVICE_ACCOUNT }}

      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      - name: Configure Docker for Artifact Registry
        run: gcloud auth configure-docker ${{ env.REGION }}-docker.pkg.dev --quiet

      - name: Build and push Docker image
        env:
          IMAGE: ${{ vars.AR_REPO }}/${{ env.SERVICE_NAME }}:${{ github.sha }}
        run: |
          docker build -t $IMAGE .
          docker push $IMAGE

      - name: Create Cloud Deploy release
        env:
          IMAGE: ${{ vars.AR_REPO }}/${{ env.SERVICE_NAME }}:${{ github.sha }}
        run: |
          gcloud deploy releases create release-${{ github.sha }} \
            --project=${{ vars.GCP_PROJECT_ID }} \
            --region=${{ env.REGION }} \
            --delivery-pipeline=${{ env.SERVICE_NAME }} \
            --images=app=$IMAGE \
            --skaffold-file=skaffold.yaml
```

## Artifact Registry Docker Push

```yaml
# Reusable pattern for building and pushing
- name: Configure Docker for AR
  run: gcloud auth configure-docker ${{ env.REGION }}-docker.pkg.dev --quiet

- name: Build and tag
  run: |
    docker build \
      -t ${{ vars.AR_REPO }}/${{ env.SERVICE_NAME }}:${{ github.sha }} \
      -t ${{ vars.AR_REPO }}/${{ env.SERVICE_NAME }}:latest \
      .

- name: Push
  run: |
    docker push ${{ vars.AR_REPO }}/${{ env.SERVICE_NAME }}:${{ github.sha }}
    docker push ${{ vars.AR_REPO }}/${{ env.SERVICE_NAME }}:latest
```

## Caching Patterns

```yaml
# Docker layer caching
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3

- name: Build with cache
  uses: docker/build-push-action@v5
  with:
    context: .
    push: true
    tags: ${{ vars.AR_REPO }}/${{ env.SERVICE_NAME }}:${{ github.sha }}
    cache-from: type=gha
    cache-to: type=gha,mode=max

# Language dependency caching (built into setup-* actions)
- uses: actions/setup-node@v4
  with:
    node-version: '20'
    cache: 'npm'

# Or explicit cache
- uses: actions/cache@v4
  with:
    path: ~/.cache/pip
    key: pip-${{ hashFiles('requirements.txt') }}
```

## Matrix Builds

```yaml
# Test across multiple versions
strategy:
  matrix:
    node-version: [18, 20, 22]
    os: [ubuntu-latest]
steps:
  - uses: actions/setup-node@v4
    with:
      node-version: ${{ matrix.node-version }}
```

## Workflow Security

- **Never** store GCP service account keys in GitHub Secrets — use WIF
- **Always** set `permissions` explicitly — don't rely on defaults
- **Pin** action versions to full SHA or major version (`@v4`, not `@main`)
- **Use** `concurrency` to prevent parallel deployments to the same environment
- **Use** GitHub Environments with protection rules for production deploys
- **Never** echo secrets or tokens in workflow logs
