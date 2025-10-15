#!/usr/bin/env bash

################################################################################
# Fix WSO2 IS as External Key Manager
#
# Properly configures WSO2 IS as the Key Manager so that:
# - Users authenticate with WSO2 IS
# - Tokens from WSO2 IS work with API Gateway
# - Application keys are in WSO2 IS
#
# Usage: ./fix_wso2is_keymanager.sh
################################################################################

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

APP_ID="d5701bf3-8569-4c05-beff-9f8d4a9fd5b9"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Configure WSO2 IS as Primary Key Manager                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Get Key Manager ID
log_info "[1/5] Getting WSO2-IS-KeyManager ID..."
KM_ID=$(curl -sk -u "admin:admin" \
  "https://localhost:9443/api/am/admin/v4/key-managers" | \
  jq -r '.list[] | select(.name=="WSO2-IS-KeyManager") | .id')

if [ -z "$KM_ID" ] || [ "$KM_ID" = "null" ]; then
  log_error "WSO2-IS-KeyManager not found. Run configure_keymanager.sh first"
  exit 1
fi

log_success "Key Manager ID: $KM_ID"
echo ""

# Step 2: Update Key Manager with proper token validation
log_info "[2/5] Updating Key Manager configuration for token validation..."

KM_CONFIG=$(cat <<'EOF'
{
  "name": "WSO2-IS-KeyManager",
  "displayName": "WSO2 Identity Server",
  "type": "WSO2-IS",
  "description": "WSO2 Identity Server as Key Manager",
  "enabled": true,
  "configuration": {
    "ServerURL": "https://wso2is:9444/services",
    "Username": "admin",
    "Password": "admin",
    "TokenURL": "https://localhost:9444/oauth2/token",
    "RevokeURL": "https://localhost:9444/oauth2/revoke",
    "IntrospectURL": "https://localhost:9444/oauth2/introspect",
    "UserInfoURL": "https://localhost:9444/oauth2/userinfo",
    "AuthorizeURL": "https://localhost:9444/oauth2/authorize",
    "issuer": "https://localhost:9444/oauth2/token",
    "consumer_key": "",
    "consumer_secret": "",
    "certificate": {
      "type": "JWKS",
      "value": "https://localhost:9444/oauth2/jwks"
    },
    "claim_mappings": [
      {
        "remote_claim": "sub",
        "local_claim": "http://wso2.org/claims/enduser"
      }
    ],
    "grant_types": [
      "client_credentials",
      "password",
      "refresh_token",
      "authorization_code"
    ],
    "enable_token_generation": true,
    "enable_token_validation": true,
    "enable_token_encryption": false,
    "enable_map_oauth_consumer_apps": true,
    "enable_oauth_app_creation": true,
    "self_validate_jwt": false,
    "token_validation_method": "introspect",
    "ValidityTime": "3600"
  }
}
EOF
)

UPDATE_RESP=$(curl -sk -u "admin:admin" -X PUT \
  "https://localhost:9443/api/am/admin/v4/key-managers/$KM_ID" \
  -H "Content-Type: application/json" \
  -d "$KM_CONFIG")

if echo "$UPDATE_RESP" | jq -e '.id' >/dev/null 2>&1; then
  log_success "Key Manager updated with introspection-based validation"
else
  log_error "Failed to update Key Manager"
  echo "$UPDATE_RESP" | jq '.'
  exit 1
fi
echo ""

# Step 3: Delete Resident Key Manager keys
log_info "[3/5] Removing Resident Key Manager keys..."
curl -sk -u "admin:admin" -X DELETE \
  "https://localhost:9443/api/am/devportal/v3/applications/${APP_ID}/keys/PRODUCTION" 2>/dev/null || true
log_success "Old keys removed"
echo ""

# Step 4: Create OAuth client in WSO2 IS
log_info "[4/5] Creating OAuth client in WSO2 IS..."

# Delete existing client if it exists
curl -sk -u "admin:admin" -X GET \
  "https://localhost:9444/api/identity/oauth2/dcr/v1.1/applications" 2>/dev/null | \
  jq -r '.applications[] | select(.client_name=="AllServicesApp_WSO2IS") | .client_id' | \
  while read CLIENT; do
    curl -sk -u "admin:admin" -X DELETE \
      "https://localhost:9444/api/identity/oauth2/dcr/v1.1/register/${CLIENT}" 2>/dev/null || true
  done

# Create new OAuth client
DCR_RESP=$(curl -sk -u "admin:admin" -X POST \
  "https://localhost:9444/api/identity/oauth2/dcr/v1.1/register" \
  -H "Content-Type: application/json" \
  -d '{
    "client_name": "AllServicesApp_WSO2IS",
    "grant_types": ["password", "client_credentials", "refresh_token"],
    "redirect_uris": ["https://localhost/callback"],
    "ext_application_owner": "admin",
    "ext_application_token_lifetime": 3600
  }')

