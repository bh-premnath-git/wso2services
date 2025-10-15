#!/usr/bin/env bash

################################################################################
# Register WSO2 IS 7.1.0 as External Key Manager in WSO2 AM 4.3.0
#
# This script configures WSO2 Identity Server as the Key Manager so that:
# - Users authenticate with WSO2 IS (ops_user, finance, etc.)
# - OAuth tokens are issued by WSO2 IS
# - API Gateway validates tokens via WSO2 IS introspection
# - Application keys are stored in WSO2 IS
#
# Usage: ./register_wso2is_keymanager.sh
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
AM_HOST="${AM_HOST:-localhost}"
AM_PORT="${AM_PORT:-9443}"
AM_BASE="https://${AM_HOST}:${AM_PORT}"
AM_ADMIN_USER="${AM_ADMIN_USER:-admin}"
AM_ADMIN_PASS="${AM_ADMIN_PASS:-admin}"

KM_NAME="WSO2-IS-KeyManager"
KM_CONFIG_FILE="conf/wso2am/is7-key-manager.json"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Register WSO2 IS as External Key Manager                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Wait for APIM Admin API
log_info "Waiting for APIM Admin API..."
MAX_WAIT=60
ELAPSED=0
until curl -sk -u "${AM_ADMIN_USER}:${AM_ADMIN_PASS}" \
  "${AM_BASE}/api/am/admin/v4/key-managers" >/dev/null 2>&1; do
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    log_error "APIM Admin API not ready after ${MAX_WAIT}s"
    exit 1
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done
log_success "APIM Admin API ready"
echo ""

# Check if Key Manager exists
log_info "Checking if Key Manager '${KM_NAME}' exists..."
EXISTING_KM=$(curl -sk -u "${AM_ADMIN_USER}:${AM_ADMIN_PASS}" \
  "${AM_BASE}/api/am/admin/v4/key-managers" | \
  jq -r ".list[] | select(.name==\"${KM_NAME}\") | .id" 2>/dev/null || echo "")

if [ -n "$EXISTING_KM" ]; then
  log_warning "Key Manager '${KM_NAME}' already exists (ID: ${EXISTING_KM})"
  log_info "Deleting existing Key Manager..."
  
  curl -sk -u "${AM_ADMIN_USER}:${AM_ADMIN_PASS}" -X DELETE \
    "${AM_BASE}/api/am/admin/v4/key-managers/${EXISTING_KM}" >/dev/null 2>&1
  
  log_success "Existing Key Manager deleted"
  sleep 2
fi
echo ""

# Verify config file exists
if [ ! -f "$KM_CONFIG_FILE" ]; then
  log_error "Key Manager config file not found: $KM_CONFIG_FILE"
  exit 1
fi

# Register Key Manager
log_info "Registering WSO2 IS as Key Manager..."
RESPONSE=$(curl -sk -u "${AM_ADMIN_USER}:${AM_ADMIN_PASS}" \
  -H "Content-Type: application/json" \
  -d @"${KM_CONFIG_FILE}" \
  -w "\n%{http_code}" \
  "${AM_BASE}/api/am/admin/v4/key-managers")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ]; then
  KM_ID=$(echo "$BODY" | jq -r '.id' 2>/dev/null || echo "")
  log_success "Key Manager registered successfully!"
  log_info "ID: ${KM_ID}"
  log_info "Name: ${KM_NAME}"
  echo ""
  
  # Show Key Manager details
  log_info "Key Manager Configuration:"
  echo "$BODY" | jq '{
    id, 
    name, 
    type, 
    enabled,
    tokenValidation: .configuration.token_validation_method,
    issuer: .configuration.issuer,
    introspectURL: .configuration.IntrospectURL
  }'
  echo ""
  
  log_success "WSO2 IS Key Manager registration complete!"
  echo ""
  echo "Next Steps:"
  echo "  1. Remove Resident Key Manager application keys (if any)"
  echo "  2. Create OAuth client in WSO2 IS"
  echo "  3. Map OAuth client to APIM application"
  echo "  4. Test with IS users (ops_user, finance, etc.)"
  echo ""
  echo "Run: ./app_scripts/setup_application_keys_with_is.sh"
  echo ""
  exit 0
else
  log_error "Failed to register Key Manager (HTTP ${HTTP_CODE})"
  echo ""
  echo "Response:"
  echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
  echo ""
  
  # Troubleshooting hints
  if echo "$BODY" | grep -qi "well-known"; then
    log_warning "Cannot reach IS well-known endpoint. Check:"
    echo "  - IS is running: docker compose ps wso2is"
    echo "  - IS health: curl -k https://localhost:9444/oauth2/token/.well-known/openid-configuration"
  fi
  
  exit 1
fi
