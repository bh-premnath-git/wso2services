#!/usr/bin/env bash

################################################################################
# WSO2 API Manager - Fix Key Manager Integration
#
# Fixes WSO2AM-IS Key Manager integration by:
# 1. Updating Key Manager configuration
# 2. Creating OAuth client in WSO2IS
# 3. Mapping keys to WSO2AM application
# 4. Testing the integration
#
# Usage: ./fix_keymanager_integration.sh
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
IS_HOST="${IS_HOST:-localhost}"
IS_PORT="${IS_PORT:-9444}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin}"
APP_ID="${APP_ID:-d5701bf3-8569-4c05-beff-9f8d4a9fd5b9}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  WSO2 Key Manager Integration Fix                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Verify Key Manager exists
log_info "[1/4] Verifying Key Manager configuration..."
KM_RESP=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
  "https://${APIM_HOST}:${APIM_PORT}/api/am/admin/v4/key-managers" 2>/dev/null)

KM_ID=$(echo "$KM_RESP" | jq -r '.list[] | select(.name=="WSO2-IS-KeyManager") | .id')

if [ -z "$KM_ID" ] || [ "$KM_ID" = "null" ]; then
  log_error "Key Manager 'WSO2-IS-KeyManager' not found"
  log_info "Run ./configure_keymanager.sh first"
  exit 1
fi

log_success "Key Manager found: $KM_ID"
echo ""

# Step 2: Create OAuth client in WSO2IS
log_info "[2/4] Creating OAuth client in WSO2IS..."
DCR_RESP=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" -X POST \
  "https://${IS_HOST}:${IS_PORT}/api/identity/oauth2/dcr/v1.1/register" \
  -H "Content-Type: application/json" \
  -d '{
    "client_name": "AllServicesApp_PRODUCTION",
    "grant_types": ["password", "client_credentials", "refresh_token"],
    "redirect_uris": ["https://localhost/callback"],
    "ext_application_owner": "admin"
  }' 2>/dev/null)

CLIENT_ID=$(echo "$DCR_RESP" | jq -r '.client_id')
CLIENT_SECRET=$(echo "$DCR_RESP" | jq -r '.client_secret')

if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" = "null" ]; then
  log_error "Failed to create OAuth client"
  echo "$DCR_RESP" | jq '.'
  exit 1
fi

log_success "OAuth client created"
log_info "Client ID: $CLIENT_ID"
log_info "Client Secret: ${CLIENT_SECRET:0:20}..."
echo ""

# Step 3: Map keys to WSO2AM application
log_info "[3/4] Mapping OAuth keys to WSO2AM application..."
MAP_RESP=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" -X POST \
  "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications/${APP_ID}/map-keys" \
  -H "Content-Type: application/json" \
  -d "{
    \"keyType\": \"PRODUCTION\",
    \"keyManager\": \"WSO2-IS-KeyManager\",
    \"consumerKey\": \"${CLIENT_ID}\",
    \"consumerSecret\": \"${CLIENT_SECRET}\"
  }" 2>/dev/null)

if echo "$MAP_RESP" | jq -e '.consumerKey' >/dev/null 2>&1; then
  log_success "Keys mapped to application successfully"
else
  log_error "Failed to map keys"
  echo "$MAP_RESP" | jq '.'
  exit 1
fi
echo ""

# Step 4: Test token generation and API call
log_info "[4/4] Testing integration..."
echo ""

# 4.1: Generate token
log_info "Generating token for ops_user..."
TOKEN_RESP=$(curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \
  -d "grant_type=password&username=ops_user&password=OpsUser123!" \
  "https://${IS_HOST}:${IS_PORT}/oauth2/token" 2>/dev/null)

ACCESS_TOKEN=$(echo "$TOKEN_RESP" | jq -r '.access_token')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
  log_error "Token generation failed"
  echo "$TOKEN_RESP" | jq '.'
  exit 1
fi

log_success "Token generated: ${ACCESS_TOKEN:0:30}..."
echo ""

# 4.2: Test API call through gateway
log_info "Testing API call through gateway..."
API_RESP=$(curl -sk -w "\nHTTP_CODE:%{http_code}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "https://${APIM_HOST}:8243/forex/v1/health" 2>/dev/null)

HTTP_CODE=$(echo "$API_RESP" | grep "HTTP_CODE" | cut -d: -f2)
BODY=$(echo "$API_RESP" | sed '/HTTP_CODE/d')

if [ "$HTTP_CODE" = "200" ]; then
  log_success "API call successful! (HTTP $HTTP_CODE)"
  echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
else
  log_error "API call failed (HTTP $HTTP_CODE)"
  echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Integration Fix Complete                                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Save credentials for future use
CREDS_FILE="/tmp/wso2_app_credentials.txt"
cat > "$CREDS_FILE" << EOF
# WSO2 AllServicesApp Production Credentials
CLIENT_ID=$CLIENT_ID
CLIENT_SECRET=$CLIENT_SECRET
APP_ID=$APP_ID

# Test token generation:
# TOKEN=\$(curl -sk -u "\${CLIENT_ID}:\${CLIENT_SECRET}" \\
#   -d "grant_type=password&username=ops_user&password=OpsUser123!" \\
#   https://${IS_HOST}:${IS_PORT}/oauth2/token | jq -r '.access_token')

# Test API call:
# curl -k -H "Authorization: Bearer \$TOKEN" \\
#   https://${APIM_HOST}:8243/forex/v1/health
EOF

log_success "Credentials saved to: $CREDS_FILE"
echo ""
echo "Application Credentials:"
echo "  Client ID:     $CLIENT_ID"
echo "  Client Secret: $CLIENT_SECRET"
echo ""
echo "Test Commands:"
echo "  # Get token"
echo "  TOKEN=\$(curl -sk -u \"${CLIENT_ID}:${CLIENT_SECRET}\" \\"
echo "    -d \"grant_type=password&username=ops_user&password=OpsUser123!\" \\"
echo "    https://${IS_HOST}:${IS_PORT}/oauth2/token | jq -r '.access_token')"
echo ""
echo "  # Call API"
echo "  curl -k -H \"Authorization: Bearer \$TOKEN\" \\"
echo "    https://${APIM_HOST}:8243/forex/v1/health"
echo ""

if [ "$HTTP_CODE" = "200" ]; then
  exit 0
else
  exit 1
fi
