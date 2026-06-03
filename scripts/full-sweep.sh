#!/bin/bash
# =============================================================================
# full-sweep.sh — Multi-Vector Chaos Artifact Sweep & Remediation
# =============================================================================
# Derived from Battle 2 (2026-06-03) defensive automation.
# Continuously scans and remediates chaos artifacts across the GKE cluster.
#
# Covers 8 attack vectors from Battle 2:
#   1. Rogue EnvoyFilters
#   2. Rogue NetworkPolicies
#   3. Service selector corruption
#   4. ENV var poisoning (deployment-level)
#   5. Redis CONFIG tampering (maxmemory)
#   6. Rogue ResourceQuotas
#   7. Node cordon/taint injection
#   8. Deployment scale-to-zero
#
# Usage:
#   ./full-sweep.sh                    # Continuous loop, 10s interval
#   ./full-sweep.sh --interval 30      # Continuous loop, 30s interval
#   ./full-sweep.sh --once             # Single pass
#   ./full-sweep.sh --dry-run          # Report only, no changes
#   ./full-sweep.sh --dry-run --once   # Audit mode: single pass, report only
#
# Project: boutique-demo-22
# Cluster: online-boutique-764d49 (us-central1-a)
# Namespace: online-boutique-demo
# =============================================================================

set -uo pipefail

# --- Configuration -----------------------------------------------------------
NAMESPACE="${NAMESPACE:-online-boutique-demo}"
INTERVAL="${INTERVAL:-10}"
DRY_RUN=false
SINGLE_PASS=false
LOG_PREFIX="[sweep]"

# --- Known-Good Baselines ----------------------------------------------------
# Service selector mappings (service-name -> selector label value)
# All services use label selector: app=<service-name>
declare -A KNOWN_SELECTORS=(
  [adservice]="adservice"
  [cartservice]="cartservice"
  [checkoutservice]="checkoutservice"
  [currencyservice]="currencyservice"
  [emailservice]="emailservice"
  [frontend]="frontend"
  [loadgenerator]="loadgenerator"
  [paymentservice]="paymentservice"
  [productcatalogservice]="productcatalogservice"
  [recommendationservice]="recommendationservice"
  [shippingservice]="shippingservice"
  [redis-cart]="redis-cart"
)

# Known-good ENV vars per deployment (critical vars only)
# Format: DEPLOYMENT:VAR_NAME=VAR_VALUE
KNOWN_ENV=(
  "frontend:PORT=8080"
  "frontend:PRODUCT_CATALOG_SERVICE_ADDR=productcatalogservice:3550"
  "frontend:CURRENCY_SERVICE_ADDR=currencyservice:7000"
  "frontend:CART_SERVICE_ADDR=cartservice:7070"
  "frontend:RECOMMENDATION_SERVICE_ADDR=recommendationservice:8080"
  "frontend:SHIPPING_SERVICE_ADDR=shippingservice:50051"
  "frontend:CHECKOUT_SERVICE_ADDR=checkoutservice:5050"
  "frontend:AD_SERVICE_ADDR=adservice:9555"
  "cartservice:PORT=7070"
  "cartservice:REDIS_ADDR=redis-cart:6379"
  "productcatalogservice:PORT=3550"
  "currencyservice:PORT=7000"
  "emailservice:PORT=8080"
  "paymentservice:PORT=50051"
  "shippingservice:PORT=50051"
  "checkoutservice:PORT=5050"
  "checkoutservice:PRODUCT_CATALOG_SERVICE_ADDR=productcatalogservice:3550"
  "checkoutservice:SHIPPING_SERVICE_ADDR=shippingservice:50051"
  "checkoutservice:PAYMENT_SERVICE_ADDR=paymentservice:50051"
  "checkoutservice:EMAIL_SERVICE_ADDR=emailservice:8080"
  "checkoutservice:CURRENCY_SERVICE_ADDR=currencyservice:7000"
  "checkoutservice:CART_SERVICE_ADDR=cartservice:7070"
  "recommendationservice:PORT=8080"
  "recommendationservice:PRODUCT_CATALOG_SERVICE_ADDR=productcatalogservice:3550"
  "adservice:PORT=9555"
  "loadgenerator:FRONTEND_ADDR=frontend:8080"
  "loadgenerator:USERS=10"
)

