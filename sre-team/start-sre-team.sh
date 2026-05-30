#!/bin/bash
set -euo pipefail

echo "============================================"
echo " SRE Team Startup: boutique-demo-22"
echo " Generated: 2026-05-30"
echo " Team size: 9 agents (full team)"
echo "============================================"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verify config files exist
for config in cloud-run-sme cloud-deploy-sme artifact-registry-sme cloud-monitoring-sme vpc-networking-sme iam-sme microservices-sme cloud-storage-sme; do
  if [ ! -f "$SCRIPT_DIR/config/${config}.yaml" ]; then
    echo "ERROR: Missing config file: config/${config}.yaml"
    exit 1
  fi
done
echo "✓ All config files present"
echo ""

# Start agents in priority order (P1 → P4)
echo "--- Starting P1-critical agents ---"

echo "[1/9] Starting vpc-networking-sme (P1-critical)..."
scion start vpc-networking-sme --type vpc-networking-sme --non-interactive
echo "  → VPC, connectors, firewall rules, cross-region architecture"

echo "[2/9] Starting iam-sme (P1-critical)..."
scion start iam-sme --type iam-sme --non-interactive
echo "  → Service accounts, IAM policy, cross-project access"

echo "[3/9] Starting cloud-run-sme (P1-critical)..."
scion start cloud-run-sme --type cloud-run-sme --non-interactive
echo "  → 3 Cloud Run frontend services (dev/stage/prod)"

echo "[4/9] Starting microservices-sme (P1-critical)..."
scion start microservices-sme --type microservices-sme --non-interactive
echo "  → GKE Autopilot cluster, 9 backend services, external LB"

echo ""
echo "--- Starting P2-high agents ---"

echo "[5/9] Starting cloud-deploy-sme (P2-high)..."
scion start cloud-deploy-sme --type cloud-deploy-sme --non-interactive
echo "  → Pipeline alt-frontend-demo, 6 deploy targets"

echo "[6/9] Starting cloud-monitoring-sme (P2-high)..."
scion start cloud-monitoring-sme --type cloud-monitoring-sme --non-interactive
echo "  → Alerting policies, dashboards, observability gaps"

echo "[7/9] Starting sre-expert (P2-high)..."
scion start sre-expert --type sre-expert --non-interactive
echo "  → General SRE advisory, cross-cutting risk coordination"

echo ""
echo "--- Starting P3-medium agents ---"

echo "[8/9] Starting artifact-registry-sme (P3-medium)..."
scion start artifact-registry-sme --type artifact-registry-sme --non-interactive
echo "  → Docker registry, vulnerability scanning, supply chain"

echo ""
echo "--- Starting P4-low agents ---"

echo "[9/9] Starting cloud-storage-sme (P4-low)..."
scion start cloud-storage-sme --type cloud-storage-sme --non-interactive
echo "  → 8 storage buckets, Terraform state, lifecycle policies"

echo ""
echo "============================================"
echo " SRE team started. 9 agents running."
echo "============================================"
echo ""
echo "Run 'scion list --non-interactive' to see agent status."
echo ""
echo "Cross-cutting risks to address first:"
echo "  CRITICAL: allow-ilb-permissive firewall rule (CCR-001)"
echo "  CRITICAL: Single default SA with Editor role (CCR-002)"
echo "  CRITICAL: Cross-project SA privilege escalation (CCR-003)"
echo ""
