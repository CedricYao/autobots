#!/bin/bash
# =============================================================================
# firewall-baseline-enforce.sh — GCP Firewall Baseline Enforcement
# =============================================================================
# Derived from Battle 2 (2026-06-03) where the chaos team injected rogue
# firewall rules with rotating name patterns (gke-pod-deny-*, gke-764d49-*,
# k8s-fw-*) to block inter-pod traffic.
#
# This script enforces a known-good firewall baseline by deleting ANY rule
# not in the allowlist. It catches all naming patterns because it works by
# allowlist, not by pattern matching rogue rules.
#
# Usage:
#   ./firewall-baseline-enforce.sh                  # Continuous loop, 30s interval
#   ./firewall-baseline-enforce.sh --interval 15    # Continuous loop, 15s interval
#   ./firewall-baseline-enforce.sh --once           # Single pass
#   ./firewall-baseline-enforce.sh --dry-run        # Report only, no changes
#   ./firewall-baseline-enforce.sh --dry-run --once # Audit mode
#
# Project: boutique-demo-22
# Baseline: 15 INGRESS rules, 0 EGRESS rules
# =============================================================================

set -uo pipefail

# --- Configuration -----------------------------------------------------------
PROJECT="${PROJECT:-boutique-demo-22}"
INTERVAL="${INTERVAL:-30}"
DRY_RUN=false
SINGLE_PASS=false
LOG_PREFIX="[firewall]"

# --- Known-Good Firewall Baseline (15 INGRESS Rules) -------------------------
# These are the legitimate firewall rules for boutique-demo-22.
# ANY rule not in this list will be flagged and deleted.
#
# To update this list, run:
#   gcloud compute firewall-rules list --project=boutique-demo-22 \
#     --format="value(name)" --sort-by=name
#
# Last verified: 2026-06-03 (post-Battle 2 cleanup)
BASELINE_RULES=(
  "allow-ilb-permissive"
  "default-allow-icmp"
  "default-allow-internal"
  "default-allow-rdp"
  "default-allow-ssh"
  "gke-online-boutique-764d49-all"
  "gke-online-boutique-764d49-exkubelet"
  "gke-online-boutique-764d49-inkubelet"
  "gke-online-boutique-764d49-master"
  "gke-online-boutique-764d49-vms"
  "k8s-8cc91e1a1e87cd10-node-hc"
  "k8s-fw-a0a463dd26baf11e9be2042010a8e003"
  "k8s-fw-a7aa9e22b5d394d4f988e62e4a8b7b90"
  "k8s-fw-l7--8cc91e1a1e87cd10"
  "serverless-to-vpc-connector"
)

# --- Argument Parsing ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=true; shift ;;
    --once)       SINGLE_PASS=true; shift ;;
    --interval)   INTERVAL="$2"; shift 2 ;;
    --project)    PROJECT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [--once] [--interval N] [--project PROJECT_ID]"
      echo ""
      echo "Baseline rules (${#BASELINE_RULES[@]}):"
      for rule in "${BASELINE_RULES[@]}"; do echo "  $rule"; done
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Utility Functions --------------------------------------------------------
log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $LOG_PREFIX $*"
}

is_baseline_rule() {
  local rule_name="$1"
  for baseline in "${BASELINE_RULES[@]}"; do
    if [[ "$rule_name" == "$baseline" ]]; then
      return 0
    fi
  done
  return 1
}

# --- Sweep Functions ----------------------------------------------------------

check_ingress_rules() {
  local rogue_count=0

  # Get all firewall rules in the project
  local current_rules
  current_rules=$(gcloud compute firewall-rules list \
    --project="$PROJECT" \
    --format="value(name)" \
    --sort-by=name 2>/dev/null)

  if [[ -z "$current_rules" ]]; then
    log "WARN: Could not retrieve firewall rules (permission issue or API error)"
    return 0
  fi

  # Check each rule against baseline
  while IFS= read -r rule_name; do
    if ! is_baseline_rule "$rule_name"; then
      log "ROGUE RULE DETECTED: $rule_name"

      # Get rule details for logging
      local rule_details
      rule_details=$(gcloud compute firewall-rules describe "$rule_name" \
        --project="$PROJECT" \
        --format="table[no-heading](direction,priority,sourceRanges.list(),destinationRanges.list(),allowed[].map().firewall_rule().list(),denied[].map().firewall_rule().list())" 2>/dev/null)
      log "  Details: $rule_details"

      if [[ "$DRY_RUN" == "true" ]]; then
        log "  DRY-RUN: would delete $rule_name"
      else
        log "  DELETING: $rule_name"
        gcloud compute firewall-rules delete "$rule_name" \
          --project="$PROJECT" \
          --quiet 2>&1 | while IFS= read -r line; do log "    $line"; done
      fi
      ((rogue_count++))
    fi
  done <<< "$current_rules"

  return $rogue_count
}

