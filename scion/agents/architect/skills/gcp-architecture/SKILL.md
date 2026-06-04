---
name: gcp-architecture
description: >-
  GCP service selection, reference architectures, and Well-Architected patterns.
  Use when recommending GCP services for a workload, evaluating cost/performance
  trade-offs, or designing cloud-native architectures on Google Cloud.
---

# GCP Architecture

Guide for selecting and composing GCP services into well-architected systems.

## Service Selection Decision Tree

### Compute

| Need | Service | When to Use | When NOT to Use |
|------|---------|-------------|-----------------|
| Stateless HTTP/gRPC | **Cloud Run** | Event-driven, scale-to-zero, per-request billing | Long-running processes, GPUs, stateful workloads |
| Container orchestration | **GKE Autopilot** | Complex multi-service, custom networking, stateful sets | Simple services (use Cloud Run), small teams |
| GKE with full control | **GKE Standard** | GPU workloads, custom node pools, DaemonSets | If Autopilot covers your needs (it usually does) |
| Background jobs | **Cloud Run Jobs** | Batch processing, scheduled tasks, migrations | Real-time processing, sub-second scheduling |
| Serverless functions | **Cloud Functions** | Single-purpose event handlers, webhooks | Complex applications (use Cloud Run instead) |

### Data

| Need | Service | When to Use |
|------|---------|-------------|
| Relational (PostgreSQL) | **AlloyDB** | High-performance OLTP, AI/ML integration, large datasets |
| Relational (standard) | **Cloud SQL** | Standard web app databases, managed PostgreSQL/MySQL |
| Document/NoSQL | **Firestore** | Mobile/web app data, real-time sync, offline support |
| Analytics | **BigQuery** | Data warehousing, analytics, ML on structured data |
| Cache | **Memorystore** | Redis/Memcached for session state, caching |
| Object storage | **Cloud Storage** | Files, backups, static assets, data lake |

### Messaging & Integration

| Need | Service | When to Use |
|------|---------|-------------|
| Async messaging | **Pub/Sub** | Event-driven, decoupled services, at-least-once delivery |
| Task queues | **Cloud Tasks** | Delayed execution, rate limiting, retries |
| Workflows | **Workflows** | Multi-step orchestration, service chaining |
| API gateway | **API Gateway / Apigee** | External API management, rate limiting, auth |

### CI/CD & Operations

| Need | Service | When to Use |
|------|---------|-------------|
| Container CI | **Cloud Build** | Docker builds, triggered by source repo |
| Progressive delivery | **Cloud Deploy** | Canary, blue-green, approval gates |
| Monitoring | **Cloud Monitoring** | Metrics, alerts, dashboards, SLOs |
| Logging | **Cloud Logging** | Centralized logs, structured queries, log-based metrics |
| Tracing | **Cloud Trace** | Distributed trace analysis, latency diagnosis |

### AI/ML

| Need | Service | When to Use |
|------|---------|-------------|
| Foundation models | **Vertex AI (Gemini)** | Text generation, code, multimodal, agents |
| Custom ML training | **Vertex AI Training** | Custom model training, hyperparameter tuning |
| ML serving | **Vertex AI Endpoints** | Model deployment, A/B testing, autoscaling |
| Embeddings + search | **Vertex AI Search** | Semantic search, RAG, grounding |

## Well-Architected Framework Pillars

### Reliability
- Design for failure: every component will fail eventually
- Use managed services to reduce operational burden
- Implement health checks, circuit breakers, retries with backoff
- Define SLOs and error budgets
- Multi-region for critical workloads; single-region with zones for most

### Security
- Least privilege IAM: dedicated service accounts per workload
- Workload Identity for GKE → GCP service authentication
- VPC Service Controls for data exfiltration prevention
- Cloud Armor for DDoS and WAF
- Secret Manager for credentials (never in env vars or code)

### Performance
- Use Cloud CDN for static content
- Right-size compute: start small, scale based on metrics
- Connection pooling for databases
- Use regional resources close to users
- Profile before optimizing: Cloud Profiler, Cloud Trace

### Cost Optimization
- Scale-to-zero with Cloud Run (pay per request)
- Committed Use Discounts for steady-state GKE/Compute
- Lifecycle policies for Cloud Storage (nearline → coldline → archive)
- BigQuery slots vs on-demand: slots for predictable analytics workloads
- Preemptible/Spot VMs for fault-tolerant batch jobs

### Operations
- Infrastructure as Code: Terraform with remote state in GCS
- GitOps: Config Sync or ArgoCD for Kubernetes
- Centralized logging + monitoring from day one
- Runbooks as code: documented procedures, not tribal knowledge
- Incident response automation: alert → agent → mitigate

## Reference Architecture Patterns

### Web Application (typical)
```
Users → Cloud Load Balancer → Cloud Run (frontend)
                                  ├→ Cloud Run (API)
                                  │    ├→ Cloud SQL (PostgreSQL)
                                  │    ├→ Memorystore (Redis)
                                  │    └→ Cloud Storage (uploads)
                                  └→ Cloud CDN (static assets)
```

### Event-Driven Microservices
```
Producers → Pub/Sub → Cloud Run (consumers)
                         ├→ BigQuery (analytics)
                         ├→ Cloud SQL (state)
                         └→ Pub/Sub (downstream events)
```

### ML Pipeline
```
Data sources → Cloud Storage → Vertex AI Pipelines
                                  ├→ Training → Model Registry
                                  └→ Evaluation → Vertex AI Endpoints
                                                       ↑
                                  Cloud Run (serving app) ─┘
```
