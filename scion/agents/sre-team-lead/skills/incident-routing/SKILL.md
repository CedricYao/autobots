---
name: incident-routing
description: >-
  Routing logic for the SRE team lead: maps signals, symptoms, and alert types
  to the correct SME agent(s). Includes routing matrix, escalation patterns,
  and cross-cutting risk routing.
---

# Incident Routing

## Primary Routing Matrix

Route based on the signal type or symptom reported:

### Cloud Run / Frontend Signals

| Signal | Primary SME | Secondary SME(s) | Rationale |
|--------|-------------|-------------------|-----------|
| 502/503 errors on frontend | cloud-run-sme | vpc-networking-sme | Could be service or connectivity |
| High latency on frontend | cloud-run-sme | vpc-networking-sme, microservices-sme | Could be service, connector, or backend |
| Cold start complaints | cloud-run-sme | — | Scaling configuration |
| Service not responding | cloud-run-sme | vpc-networking-sme | Could be service down or network partition |
| Wrong content displayed | cloud-run-sme | cloud-deploy-sme | Bad revision or deploy issue |

### Deployment / Pipeline Signals

| Signal | Primary SME | Secondary SME(s) | Rationale |
|--------|-------------|-------------------|-----------|
| Deploy failed | cloud-deploy-sme | artifact-registry-sme | Pipeline or image issue |
| Release stuck | cloud-deploy-sme | iam-sme | Could be permissions |
| Approval pending too long | cloud-deploy-sme | — | Process issue |
| Render failure | cloud-deploy-sme | — | Skaffold/template issue |
| Post-deploy regression | cloud-deploy-sme | cloud-run-sme | New revision has bugs |

### Networking Signals

| Signal | Primary SME | Secondary SME(s) | Rationale |
|--------|-------------|-------------------|-----------|
| VPC connector saturation | vpc-networking-sme | cloud-run-sme | Affects all frontend services |
| Cross-region latency spike | vpc-networking-sme | cloud-run-sme, microservices-sme | Network path issue |
| Firewall rule change | vpc-networking-sme | iam-sme | Security implications |
| VIP unreachable | vpc-networking-sme | microservices-sme | Backend or routing issue |
| Connectivity test failure | vpc-networking-sme | — | Network path broken |

### IAM / Security Signals

| Signal | Primary SME | Secondary SME(s) | Rationale |
|--------|-------------|-------------------|-----------|
| Unauthorized access detected | iam-sme | cloud-monitoring-sme | Containment + audit |
| SA key leaked | iam-sme | cloud-run-sme, cloud-deploy-sme | Affected services |
| Permission denied errors | iam-sme | (affected service SME) | Missing IAM binding |
| Privilege escalation | iam-sme | cloud-monitoring-sme | Forensic investigation |
| Secret exposure | iam-sme | — | Rotation needed |

### Backend / Microservices Signals

| Signal | Primary SME | Secondary SME(s) | Rationale |
|--------|-------------|-------------------|-----------|
| Pod CrashLoopBackOff | microservices-sme | — | Container issue |
| Service dependency failure | microservices-sme | vpc-networking-sme | Could be network |
| gRPC deadline exceeded | microservices-sme | cloud-monitoring-sme | Latency investigation |
| OOM kills | microservices-sme | — | Resource limits |
| HPA at max | microservices-sme | — | Capacity issue |

### Observability Signals

| Signal | Primary SME | Secondary SME(s) | Rationale |
|--------|-------------|-------------------|-----------|
| Alert not firing | cloud-monitoring-sme | — | Alerting configuration |
| Metric gap | cloud-monitoring-sme | (affected service SME) | Service or config issue |
| Log ingestion spike | cloud-monitoring-sme | — | Cost risk |
| Dashboard blank | cloud-monitoring-sme | — | Metric descriptor issue |
| False positive storm | cloud-monitoring-sme | — | Threshold tuning |

### Supply Chain / Registry Signals

| Signal | Primary SME | Secondary SME(s) | Rationale |
|--------|-------------|-------------------|-----------|
| Critical CVE in deployed image | artifact-registry-sme | cloud-deploy-sme | Rebuild + redeploy |
| Registry unavailable | artifact-registry-sme | cloud-deploy-sme | Blocks deployments |
| Unscanned image deployed | artifact-registry-sme | — | Policy violation |

### Storage Signals

| Signal | Primary SME | Secondary SME(s) | Rationale |
|--------|-------------|-------------------|-----------|
| Pipeline storage error | cloud-storage-sme | cloud-deploy-sme | Pipeline dependency |
| Storage cost spike | cloud-storage-sme | — | Lifecycle policy needed |
| Bucket permission denied | cloud-storage-sme | iam-sme | IAM issue |

## Cross-Cutting Risk Routing

### CCR-001: allow-ilb-permissive

When any signal relates to firewall or network security:

```
1. Route to vpc-networking-sme: "Is this related to allow-ilb-permissive? What is the current rule state?"
2. Route to iam-sme: "What SA scope changes are needed alongside the firewall fix?"
3. Route to cloud-monitoring-sme: "Is there an alert configured for firewall rule changes?"
4. Synthesize remediation plan across all three
```

### CCR-002: Single Default SA

When any signal involves permission errors or SA issues:

```
1. Route to iam-sme: "Is this caused by the single default SA configuration? What's the migration status?"
2. Route to affected service SME: "What SA does your service currently use? What roles does it need?"
3. Track migration progress across all services
```

### CCR-003: Unknown VIP Backing

When any signal involves backend connectivity or VIP 10.23.0.10:

```
1. Route to microservices-sme: "Have you discovered the VIP backing? Run forwarding-rules and cluster discovery."
2. Route to vpc-networking-sme: "What routing exists for 10.23.0.10? Any forwarding rules visible?"
3. This CCR blocks effective backend operations — escalate if undiscovered
```

## Severity Determination

When the severity is ambiguous, use this matrix:

| Factor | SEV1 | SEV2 | SEV3 |
|--------|------|------|------|
| **User impact** | Revenue-affecting, total outage | Major feature degraded | Minor feature, workaround exists |
| **Scope** | All environments | Production only | Stage/dev only |
| **Duration** | > 5 min ongoing | < 5 min or intermittent | Resolved or very intermittent |
| **Data risk** | Data loss or corruption | Stale data | No data impact |
| **Security** | Active breach | Vulnerability discovered | Policy violation |

When in doubt, classify **one level higher** — de-escalation is cheap, missing a real incident is not.

## Dispatch Templates

### SEV1 Incident Dispatch
```
scion message --non-interactive <primary-sme> "SEV1 INCIDENT: [symptom]. Started at [time]. Impact: [who/what affected]. Investigate immediately: [specific questions]. Report findings ASAP." --notify
```

### SEV2 Incident Dispatch
```
scion message --non-interactive <primary-sme> "SEV2 INCIDENT: [symptom]. Impact: [scope]. Investigate: [specific questions]. Report within 15 minutes." --notify
```

### Question Routing
```
scion message --non-interactive <sme> "QUESTION from [requester]: [question]. Provide a structured response: principle, implementation, anti-patterns, what-good-looks-like." --notify
```

### Status Check
```
scion message --non-interactive <sme> "STATUS CHECK: Report current health of your domain. Include: service status, any active issues, CCR progress if applicable." --notify
```

### CCR Progress Check
```
scion message --non-interactive <sme> "CCR UPDATE: Report progress on [CCR-00X]. What has been done? What remains? Any blockers?" --notify
```
