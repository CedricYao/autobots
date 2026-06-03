#!/bin/bash
# =============================================================================
# vpc-connector-rebuild.sh — VPC Serverless Connector Rebuild
# =============================================================================
# Derived from Battle 2 (2026-06-03) where the chaos team poisoned the VPC
# connector (min/max instances set to 0) and then deleted it during restoration,
# causing a ~9 minute connector outage that severed Cloud Run → backend traffic.
#
# This script detects connector issues and rebuilds from known-good config.
#
# Usage:
#   ./vpc-connector-rebuild.sh                    # Check and rebuild if needed
#   ./vpc-connector-rebuild.sh --dry-run          # Check only, no changes
#   ./vpc-connector-rebuild.sh --force            # Force rebuild even if READY
#   ./vpc-connector-rebuild.sh --loop             # Continuous monitoring
#   ./vpc-connector-rebuild.sh --loop --interval 30  # Custom interval
#
# Project: boutique-demo-22
# Connector: west1-default (us-west1)
# =============================================================================

set -uo pipefail

# --- Configuration -----------------------------------------------------------
PROJECT="${PROJECT:-boutique-demo-22}"
REGION="${REGION:-us-west1}"
CONNECTOR_NAME="${CONNECTOR_NAME:-west1-default}"
DRY_RUN=false
FORCE_REBUILD=false
LOOP_MODE=false
INTERVAL="${INTERVAL:-60}"
LOG_PREFIX="[vpc-connector]"

# --- Known-Good Connector Configuration --------------------------------------
# These values define the connector that Cloud Run services depend on.
# Update if the connector spec changes.
CONNECTOR_NETWORK="default"
CONNECTOR_SUBNET="default"
CONNECTOR_MIN_INSTANCES=2
CONNECTOR_MAX_INSTANCES=3
CONNECTOR_MACHINE_TYPE="e2-micro"

# Cloud Run services that use this connector
CLOUD_RUN_SERVICES=(
  "frontend-alt-dev"
  "frontend-alt-stage"
  "frontend-alt-prod"
)

# --- Argument Parsing ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)        DRY_RUN=true; shift ;;
    --force)          FORCE_REBUILD=true; shift ;;
    --loop)           LOOP_MODE=true; shift ;;
    --interval)       INTERVAL="$2"; shift 2 ;;
    --project)        PROJECT="$2"; shift 2 ;;
    --region)         REGION="$2"; shift 2 ;;
    --connector)      CONNECTOR_NAME="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [--force] [--loop] [--interval N]"
      echo "       [--project PROJECT] [--region REGION] [--connector NAME]"
      echo ""
      echo "Known-good connector config:"
      echo "  Name:           $CONNECTOR_NAME"
      echo "  Region:         $REGION"
      echo "  Network:        $CONNECTOR_NETWORK"
      echo "  Min instances:  $CONNECTOR_MIN_INSTANCES"
      echo "  Max instances:  $CONNECTOR_MAX_INSTANCES"
      echo "  Machine type:   $CONNECTOR_MACHINE_TYPE"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Utility Functions --------------------------------------------------------
log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $LOG_PREFIX $*"
}

# --- Core Functions -----------------------------------------------------------

get_connector_status() {
  gcloud compute networks vpc-access connectors describe "$CONNECTOR_NAME" \
    --project="$PROJECT" \
    --region="$REGION" \
    --format="value(state)" 2>/dev/null
}

get_connector_details() {
  gcloud compute networks vpc-access connectors describe "$CONNECTOR_NAME" \
    --project="$PROJECT" \
    --region="$REGION" \
    --format="json(state,minInstances,maxInstances,machineType,network,subnet)" 2>/dev/null
}

delete_connector() {
  log "Deleting connector $CONNECTOR_NAME..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY-RUN: would delete connector $CONNECTOR_NAME"
    return 0
  fi

  gcloud compute networks vpc-access connectors delete "$CONNECTOR_NAME" \
    --project="$PROJECT" \
    --region="$REGION" \
    --quiet 2>&1 | while IFS= read -r line; do log "  $line"; done

  # Wait for deletion to complete
  local wait_count=0
  while gcloud compute networks vpc-access connectors describe "$CONNECTOR_NAME" \
    --project="$PROJECT" --region="$REGION" &>/dev/null; do
    ((wait_count++))
    if [[ $wait_count -ge 30 ]]; then
      log "ERROR: Connector deletion timed out after 60s"
      return 1
    fi
    log "  Waiting for deletion to complete... (${wait_count}/30)"
    sleep 2
  done
  log "Connector deleted successfully"
}

