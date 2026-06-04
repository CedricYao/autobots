---
name: terraform-gcp
description: >-
  Terraform patterns for GCP: provider config, Workload Identity Federation,
  Cloud Run, Cloud Deploy, Artifact Registry, IAM, tfvars parameterization,
  state management, and module structure. Use when provisioning GCP resources.
---

# Terraform for GCP

## Provider Configuration

```hcl
# versions.tf
terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Remote state in GCS (create bucket manually or via bootstrap)
  backend "gcs" {
    bucket = "tf-state-PROJECT_ID"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
```

## Variables and Parameterization

```hcl
# variables.tf
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "repo_owner" {
  description = "GitHub repository owner (org or user)"
  type        = string
}

variable "repo_name" {
  description = "GitHub repository name"
  type        = string
}

variable "service_name" {
  description = "Name for the Cloud Run service"
  type        = string
  default     = "app"
}

variable "environments" {
  description = "Deployment environments"
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}
```

```hcl
# terraform.tfvars.example (user copies to terraform.tfvars)
project_id  = "my-project-123"
region      = "us-central1"
repo_owner  = "my-org"
repo_name   = "my-app"
service_name = "my-app"
```

## Workload Identity Federation

```hcl
# wif.tf — Keyless GitHub Actions → GCP auth

# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# WIF pool
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  description               = "WIF pool for GitHub Actions OIDC"

  depends_on = [google_project_service.apis]
}

# WIF provider (GitHub OIDC)
resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository == '${var.repo_owner}/${var.repo_name}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Service account for GitHub Actions
resource "google_service_account" "github_actions" {
  account_id   = "github-actions"
  display_name = "GitHub Actions (WIF)"
  description  = "Used by GitHub Actions via Workload Identity Federation"
}

# Allow GitHub Actions to impersonate the service account
resource "google_service_account_iam_member" "wif_binding" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.repo_owner}/${var.repo_name}"
}
```

## Artifact Registry

```hcl
resource "google_project_service" "artifactregistry" {
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "app" {
  location      = var.region
  repository_id = var.service_name
  format        = "DOCKER"
  description   = "Docker images for ${var.service_name}"

  depends_on = [google_project_service.artifactregistry]
}

# Grant GitHub Actions SA permission to push images
resource "google_artifact_registry_repository_iam_member" "github_push" {
  location   = google_artifact_registry_repository.app.location
  repository = google_artifact_registry_repository.app.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.github_actions.email}"
}
```

## Cloud Run

```hcl
resource "google_project_service" "run" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

# Cloud Run service (initial deployment — Cloud Deploy manages updates)
resource "google_cloud_run_v2_service" "app" {
  for_each = toset(var.environments)

  name     = "${var.service_name}-${each.value}"
  location = var.region

  template {
    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.service_name}/${var.service_name}:latest"

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }

    scaling {
      min_instance_count = each.value == "prod" ? 1 : 0
      max_instance_count = each.value == "prod" ? 10 : 3
    }
  }

  depends_on = [google_project_service.run]

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,  # Managed by Cloud Deploy
    ]
  }
}

# Allow unauthenticated access (for public APIs — remove for internal)
resource "google_cloud_run_v2_service_iam_member" "public" {
  for_each = toset(var.environments)

  name     = google_cloud_run_v2_service.app[each.value].name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}
```

## Cloud Deploy

```hcl
resource "google_project_service" "deploy" {
  service            = "clouddeploy.googleapis.com"
  disable_on_destroy = false
}

# Grant GitHub Actions SA permission to create releases
resource "google_project_iam_member" "deploy_releaser" {
  project = var.project_id
  role    = "roles/clouddeploy.releaser"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Grant Cloud Deploy SA permission to deploy to Cloud Run
resource "google_project_iam_member" "deploy_runner" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

# Grant Cloud Deploy SA permission to act as the compute SA
resource "google_project_iam_member" "deploy_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

data "google_project" "project" {}
```

## Outputs

```hcl
# outputs.tf — values needed by GitHub Actions and bootstrap
output "wif_provider" {
  description = "WIF provider resource name (for GitHub Actions)"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "wif_service_account" {
  description = "Service account email (for GitHub Actions)"
  value       = google_service_account.github_actions.email
}

output "artifact_registry_repo" {
  description = "Artifact Registry Docker repo URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}"
}

output "cloud_run_urls" {
  description = "Cloud Run service URLs per environment"
  value = {
    for env, svc in google_cloud_run_v2_service.app : env => svc.uri
  }
}
```

## State Management

```hcl
# Option 1: GCS backend (recommended)
terraform {
  backend "gcs" {
    bucket = "tf-state-PROJECT_ID"  # Replace in bootstrap
    prefix = "terraform/state"
  }
}

# Create the state bucket in bootstrap.sh BEFORE terraform init:
# gsutil mb -p $PROJECT_ID -l $REGION gs://tf-state-$PROJECT_ID
# gsutil versioning set on gs://tf-state-$PROJECT_ID
```

## API Enablement Pattern

```hcl
# Enable all required APIs upfront
locals {
  required_apis = [
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "run.googleapis.com",
    "clouddeploy.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
  ]
}

resource "google_project_service" "required" {
  for_each           = toset(local.required_apis)
  service            = each.value
  disable_on_destroy = false
}
```

## IAM Least Privilege

| Role | Who | Why |
|------|-----|-----|
| `roles/artifactregistry.writer` | GitHub Actions SA | Push Docker images |
| `roles/clouddeploy.releaser` | GitHub Actions SA | Create releases |
| `roles/run.developer` | Cloud Deploy SA | Deploy to Cloud Run |
| `roles/iam.serviceAccountUser` | Cloud Deploy SA | Act as compute SA |
| `roles/iam.workloadIdentityUser` | GitHub OIDC principal | Impersonate SA |

Never grant `roles/editor` or `roles/owner` to automation service accounts.
