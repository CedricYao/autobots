---
name: vpc-networking
description: >-
  VPC networking expertise: VPC architecture, firewall rule management, VPC
  Access connector operations, connectivity testing, cross-region networking,
  network security auditing, and flow log analysis for boutique-demo-22.
---

# VPC Networking Operations

## View Commands (READ — safe at any time)

### VPC Architecture
```bash
# List VPC networks
gcloud compute networks list --project=boutique-demo-22 --format="table(name,autoCreateSubnetworks,routingConfig.routingMode)"

# List subnets
gcloud compute networks subnets list --project=boutique-demo-22 --format="table(name,region,ipCidrRange,network,purpose)"

# Describe specific subnet
gcloud compute networks subnets describe SUBNET_NAME --region=REGION --project=boutique-demo-22 --format=yaml
```

### Firewall Rules
```bash
# List all firewall rules
gcloud compute firewall-rules list --project=boutique-demo-22 --format="table(name,network,direction,priority,sourceRanges,destinationRanges,allowed,targetServiceAccounts,targetTags)"

# Describe specific rule (full details)
gcloud compute firewall-rules describe RULE_NAME --project=boutique-demo-22 --format=yaml

# Find overly-permissive rules (source 0.0.0.0/0)
gcloud compute firewall-rules list --project=boutique-demo-22 --filter="sourceRanges=0.0.0.0/0" --format="table(name,priority,allowed,direction)"
```

### VPC Access Connectors
```bash
# List connectors
gcloud compute networks vpc-access connectors list --region=us-west1 --project=boutique-demo-22 --format="table(name,state,network,machineType,minInstances,maxInstances)"

# Describe connector (full config)
gcloud compute networks vpc-access connectors describe west1-default --region=us-west1 --project=boutique-demo-22 --format=yaml

# Connector metrics (MQL)
fetch vpc_access_connector
| metric 'vpcaccess.googleapis.com/connector/sent_bytes_count'
| filter resource.project_id == 'boutique-demo-22'
| align rate(1m)

fetch vpc_access_connector
| metric 'vpcaccess.googleapis.com/connector/received_bytes_count'
| filter resource.project_id == 'boutique-demo-22'
| align rate(1m)
```

### Routes
```bash
# List routes
gcloud compute routes list --project=boutique-demo-22 --format="table(name,network,destRange,nextHopType,nextHopIp,priority)"
```

### Connectivity Testing
```bash
# Create connectivity test
gcloud network-management connectivity-tests create TEST_NAME --source-instance=SOURCE --destination-ip-address=10.23.0.10 --destination-port=80 --protocol=TCP --project=boutique-demo-22

# Describe test result
gcloud network-management connectivity-tests describe TEST_NAME --project=boutique-demo-22 --format=yaml
```

### Forwarding Rules (VIP investigation)
```bash
# List forwarding rules (looking for VIP 10.23.0.10)
gcloud compute forwarding-rules list --project=boutique-demo-22 --format="table(name,IPAddress,target,region,loadBalancingScheme)"

# Filter by specific IP
gcloud compute forwarding-rules list --filter="IPAddress=10.23.0.10" --project=boutique-demo-22 --format=yaml
```

### Flow Logs
```bash
# Read VPC flow logs (if enabled)
gcloud logging read 'resource.type="gce_subnetwork" AND logName="projects/boutique-demo-22/logs/compute.googleapis.com%2Fvpc_flows"' --project=boutique-demo-22 --limit=20 --format=json --freshness=1h
```

## Modify Commands (WRITE — require operator access)

### Firewall Rules
```bash
# Create scoped allow rule (replace allow-ilb-permissive)
gcloud compute firewall-rules create allow-connector-to-vip --network=default --allow=tcp:80,tcp:443,tcp:8080 --source-ranges=VPC_CONNECTOR_CIDR --target-tags=backend --priority=900 --project=boutique-demo-22
# Risk: low (adding allow) | Reversible: delete rule

# Delete overly-permissive rule (AFTER replacement is verified)
gcloud compute firewall-rules delete allow-ilb-permissive --project=boutique-demo-22
# Risk: HIGH (could break connectivity if replacement is wrong) | Reversible: recreate
# Approval: REQUIRED — test replacement rule first

# Update firewall rule
gcloud compute firewall-rules update RULE_NAME --source-ranges=NEW_CIDR --project=boutique-demo-22
# Risk: medium | Reversible: update again
```

### VPC Connector Scaling
```bash
# Scale up connector (more instances, bigger machine type)
gcloud compute networks vpc-access connectors update west1-default --region=us-west1 --max-instances=10 --machine-type=e2-standard-4 --project=boutique-demo-22
# Risk: medium (connector restart possible) | Reversible: update again
# Side effects: cost increase, brief connectivity disruption during update

# Note: min/max throughput and machine type changes may require connector recreation
```

### Enable Flow Logs
```bash
# Enable VPC flow logs on a subnet
gcloud compute networks subnets update SUBNET_NAME --region=REGION --enable-flow-logs --flow-sampling=0.5 --metadata=INCLUDE_ALL_METADATA --project=boutique-demo-22
# Risk: low (read-only observation) | Side effects: increased log ingestion cost
```

## Change Records

### Audit Logs
```bash
# Network configuration changes
gcloud logging read 'logName="projects/boutique-demo-22/logs/cloudaudit.googleapis.com%2Factivity" AND protoPayload.serviceName="compute.googleapis.com" AND protoPayload.methodName=~"firewalls|networks|subnetworks|routes"' --project=boutique-demo-22 --limit=20 --format=json --freshness=30d
```
Captures: firewall rule creates/updates/deletes, subnet changes, route changes. Retention: 400 days.

## Alert Signals

### P1 (page immediately)
- **VPC connector NOT READY** — all Cloud Run → backend traffic fails.
- **VIP 10.23.0.10 unreachable for > 1 min** — backend completely unavailable.
- **Cross-region connectivity loss** — us-west1 cannot reach us-central1.

### P2 (alert, investigate within 15 minutes)
- **Connector throughput > 80%** — saturation risk, consider scaling.
- **Cross-region latency > 50ms sustained** — performance degradation.
- **New firewall rule with 0.0.0.0/0 source** — potential security issue.

### P3 (track, business hours)
- **Connector at max instances** — may need higher max or machine upgrade.
- **VPC Flow Logs not enabled** — observability gap.

## Cross-Region Architecture

```
Cloud Run (us-west1) → VPC Connector (west1-default, e2-micro)
    → Default VPC routing → Internal VIP 10.23.0.10 (us-central1)
        → Backend Microservices (GKE?)

Key characteristics:
- Cross-region latency: ~20-30ms baseline (us-west1 ↔ us-central1)
- Single VPC connector shared by ALL Cloud Run services (dev/stage/prod)
- Connector saturation affects ALL environments simultaneously
- VIP backing is currently unknown — needs discovery
```

## Known Issues

### allow-ilb-permissive (CRITICAL)
This firewall rule allows ALL traffic from 0.0.0.0/0. It provides effectively no firewall protection. Remediation:
1. Identify the VPC connector's CIDR range
2. Create replacement rule scoped to that CIDR
3. Verify connectivity with replacement rule active
4. Delete allow-ilb-permissive

### VIP 10.23.0.10 Backing Unknown
No forwarding rule visible in this project. The VIP may be:
- An ILB in a different project (Shared VPC)
- A GKE internal service with an external-facing type
- A manually configured static IP
Discovery required before backend agent can be effective.