check_egress_rules() {
  # Per RB-005: ANY egress deny rule targeting internal subnets is suspicious
  local egress_denies
  egress_denies=$(gcloud compute firewall-rules list \
    --project="$PROJECT" \
    --filter="direction=EGRESS" \
    --format="value(name)" 2>/dev/null)

  if [[ -n "$egress_denies" ]]; then
    while IFS= read -r rule_name; do
      # Check if it's in the baseline (currently no egress rules in baseline)
      if ! is_baseline_rule "$rule_name"; then
        log "ROGUE EGRESS RULE: $rule_name (no egress rules in baseline)"

        local rule_details
        rule_details=$(gcloud compute firewall-rules describe "$rule_name" \
          --project="$PROJECT" \
          --format="json(priority,denied,destinationRanges)" 2>/dev/null)
        log "  Details: $rule_details"

        if [[ "$DRY_RUN" == "true" ]]; then
          log "  DRY-RUN: would delete $rule_name"
        else
          log "  DELETING: $rule_name"
          gcloud compute firewall-rules delete "$rule_name" \
            --project="$PROJECT" \
            --quiet 2>&1 | while IFS= read -r line; do log "    $line"; done
        fi
      fi
    done <<< "$egress_denies"
    return 1
  fi
  return 0
}

verify_baseline_present() {
  # Verify all baseline rules still exist (detect deletion attacks like Battle 2 Phase 1)
  local missing=0
  for rule in "${BASELINE_RULES[@]}"; do
    if ! gcloud compute firewall-rules describe "$rule" --project="$PROJECT" &>/dev/null; then
      log "MISSING BASELINE RULE: $rule has been deleted!"
      ((missing++))
    fi
  done

  if [[ "$missing" -gt 0 ]]; then
    log "WARNING: $missing baseline rule(s) missing — possible deletion attack"
    return 1
  fi
  return 0
}

# --- Main Sweep ---------------------------------------------------------------
run_sweep() {
  log "--- Firewall sweep starting (project: $PROJECT) ---"

  local issues=0

  # Check for rogue rules (ingress)
  check_ingress_rules || ((issues += $?))

  # Check for rogue egress rules
  check_egress_rules || ((issues++))

  # Verify baseline rules are intact
  verify_baseline_present || ((issues++))

  # Report current state
  local total_rules
  total_rules=$(gcloud compute firewall-rules list --project="$PROJECT" --format="value(name)" 2>/dev/null | wc -l)
  log "Current rule count: $total_rules (baseline: ${#BASELINE_RULES[@]})"

  if [[ "$issues" -eq 0 ]]; then
    log "--- Firewall sweep clean ---"
  else
    log "--- Firewall sweep: $issues issue(s) found ---"
  fi

  return $issues
}

# --- Entry Point --------------------------------------------------------------
log "=========================================="
log "Firewall Baseline Enforcement starting"
log "  Project:     $PROJECT"
log "  Interval:    ${INTERVAL}s"
log "  Dry-run:     $DRY_RUN"
log "  Single-pass: $SINGLE_PASS"
log "  Baseline:    ${#BASELINE_RULES[@]} rules"
log "=========================================="

if [[ "$SINGLE_PASS" == "true" ]]; then
  run_sweep
  exit $?
fi

# Continuous loop
SWEEP_COUNT=0
while true; do
  ((SWEEP_COUNT++))
  log "=== Firewall sweep #$SWEEP_COUNT ==="
  run_sweep
  sleep "$INTERVAL"
done