# Minimum replicas per deployment
declare -A MIN_REPLICAS=(
  [adservice]=1
  [cartservice]=1
  [checkoutservice]=1
  [currencyservice]=1
  [emailservice]=1
  [frontend]=1
  [loadgenerator]=1
  [paymentservice]=1
  [productcatalogservice]=1
  [recommendationservice]=1
  [shippingservice]=1
  [redis-cart]=1
)

# --- Argument Parsing ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=true; shift ;;
    --once)       SINGLE_PASS=true; shift ;;
    --interval)   INTERVAL="$2"; shift 2 ;;
    --namespace)  NAMESPACE="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [--once] [--interval N] [--namespace NS]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Utility Functions --------------------------------------------------------
log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $LOG_PREFIX $*"
}

action() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY-RUN: would execute: $*"
  else
    log "REMEDIATE: $*"
    eval "$@" 2>&1 | while IFS= read -r line; do log "  $line"; done
  fi
}

# --- Sweep Functions ----------------------------------------------------------

sweep_envoyfilters() {
  local count
  count=$(kubectl get envoyfilters -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
  if [[ "$count" -gt 0 ]]; then
    log "FOUND: $count EnvoyFilter(s) in $NAMESPACE"
    kubectl get envoyfilters -n "$NAMESPACE" --no-headers 2>/dev/null | while read -r name _rest; do
      action "kubectl delete envoyfilter '$name' -n '$NAMESPACE'"
    done
    return 1
  fi
  return 0
}

sweep_networkpolicies() {
  local count
  count=$(kubectl get networkpolicies -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
  if [[ "$count" -gt 0 ]]; then
    log "FOUND: $count NetworkPolicy(ies) in $NAMESPACE"
    kubectl get networkpolicies -n "$NAMESPACE" --no-headers 2>/dev/null | while read -r name _rest; do
      action "kubectl delete networkpolicy '$name' -n '$NAMESPACE'"
    done
    return 1
  fi
  return 0
}

sweep_selectors() {
  local issues=0
  for svc in "${!KNOWN_SELECTORS[@]}"; do
    local expected="${KNOWN_SELECTORS[$svc]}"
    local actual
    actual=$(kubectl get service "$svc" -n "$NAMESPACE" -o jsonpath='{.spec.selector.app}' 2>/dev/null)
    if [[ -n "$actual" && "$actual" != "$expected" ]]; then
      log "FOUND: Service $svc selector corrupted: app=$actual (expected: app=$expected)"
      action "kubectl patch service '$svc' -n '$NAMESPACE' -p '{\"spec\":{\"selector\":{\"app\":\"$expected\"}}}'"
      issues=1
    fi
  done
  return $issues
}

sweep_env_vars() {
  local issues=0
  for entry in "${KNOWN_ENV[@]}"; do
    local deploy="${entry%%:*}"
    local var_pair="${entry#*:}"
    local var_name="${var_pair%%=*}"
    local var_value="${var_pair#*=}"

    local actual
    actual=$(kubectl get deployment "$deploy" -n "$NAMESPACE" \
      -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name=='$var_name')].value}" 2>/dev/null)

    if [[ -n "$actual" && "$actual" != "$var_value" ]]; then
      log "FOUND: Deployment $deploy env $var_name=$actual (expected: $var_value)"
      action "kubectl set env deployment/'$deploy' -n '$NAMESPACE' '$var_name=$var_value'"
      issues=1
    fi
  done
  return $issues
}

