#!/bin/bash
# =============================================================================
# alert-policy-restore.sh — Monitoring Alert Policy Auto-Restore
# =============================================================================
# Derived from Battle 2 (2026-06-03) where the chaos team deleted all 3
# monitoring alert policies at 05:11Z as the opening move to blind the SRE
# team. The SRE team auto-recreated them in <30 seconds.
#
# This script detects missing alert policies and recreates them from
# known-good configurations.
#
# Usage:
#   ./alert-policy-restore.sh                   # Single pass: check & restore
#   ./alert-policy-restore.sh --dry-run         # Check only, report missing
#   ./alert-policy-restore.sh --loop            # Continuous monitoring
#   ./alert-policy-restore.sh --loop --interval 30  # Custom interval
#
# Project: boutique-demo-22
# Alert Policies: 3 (Cloud Run error rate, VPC connector health, GKE pod health)
# =============================================================================

set -uo pipefail

# --- Configuration -----------------------------------------------------------
PROJECT="${PROJECT:-boutique-demo-22}"
DRY_RUN=false
LOOP_MODE=false
INTERVAL="${INTERVAL:-60}"
LOG_PREFIX="[alerts]"

# Notification channel (if configured — leave empty to create policies without notification)
NOTIFICATION_CHANNEL="${NOTIFICATION_CHANNEL:-}"

# --- Argument Parsing ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=true; shift ;;
    --loop)       LOOP_MODE=true; shift ;;
    --interval)   INTERVAL="$2"; shift 2 ;;
    --project)    PROJECT="$2"; shift 2 ;;
    --channel)    NOTIFICATION_CHANNEL="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [--loop] [--interval N] [--project PROJECT] [--channel CHANNEL_ID]"
      echo ""
      echo "Managed alert policies:"
      echo "  1. Cloud Run 5xx Error Rate (frontend-alt services)"
      echo "  2. VPC Connector Health (west1-default)"
      echo "  3. GKE Pod Restart Alert (online-boutique cluster)"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Utility Functions --------------------------------------------------------
log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $LOG_PREFIX $*"
}

# Get existing alert policy display names
get_existing_policies() {
  gcloud alpha monitoring policies list \
    --project="$PROJECT" \
    --format="value(displayName)" 2>/dev/null
}

policy_exists() {
  local display_name="$1"
  local existing
  existing=$(get_existing_policies)
  echo "$existing" | grep -qF "$display_name"
}

# --- Alert Policy Definitions -------------------------------------------------
# Each function creates one alert policy using gcloud.

