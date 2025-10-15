#!/usr/bin/env bash

################################################################################
# WSO2 API Manager - Deploy APIs to Gateway
#
# Creates revisions and deploys APIs to the gateway runtime
# Required for WSO2 API Manager 4.x (APIs must have revisions to be accessible)
#
# Usage: ./deploy_apis_to_gateway.sh
################################################################################

set -eo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
APIM_HOST="${APIM_HOST:-localhost}"
APIM_PORT="${APIM_PORT:-9443}"
APIM_BASE="https://${APIM_HOST}:${APIM_PORT}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin}"
GATEWAY_ENV="${GATEWAY_ENV:-Default}"
VHOST="${VHOST:-localhost}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  WSO2 API Manager - Deploy APIs to Gateway                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

log_info "Target: ${APIM_BASE}"
log_info "Gateway Environment: ${GATEWAY_ENV}"
log_info "VHost: ${VHOST}"
echo ""

# Get all published APIs
log_info "Fetching published APIs..."
API_LIST=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
  "${APIM_BASE}/api/am/publisher/v4/apis" 2>/dev/null | jq -r '.list[] | .id')

if [ -z "$API_LIST" ]; then
  log_error "No APIs found or failed to connect to API Manager"
  exit 1
fi

API_COUNT=$(echo "$API_LIST" | wc -l)
log_success "Found $API_COUNT APIs"
echo ""

# Process each API
DEPLOYED=0
FAILED=0

for API_ID in $API_LIST; do
  # Get API details
  API_DETAILS=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${APIM_BASE}/api/am/publisher/v4/apis/${API_ID}" 2>/dev/null)
  
  API_NAME=$(echo "$API_DETAILS" | jq -r '.name')
  API_VERSION=$(echo "$API_DETAILS" | jq -r '.version')
  API_CONTEXT=$(echo "$API_DETAILS" | jq -r '.context')
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log_info "Processing: $API_NAME ($API_VERSION)"
  echo "   Context: $API_CONTEXT"
  
  # Check existing revisions
  EXISTING_REVS=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${APIM_BASE}/api/am/publisher/v4/apis/${API_ID}/revisions" 2>/dev/null | jq -r '.count')
  
  if [ "$EXISTING_REVS" -gt 0 ]; then
    log_warning "API already has $EXISTING_REVS revision(s)"
    
    # Check if deployed
    DEPLOYED_REVS=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
      "${APIM_BASE}/api/am/publisher/v4/apis/${API_ID}/revisions" 2>/dev/null | \
      jq -r '.list[] | select(.deploymentInfo | length > 0) | .id')
    
    if [ -n "$DEPLOYED_REVS" ]; then
      log_success "Already deployed to gateway"
      DEPLOYED=$((DEPLOYED + 1))
      echo ""
      continue
    fi
  fi
  
  # Create new revision
  log_info "Creating revision..."
  REV_RESP=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" -X POST \
    -H "Content-Type: application/json" \
    -d "{\"description\": \"Deployed on $(date +'%Y-%m-%d %H:%M:%S')\"}" \
    "${APIM_BASE}/api/am/publisher/v4/apis/${API_ID}/revisions" 2>/dev/null)
  
  REV_ID=$(echo "$REV_RESP" | jq -r '.id // empty')
  
  if [ -z "$REV_ID" ] || [ "$REV_ID" = "null" ]; then
    log_error "Failed to create revision"
    echo "$REV_RESP" | jq '.'
    FAILED=$((FAILED + 1))
    echo ""
    continue
  fi
  
  log_success "Created revision: $REV_ID"
  
  # Deploy revision to gateway
  log_info "Deploying to gateway environment: $GATEWAY_ENV"
  DEPLOY_RESP=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" -X POST \
    -H "Content-Type: application/json" \
    -d "[{\"name\": \"${GATEWAY_ENV}\", \"vhost\": \"${VHOST}\", \"displayOnDevportal\": true}]" \
    "${APIM_BASE}/api/am/publisher/v4/apis/${API_ID}/deploy-revision?revisionId=${REV_ID}" 2>/dev/null)
  
  # Check if deployment was successful (response is an array with deployment info)
  if echo "$DEPLOY_RESP" | jq -e '.[0].deployedTime' >/dev/null 2>&1; then
    DEPLOY_STATUS=$(echo "$DEPLOY_RESP" | jq -r '.[0].status')
    log_success "Deployed to Gateway! (Status: $DEPLOY_STATUS)"
    log_info "Gateway URL: https://${VHOST}:8243${API_CONTEXT}/${API_VERSION}/*"
    DEPLOYED=$((DEPLOYED + 1))
  else
    log_error "Deployment failed"
    echo "$DEPLOY_RESP" | jq '.'
    FAILED=$((FAILED + 1))
  fi
  
  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Deployment Summary                                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Total APIs: $API_COUNT"
echo "✅ Deployed: $DEPLOYED"
echo "❌ Failed: $FAILED"
echo ""

if [ $DEPLOYED -gt 0 ]; then
  log_success "APIs are now accessible through the gateway!"
  echo ""
  echo "Gateway Base URL: https://${VHOST}:8243"
  echo ""
  echo "Test an API:"
  echo "  curl -k https://${VHOST}:8243/forex/v1/health"
  echo ""
  echo "With authentication:"
  echo "  curl -k -H \"Authorization: Bearer \$TOKEN\" \\"
  echo "    https://${VHOST}:8243/forex/v1/health"
  echo ""
fi

if [ $FAILED -gt 0 ]; then
  log_warning "Some APIs failed to deploy. Check the errors above."
  exit 1
fi

exit 0