sweep_redis_config() {
  local redis_pod
  redis_pod=$(kubectl get pods -n "$NAMESPACE" -l app=redis-cart -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [[ -z "$redis_pod" ]]; then
    log "WARN: redis-cart pod not found"
    return 0
  fi

  local maxmem
  maxmem=$(kubectl exec "$redis_pod" -n "$NAMESPACE" -- redis-cli CONFIG GET maxmemory 2>/dev/null | tail -1)

  # maxmemory of 0 means unlimited (default). Small values like 1048576 (1MB) are attacks.
  if [[ -n "$maxmem" && "$maxmem" != "0" && "$maxmem" -lt 104857600 ]]; then
    log "FOUND: Redis maxmemory set to $maxmem bytes (attack threshold: <100MB)"
    action "kubectl exec '$redis_pod' -n '$NAMESPACE' -- redis-cli CONFIG SET maxmemory 0"
    return 1
  fi
  return 0
}

sweep_resource_quotas() {
  local rogue_quotas
  rogue_quotas=$(kubectl get resourcequotas -n "$NAMESPACE" --no-headers 2>/dev/null | grep -i chaos | awk '{print $1}')
  if [[ -n "$rogue_quotas" ]]; then
    while read -r quota; do
      log "FOUND: Rogue ResourceQuota: $quota"
      action "kubectl delete resourcequota '$quota' -n '$NAMESPACE'"
    done <<< "$rogue_quotas"
    return 1
  fi
  return 0
}

sweep_node_cordons() {
  local cordoned
  cordoned=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.unschedulable}{"\n"}{end}' 2>/dev/null | grep true | awk '{print $1}')
  if [[ -n "$cordoned" ]]; then
    while read -r node; do
      log "FOUND: Node cordoned: $node"
      action "kubectl uncordon '$node'"
    done <<< "$cordoned"
    return 1
  fi
  return 0
}

sweep_scale_zero() {
  local issues=0
  for deploy in "${!MIN_REPLICAS[@]}"; do
    local min="${MIN_REPLICAS[$deploy]}"
    local actual
    actual=$(kubectl get deployment "$deploy" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [[ -n "$actual" && "$actual" -lt "$min" ]]; then
      log "FOUND: Deployment $deploy scaled to $actual (minimum: $min)"
      action "kubectl scale deployment/'$deploy' -n '$NAMESPACE' --replicas='$min'"
      issues=1
    fi
  done
  return $issues
}

# --- Rogue Istio CRD Sweep (VS, AP, DR, PA, SE) ------------------------------
sweep_istio_crds() {
  local issues=0
  for crd_type in virtualservices authorizationpolicies destinationrules peerauthentications serviceentries; do
    local count
    count=$(kubectl get "$crd_type" -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [[ "$count" -gt 0 ]]; then
      log "FOUND: $count rogue $crd_type in $NAMESPACE"
      action "kubectl delete '$crd_type' --all -n '$NAMESPACE'"
      issues=1
    fi
  done
  return $issues
}

# --- Main Sweep ---------------------------------------------------------------
run_sweep() {
  local total_issues=0

  log "--- Sweep starting (namespace: $NAMESPACE) ---"

  sweep_envoyfilters      || ((total_issues++))
  sweep_istio_crds        || ((total_issues++))
  sweep_networkpolicies   || ((total_issues++))
  sweep_selectors         || ((total_issues++))
  sweep_env_vars          || ((total_issues++))
  sweep_redis_config      || ((total_issues++))
  sweep_resource_quotas   || ((total_issues++))
  sweep_node_cordons      || ((total_issues++))
  sweep_scale_zero        || ((total_issues++))

  if [[ "$total_issues" -eq 0 ]]; then
    log "--- Sweep clean: no issues found ---"
  else
    log "--- Sweep complete: remediated $total_issues vector(s) ---"
  fi

  return $total_issues
}

# --- Entry Point --------------------------------------------------------------
log "=========================================="
log "Full Sweep starting"
log "  Namespace:  $NAMESPACE"
log "  Interval:   ${INTERVAL}s"
log "  Dry-run:    $DRY_RUN"
log "  Single-pass: $SINGLE_PASS"
log "=========================================="

if [[ "$SINGLE_PASS" == "true" ]]; then
  run_sweep
  exit $?
fi

# Continuous loop
SWEEP_COUNT=0
while true; do
  ((SWEEP_COUNT++))
  log "=== Sweep #$SWEEP_COUNT ==="
  run_sweep
  sleep "$INTERVAL"
done