create_cloud_run_error_rate_policy() {
  local policy_name="Cloud Run 5xx Error Rate"
  log "Creating alert policy: $policy_name"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY-RUN: would create '$policy_name'"
    return 0
  fi

  # Create policy JSON
  local policy_file
  policy_file=$(mktemp /tmp/alert-policy-XXXXXX.json)

  cat > "$policy_file" << 'POLICY_EOF'
{
  "displayName": "Cloud Run 5xx Error Rate",
  "documentation": {
    "content": "Cloud Run frontend services are returning elevated 5xx error rates. Check Cloud Run logs, VPC connector status, and backend health.\n\nRunbooks: RB-006 (traffic pinning), RB-009 (sidecar disable)",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Cloud Run 5xx error rate > 5%",
      "conditionThreshold": {
        "filter": "resource.type = \"cloud_run_revision\" AND metric.type = \"run.googleapis.com/request_count\" AND metric.labels.response_code_class = \"5xx\"",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE",
            "crossSeriesReducer": "REDUCE_SUM",
            "groupByFields": ["resource.labels.service_name"]
          }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 5,
        "duration": "60s",
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "combiner": "OR",
  "enabled": true,
  "alertStrategy": {
    "autoClose": "604800s"
  }
}
POLICY_EOF

  # Add notification channel if configured
  if [[ -n "$NOTIFICATION_CHANNEL" ]]; then
    local tmp_file
    tmp_file=$(mktemp /tmp/alert-policy-nc-XXXXXX.json)
    python3 -c "
import json, sys
with open('$policy_file') as f:
    policy = json.load(f)
policy['notificationChannels'] = ['$NOTIFICATION_CHANNEL']
with open('$tmp_file', 'w') as f:
    json.dump(policy, f, indent=2)
" 2>/dev/null && mv "$tmp_file" "$policy_file"
  fi

  gcloud alpha monitoring policies create \
    --project="$PROJECT" \
    --policy-from-file="$policy_file" \
    2>&1 | while IFS= read -r line; do log "  $line"; done

  rm -f "$policy_file"
  log "Created: $policy_name"
}

create_vpc_connector_health_policy() {
  local policy_name="VPC Connector Health"
  log "Creating alert policy: $policy_name"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY-RUN: would create '$policy_name'"
    return 0
  fi

  local policy_file
  policy_file=$(mktemp /tmp/alert-policy-XXXXXX.json)

  cat > "$policy_file" << 'POLICY_EOF'
{
  "displayName": "VPC Connector Health",
  "documentation": {
    "content": "VPC serverless connector is unhealthy or has been deleted. This severs Cloud Run to GKE backend connectivity.\n\nRunbook: vpc-connector-rebuild.sh",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "VPC connector throughput dropped to zero",
      "conditionThreshold": {
        "filter": "resource.type = \"vpc_access_connector\" AND metric.type = \"vpcaccess.googleapis.com/connector/sent_bytes_count\"",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_RATE",
            "crossSeriesReducer": "REDUCE_SUM"
          }
        ],
        "comparison": "COMPARISON_LT",
        "thresholdValue": 1,
        "duration": "300s",
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "combiner": "OR",
  "enabled": true,
  "alertStrategy": {
    "autoClose": "604800s"
  }
}
POLICY_EOF

  if [[ -n "$NOTIFICATION_CHANNEL" ]]; then
    local tmp_file
    tmp_file=$(mktemp /tmp/alert-policy-nc-XXXXXX.json)
    python3 -c "
import json, sys
with open('$policy_file') as f:
    policy = json.load(f)
policy['notificationChannels'] = ['$NOTIFICATION_CHANNEL']
with open('$tmp_file', 'w') as f:
    json.dump(policy, f, indent=2)
" 2>/dev/null && mv "$tmp_file" "$policy_file"
  fi

  gcloud alpha monitoring policies create \
    --project="$PROJECT" \
    --policy-from-file="$policy_file" \
    2>&1 | while IFS= read -r line; do log "  $line"; done

  rm -f "$policy_file"
  log "Created: $policy_name"
}

create_gke_pod_restart_policy() {
  local policy_name="GKE Pod Restart Alert"
  log "Creating alert policy: $policy_name"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY-RUN: would create '$policy_name'"
    return 0
  fi

  local policy_file
  policy_file=$(mktemp /tmp/alert-policy-XXXXXX.json)

  cat > "$policy_file" << 'POLICY_EOF'
{
  "displayName": "GKE Pod Restart Alert",
  "documentation": {
    "content": "GKE pods are restarting frequently, indicating crash loops or resource pressure. Check for CRD floods (sidecar crashes), env var poisoning, or resource quota attacks.\n\nRunbooks: RB-008 (GKE attack response), RB-009 (emergency sidecar disable)",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Pod restart count > 5 in 5 minutes",
      "conditionThreshold": {
        "filter": "resource.type = \"k8s_container\" AND metric.type = \"kubernetes.io/container/restart_count\"",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_DELTA",
            "crossSeriesReducer": "REDUCE_SUM",
            "groupByFields": ["resource.labels.pod_name"]
          }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 5,
        "duration": "0s",
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "combiner": "OR",
  "enabled": true,
  "alertStrategy": {
    "autoClose": "604800s"
  }
}
POLICY_EOF

  if [[ -n "$NOTIFICATION_CHANNEL" ]]; then
    local tmp_file
    tmp_file=$(mktemp /tmp/alert-policy-nc-XXXXXX.json)
    python3 -c "
import json, sys
with open('$policy_file') as f:
    policy = json.load(f)
policy['notificationChannels'] = ['$NOTIFICATION_CHANNEL']
with open('$tmp_file', 'w') as f:
    json.dump(policy, f, indent=2)
" 2>/dev/null && mv "$tmp_file" "$policy_file"
  fi

  gcloud alpha monitoring policies create \
    --project="$PROJECT" \
    --policy-from-file="$policy_file" \
    2>&1 | while IFS= read -r line; do log "  $line"; done

  rm -f "$policy_file"
  log "Created: $policy_name"
}

# --- Known Policies -----------------------------------------------------------
# Map of display name -> creation function
declare -A MANAGED_POLICIES=(
  ["Cloud Run 5xx Error Rate"]="create_cloud_run_error_rate_policy"
  ["VPC Connector Health"]="create_vpc_connector_health_policy"
  ["GKE Pod Restart Alert"]="create_gke_pod_restart_policy"
)

# --- Main Check & Restore ----------------------------------------------------
check_and_restore() {
  log "--- Alert policy check starting (project: $PROJECT) ---"

  local missing=0
  local existing=0

  for policy_name in "${!MANAGED_POLICIES[@]}"; do
    if policy_exists "$policy_name"; then
      log "OK: '$policy_name' exists"
      ((existing++))
    else
      log "MISSING: '$policy_name' — restoring"
      ${MANAGED_POLICIES[$policy_name]}
      ((missing++))
    fi
  done

  # Summary
  local total=${#MANAGED_POLICIES[@]}
  if [[ "$missing" -eq 0 ]]; then
    log "--- All $total alert policies present ---"
  else
    log "--- Restored $missing of $total alert policies ($existing were already present) ---"
  fi

  return $missing
}

# --- Entry Point --------------------------------------------------------------
log "=========================================="
log "Alert Policy Restore Tool"
log "  Project:    $PROJECT"
log "  Dry-run:    $DRY_RUN"
log "  Loop:       $LOOP_MODE"
log "  Interval:   ${INTERVAL}s"
log "  Policies:   ${#MANAGED_POLICIES[@]} managed"
log "  Channel:    ${NOTIFICATION_CHANNEL:-none}"
log "=========================================="

if [[ "$LOOP_MODE" == "true" ]]; then
  SWEEP_COUNT=0
  while true; do
    ((SWEEP_COUNT++))
    log "=== Alert check #$SWEEP_COUNT ==="
    check_and_restore
    sleep "$INTERVAL"
  done
else
  check_and_restore
  exit $?
fi
