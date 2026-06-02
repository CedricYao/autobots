#!/bin/bash
# REMEDIATION SCRIPT — Chaos Exercise Attack (Phase 1 + Phase 2)
# Target: frontend-alt-dev (Cloud Run, us-west1, boutique-demo-22)
#
# ATTACK SUMMARY:
#   Phase 1 (23:26Z): Poisoned PRODUCT_CATALOG_SERVICE_ADDR, sabotaged startup probe, injected labels
#   Phase 2 (23:37Z): Stripped roles/run.developer from default compute SA
#                      (258519306384-compute@developer.gserviceaccount.com)
#                      Also: reverted env var poison (covering tracks), created 2 more junk revisions,
#                      but KEPT the startup probe sabotage — denial-of-deploy + denial-of-remediation
#
# CURRENT STATE: Env var is correct again. Startup probe sabotage is the active weapon.
#   3 junk revisions (00052, 00053, 00054) stuck NOT READY.
#   Traffic still on old good revision (frontend-alt-dev-lawi7y9v).
#   Compute SA missing roles/run.developer — Cloud Deploy pipelines to Cloud Run are broken.
#
# Run by: Cedric (project owner) or any roles/owner
# Estimated time: ~2 minutes

set -euo pipefail
PROJECT="boutique-demo-22"
REGION="us-west1"
SERVICE="frontend-alt-dev"

echo "=== Step 0: Restore IAM — re-add roles/run.developer to compute SA ==="
echo "This was stripped at 23:37:46Z to prevent Cloud Run deployments"
COMPUTE_SA="258519306384-compute@developer.gserviceaccount.com"
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/run.developer" \
  --quiet

echo ""
echo "=== Step 1: Remove sabotaged startup probe ==="
echo "Clearing startup probe (failureThreshold=1, periodSeconds=240 → removed)"
gcloud run services update "$SERVICE" \
  --project="$PROJECT" \
  --region="$REGION" \
  --startup-probe=""

echo ""
echo "=== Step 2: Delete junk revisions created by attacker ==="
echo "Removing 3 unauthorized revisions..."
for REV in frontend-alt-dev-00052-mbg frontend-alt-dev-00053-7d2 frontend-alt-dev-00054-wsw; do
  echo "Deleting revision: $REV"
  gcloud run revisions delete "$REV" \
    --project="$PROJECT" \
    --region="$REGION" \
    --quiet 2>/dev/null || echo "  (revision $REV not found or already deleted — OK)"
done

echo ""
echo "=== Step 3: Verify env vars are correct ==="
echo "Confirming PRODUCT_CATALOG_SERVICE_ADDR = 10.23.0.10:3550"
gcloud run services describe "$SERVICE" \
  --project="$PROJECT" \
  --region="$REGION" \
  --format="yaml(spec.template.spec.containers[0].env)"

echo ""
echo "=== Step 4: Verify startup probe cleared ==="
gcloud run services describe "$SERVICE" \
  --project="$PROJECT" \
  --region="$REGION" \
  --format="yaml(spec.template.spec.containers[0].startupProbe)"

echo ""
echo "=== Step 5: Verify traffic routing ==="
gcloud run services describe "$SERVICE" \
  --project="$PROJECT" \
  --region="$REGION" \
  --format="yaml(status.traffic)"

echo ""
echo "=== Step 6: List remaining revisions ==="
gcloud run revisions list \
  --project="$PROJECT" \
  --region="$REGION" \
  --service="$SERVICE" \
  --format="table(name,active,ready,creation_timestamp)"

echo ""
echo "=== Step 7: Verify IAM restored ==="
gcloud projects get-iam-policy "$PROJECT" \
  --flatten="bindings[].members" \
  --filter="bindings.members:258519306384-compute" \
  --format="table(bindings.role)"

echo ""
echo "=== REMEDIATION COMPLETE ==="
echo "Frontend-alt-dev should now be deployable with correct config."
echo "Cloud Deploy pipelines to Cloud Run are restored."
echo ""
echo "Verify service URL:"
SERVICE_URL=$(gcloud run services describe "$SERVICE" --project="$PROJECT" --region="$REGION" --format="value(status.url)")
echo "  curl -s -o /dev/null -w '%{http_code} %{time_total}s' ${SERVICE_URL}/ --max-time 15"