CLIENT_ID=$(echo "$DCR_RESP" | jq -r '.client_id')
CLIENT_SECRET=$(echo "$DCR_RESP" | jq -r '.client_secret')

if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" = "null" ]; then
  log_error "Failed to create OAuth client in WSO2 IS"
  echo "$DCR_RESP" | jq '.'
  exit 1
fi

log_success "OAuth client created in WSO2 IS"
log_info "Client ID: $CLIENT_ID"
echo ""

# Step 5: Map OAuth client to WSO2 AM application
log_info "[5/5] Mapping OAuth client to WSO2 AM application..."

MAP_RESP=$(curl -sk -u "admin:admin" -X POST \
  "https://localhost:9443/api/am/devportal/v3/applications/${APP_ID}/map-keys" \
  -H "Content-Type: application/json" \
  -d "{
    \"keyType\": \"PRODUCTION\",
    \"keyManager\": \"WSO2-IS-KeyManager\",
    \"consumerKey\": \"${CLIENT_ID}\",
    \"consumerSecret\": \"${CLIENT_SECRET}\"
  }")

if echo "$MAP_RESP" | jq -e '.consumerKey' >/dev/null 2>&1; then
  log_success "OAuth keys mapped to application"
else
  log_error "Failed to map keys"
  echo "$MAP_RESP" | jq '.'
  exit 1
fi
echo ""

# Test the integration
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Testing Integration                                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

log_info "Step 1: Getting token from WSO2 IS for ops_user..."
TOKEN_RESP=$(curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \
  -d "grant_type=password&username=ops_user&password=OpsUser123!" \
  "https://localhost:9444/oauth2/token")

ACCESS_TOKEN=$(echo "$TOKEN_RESP" | jq -r '.access_token')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
  log_error "Failed to get token from WSO2 IS"
  echo "$TOKEN_RESP" | jq '.'
  exit 1
fi

log_success "Token obtained from WSO2 IS"
echo "Token: ${ACCESS_TOKEN:0:40}..."
echo ""

log_info "Step 2: Testing API calls through WSO2 AM Gateway..."
echo ""

# Test each API
declare -A RESULTS
APIS=("forex" "profile" "wallet" "payment" "ledger" "rules")

for API in "${APIS[@]}"; do
  echo -n "Testing /${API}/v1/health ... "
  
  RESPONSE=$(curl -sk -w "\nHTTP_CODE:%{http_code}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "https://localhost:8243/${API}/v1/health" 2>/dev/null)
  
  HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
  BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE/d')
  
  if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ HTTP $HTTP_CODE${NC}"
    RESULTS[$API]="success"
  else
    echo -e "${RED}❌ HTTP $HTTP_CODE${NC}"
    RESULTS[$API]="failed"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
  fi
done

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Configuration Complete                                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Count results
SUCCESS_COUNT=0
for result in "${RESULTS[@]}"; do
  if [ "$result" = "success" ]; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  fi
done

echo "Test Results: ${SUCCESS_COUNT}/${#APIS[@]} APIs working"
echo ""
echo "Application Credentials (WSO2 IS):"
echo "  Client ID:     $CLIENT_ID"
echo "  Client Secret: $CLIENT_SECRET"
echo "  Key Manager:   WSO2-IS-KeyManager"
echo "  Token Endpoint: https://localhost:9444/oauth2/token"
echo ""
echo "Usage Example:"
echo "  # Get token from WSO2 IS"
echo "  TOKEN=\$(curl -sk -u \"${CLIENT_ID}:${CLIENT_SECRET}\" \\"
echo "    -d \"grant_type=password&username=ops_user&password=OpsUser123!\" \\"
echo "    https://localhost:9444/oauth2/token | jq -r '.access_token')"
echo ""
echo "  # Call API through WSO2 AM Gateway"
echo "  curl -k -H \"Authorization: Bearer \$TOKEN\" \\"
echo "    https://localhost:8243/forex/v1/health"
echo ""

# Save credentials
cat > /tmp/wso2is_credentials.txt << EOF
# WSO2 Identity Server OAuth Credentials
CLIENT_ID=$CLIENT_ID
CLIENT_SECRET=$CLIENT_SECRET
KEY_MANAGER=WSO2-IS-KeyManager
TOKEN_ENDPOINT=https://localhost:9444/oauth2/token
GATEWAY_URL=https://localhost:8243

# Test Users (from WSO2 IS):
# - ops_user / OpsUser123!
# - finance / Finance123!
# - auditor / Auditor123!
# - user / User1234!
# - app_admin / AppAdmin123!
EOF

log_success "Credentials saved to /tmp/wso2is_credentials.txt"
echo ""

if [ "$SUCCESS_COUNT" -eq "${#APIS[@]}" ]; then
  log_success "All APIs working with WSO2 IS tokens!"
  exit 0
else
  log_error "Some APIs failed. Check configuration."
  exit 1
fi