create_connector() {
  log "Creating connector $CONNECTOR_NAME with known-good config..."
  log "  Network:        $CONNECTOR_NETWORK"
  log "  Min instances:  $CONNECTOR_MIN_INSTANCES"
  log "  Max instances:  $CONNECTOR_MAX_INSTANCES"
  log "  Machine type:   $CONNECTOR_MACHINE_TYPE"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY-RUN: would create connector $CONNECTOR_NAME"
    return 0
  fi

  gcloud compute networks vpc-access connectors create "$CONNECTOR_NAME" \
    --project="$PROJECT" \
    --region="$REGION" \
    --network="$CONNECTOR_NETWORK" \
    --range="10.8.0.0/28" \
    --min-instances="$CONNECTOR_MIN_INSTANCES" \
    --max-instances="$CONNECTOR_MAX_INSTANCES" \
    --machine-type="$CONNECTOR_MACHINE_TYPE" \
    2>&1 | while IFS= read -r line; do log "  $line"; done

  # Wait for connector to reach READY state
  local wait_count=0
  local status=""
  while true; do
    status=$(get_connector_status)
    if [[ "$status" == "READY" ]]; then
      log "Connector $CONNECTOR_NAME is READY"
      return 0
    fi
    ((wait_count++))
    if [[ $wait_count -ge 60 ]]; then
      log "ERROR: Connector creation timed out after 120s (status: $status)"
      return 1
    fi
    log "  Waiting for READY state... current: $status (${wait_count}/60)"
    sleep 2
  done
}

verify_cloud_run_binding() {
  log "Verifying Cloud Run services reference connector..."
  local connector_path="projects/$PROJECT/locations/$REGION/connectors/$CONNECTOR_NAME"

  for service in "${CLOUD_RUN_SERVICES[@]}"; do
    local svc_connector
    svc_connector=$(gcloud run services describe "$service" \
      --project="$PROJECT" \
      --region="$REGION" \
      --format="value(metadata.annotations['run.googleapis.com/vpc-access-connector'])" 2>/dev/null)

    if [[ "$svc_connector" == *"$CONNECTOR_NAME"* ]]; then
      log "  OK: $service -> $CONNECTOR_NAME"
    else
      log "  WARN: $service connector binding: $svc_connector (expected: *$CONNECTOR_NAME*)"
    fi
  done
}

# --- Main Check & Rebuild ----------------------------------------------------
check_and_rebuild() {
  log "--- VPC Connector check starting ---"

  # Step 1: Check if connector exists
  local status
  status=$(get_connector_status)

  if [[ -z "$status" ]]; then
    log "ALERT: Connector $CONNECTOR_NAME does not exist — REBUILDING"
    create_connector
    verify_cloud_run_binding
    return $?
  fi

  log "Connector status: $status"

  # Step 2: Check status
  case "$status" in
    READY)
      if [[ "$FORCE_REBUILD" == "true" ]]; then
        log "Connector is READY but --force specified — REBUILDING"
        delete_connector && create_connector
        verify_cloud_run_binding
        return $?
      fi

      # Verify config matches known-good values
      local details
      details=$(get_connector_details)
      log "Connector details: $details"

      # Check for poisoned config (min/max = 0, like Battle 2)
      local min_inst max_inst
      min_inst=$(echo "$details" | python3 -c "import json,sys; print(json.load(sys.stdin).get('minInstances',0))" 2>/dev/null)
      max_inst=$(echo "$details" | python3 -c "import json,sys; print(json.load(sys.stdin).get('maxInstances',0))" 2>/dev/null)

      if [[ "$min_inst" -eq 0 || "$max_inst" -eq 0 ]]; then
        log "ALERT: Connector config poisoned (min=$min_inst, max=$max_inst) — REBUILDING"
        delete_connector && create_connector
        verify_cloud_run_binding
        return $?
      fi

      log "--- Connector healthy ---"
      verify_cloud_run_binding
      return 0
      ;;

    ERROR)
      log "ALERT: Connector in ERROR state — REBUILDING"
      delete_connector && create_connector
      verify_cloud_run_binding
      return $?
      ;;

    CREATING|UPDATING)
      log "Connector is in transitional state ($status) — waiting..."
      return 0
      ;;

    *)
      log "WARN: Unknown connector state: $status"
      return 1
      ;;
  esac
}

# --- Entry Point --------------------------------------------------------------
log "=========================================="
log "VPC Connector Rebuild Tool"
log "  Project:    $PROJECT"
log "  Region:     $REGION"
log "  Connector:  $CONNECTOR_NAME"
log "  Dry-run:    $DRY_RUN"
log "  Force:      $FORCE_REBUILD"
log "  Loop:       $LOOP_MODE"
log "=========================================="

if [[ "$LOOP_MODE" == "true" ]]; then
  SWEEP_COUNT=0
  while true; do
    ((SWEEP_COUNT++))
    log "=== Check #$SWEEP_COUNT ==="
    check_and_rebuild
    sleep "$INTERVAL"
  done
else
  check_and_rebuild
  exit $?
fi
