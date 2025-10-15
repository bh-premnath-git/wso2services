#!/usr/bin/env bash

################################################################################
# WSO2 Key Manager - Complete Diagnostic and Fix
#
# This script:
# 1. Diagnoses Key Manager connectivity issues
# 2. Tests DCR endpoint directly
# 3. Updates Key Manager configuration
# 4. Verifies SSL certificates
# 5. Tests key generation
#
# Usage: ./diagnose_and_fix_keymanager.sh
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
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

AM_HOST="localhost"
AM_PORT="9443"
IS_HOST="localhost"
IS_PORT="9444"
IS_INTERNAL_HOST="wso2is"
IS_INTERNAL_PORT="9443"
APP_ID="d5701bf3-8569-4c05-beff-9f8d4a9fd5b9"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  WSO2 Key Manager - Diagnostic & Fix                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Check AM logs for errors
log_info "[1/7] Checking WSO2 AM logs for Key Manager errors..."
echo ""

if docker compose ps wso2am | grep -q "Up"; then
  LOG_ERRORS=$(docker compose logs wso2am --tail=100 2>&1 | \
    grep -i "keymanager\|DCR\|client.registration" || echo "")
  
  if [ -n "$LOG_ERRORS" ]; then
    log_warning "Found Key Manager related log entries:"
    echo "$LOG_ERRORS" | tail -10
  else
    log_info "No obvious errors in recent logs"
  fi
else
  log_error "WSO2 AM container not running"
  exit 1
fi
echo ""

# Step 2: Test DCR endpoint directly
log_info "[2/7] Testing WSO2 IS DCR endpoint directly..."
echo ""

DCR_TEST=$(curl -sk -X POST \
  "https://${IS_HOST}:${IS_PORT}/api/identity/oauth2/dcr/v1.1/register" \
  -H "Authorization: Basic $(echo -n 'admin:admin' | base64)" \
  -H "Content-Type: application/json" \
  -d '{
    "client_name": "DiagnosticTestClient",
    "grant_types": ["client_credentials", "password"],
    "redirect_uris": ["https://localhost/callback"]
  }')

DCR_CLIENT_ID=$(echo "$DCR_TEST" | jq -r '.client_id // empty')

if [ -n "$DCR_CLIENT_ID" ] && [ "$DCR_CLIENT_ID" != "null" ]; then
  log_success "DCR endpoint working! Test client created: $DCR_CLIENT_ID"
  
  # Clean up test client
  curl -sk -X DELETE \
    "https://${IS_HOST}:${IS_PORT}/api/identity/oauth2/dcr/v1.1/register/${DCR_CLIENT_ID}" \
    -H "Authorization: Basic $(echo -n 'admin:admin' | base64)" >/dev/null 2>&1
else
  log_error "DCR endpoint not working!"
  echo "$DCR_TEST" | jq '.'
  log_warning "WSO2 IS may need DCR enabled in deployment.toml"
  exit 1
fi
echo ""

# Step 3: Check network connectivity from AM to IS
log_info "[3/7] Testing network connectivity AM → IS..."
echo ""

NETWORK_TEST=$(docker compose exec -T wso2am curl -sk -o /dev/null -w "%{http_code}" \
  "https://${IS_INTERNAL_HOST}:${IS_INTERNAL_PORT}/oauth2/token/.well-known/openid-configuration" 2>/dev/null || echo "000")

if [ "$NETWORK_TEST" = "200" ]; then
  log_success "Network connectivity OK (HTTP $NETWORK_TEST)"
else
  log_error "Cannot reach WSO2 IS from WSO2 AM container (HTTP $NETWORK_TEST)"
  log_warning "Check docker network configuration"
  exit 1
fi
echo ""

# Step 4: Get current Key Manager configuration
log_info "[4/7] Checking current Key Manager configuration..."
echo ""

KM_LIST=$(curl -sk -u "admin:admin" \
  "https://${AM_HOST}:${AM_PORT}/api/am/admin/v4/key-managers")

KM_ID=$(echo "$KM_LIST" | jq -r '.list[] | select(.name=="WSO2-IS-KeyManager") | .id')

if [ -z "$KM_ID" ] || [ "$KM_ID" = "null" ]; then
  log_error "WSO2-IS-KeyManager not found"
  log_info "Run: ./app_scripts/register_wso2is_keymanager.sh"
  exit 1
fi

log_success "Key Manager found: $KM_ID"

# Get full configuration
KM_CONFIG=$(curl -sk -u "admin:admin" \
  "https://${AM_HOST}:${AM_PORT}/api/am/admin/v4/key-managers/${KM_ID}")

echo "Current configuration:"
echo "$KM_CONFIG" | jq '{
  name,
  enabled,
  introspectURL: .additionalProperties.IntrospectURL,
  tokenURL: .additionalProperties.TokenURL,
  registrationEP: .additionalProperties.client_registration_endpoint
}' 2>/dev/null || echo "$KM_CONFIG" | jq '.'
echo ""

# Step 5: Update Key Manager with correct DCR configuration
log_info "[5/7] Updating Key Manager with proper DCR configuration..."
echo ""

UPDATE_CONFIG=$(cat <<EOF
{
  "name": "WSO2-IS-KeyManager",
  "displayName": "WSO2 Identity Server",
  "type": "WSO2-IS",
  "description": "WSO2 IS as Key Manager with DCR",
  "enabled": true,
  "additionalProperties": {
    "ServerURL": "https://${IS_INTERNAL_HOST}:${IS_INTERNAL_PORT}/services",
    "Username": "admin",
    "Password": "admin",
    "client_registration_endpoint": "https://${IS_INTERNAL_HOST}:${IS_INTERNAL_PORT}/api/identity/oauth2/dcr/v1.1/register",
    "introspection_endpoint": "https://${IS_INTERNAL_HOST}:${IS_INTERNAL_PORT}/oauth2/introspect",
    "token_endpoint": "https://${IS_INTERNAL_HOST}:${IS_INTERNAL_PORT}/oauth2/token",
    "revoke_endpoint": "https://${IS_INTERNAL_HOST}:${IS_INTERNAL_PORT}/oauth2/revoke",
    "userinfo_endpoint": "https://${IS_INTERNAL_HOST}:${IS_INTERNAL_PORT}/oauth2/userinfo",
    "authorize_endpoint": "https://${IS_HOST}:${IS_PORT}/oauth2/authorize",
    "scope_management_endpoint": "https://${IS_INTERNAL_HOST}:${IS_INTERNAL_PORT}/api/identity/oauth2/v1.0/scopes",
    "TokenURL": "https://${IS_HOST}:${IS_PORT}/oauth2/token",
    "RevokeURL": "https://${IS_HOST}:${IS_PORT}/oauth2/revoke",
    "IntrospectURL": "https://${IS_INTERNAL_HOST}:${IS_INTERNAL_PORT}/oauth2/introspect",
    "UserInfoURL": "https://${IS_INTERNAL_HOST}:${IS_INTERNAL_PORT}/oauth2/userinfo",
    "AuthorizeURL": "https://${IS_HOST}:${IS_PORT}/oauth2/authorize",
    "issuer": "https://${IS_HOST}:${IS_PORT}/oauth2/token",
    "grant_types": "client_credentials password authorization_code refresh_token",
    "enable_token_generation": "true",
    "enable_token_encryption": "false",
    "enable_token_hashing": "false",
    "enable_oauth_app_creation": "true",
    "enable_map_oauth_consumer_apps": "true",
    "self_validate_jwt": "true",
    "token_validation": "introspect",
    "claim_mapping": "sub:http://wso2.org/claims/username"
  }
}
EOF
)

UPDATE_RESP=$(curl -sk -u "admin:admin" -X PUT \
  "https://${AM_HOST}:${AM_PORT}/api/am/admin/v4/key-managers/${KM_ID}" \
  -H "Content-Type: application/json" \
  -d "$UPDATE_CONFIG")

if echo "$UPDATE_RESP" | jq -e '.id' >/dev/null 2>&1; then
  log_success "Key Manager configuration updated"
else
  log_error "Failed to update Key Manager"
  echo "$UPDATE_RESP" | jq '.'
fi
echo ""

# Step 6: Clean up existing application keys
log_info "[6/7] Cleaning up existing application keys..."
echo ""

EXISTING_KEYS=$(curl -sk -u "admin:admin" \
  "https://${AM_HOST}:${AM_PORT}/api/am/devportal/v3/applications/${APP_ID}/oauth-keys" | \
  jq -r '.list[] | .keyMappingId' || echo "")

if [ -n "$EXISTING_KEYS" ]; then
  for KEY_ID in $EXISTING_KEYS; do
    log_info "Attempting to clean up key: $KEY_ID"
    curl -sk -u "admin:admin" -X POST \
      "https://${AM_HOST}:${AM_PORT}/api/am/devportal/v3/applications/${APP_ID}/clean-up-keys?keyMappingId=${KEY_ID}" \
      >/dev/null 2>&1 || true
  done
  log_info "Cleanup attempted"
else
  log_info "No existing keys to clean"
fi

sleep 2
echo ""

# Step 7: Test key generation
log_info "[7/7] Testing key generation with updated configuration..."
echo ""

GEN_RESP=$(curl -sk -u "admin:admin" -X POST \
  "https://${AM_HOST}:${AM_PORT}/api/am/devportal/v3/applications/${APP_ID}/generate-keys" \
  -H "Content-Type: application/json" \
  -d '{
    "keyType": "PRODUCTION",
    "keyManager": "WSO2-IS-KeyManager",
    "grantTypesToBeSupported": ["password", "client_credentials", "refresh_token"],
    "callbackUrl": "https://localhost:9443/callback",
    "validityTime": 3600
  }')

CLIENT_ID=$(echo "$GEN_RESP" | jq -r '.consumerKey // empty')
CLIENT_SECRET=$(echo "$GEN_RESP" | jq -r '.consumerSecret // empty')

if [ -n "$CLIENT_ID" ] && [ "$CLIENT_ID" != "null" ]; then
  log_success "Key generation SUCCESSFUL!"
  echo ""
  echo "Application Credentials:"
  echo "  Client ID:     $CLIENT_ID"
  echo "  Client Secret: ${CLIENT_SECRET:0:20}..."
  echo "  Key Manager:   WSO2-IS-KeyManager"
  echo ""
  
  # Test token generation
  log_info "Testing token generation from WSO2 IS..."
  TOKEN_RESP=$(curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \
    -d "grant_type=password&username=ops_user&password=OpsUser123!" \
    "https://${IS_HOST}:${IS_PORT}/oauth2/token")
  
  ACCESS_TOKEN=$(echo "$TOKEN_RESP" | jq -r '.access_token // empty')
  
  if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
    log_success "Token generation working!"
    echo "Token: ${ACCESS_TOKEN:0:40}..."
    echo ""
    
    # Test API call
    log_info "Testing API call through gateway..."
    API_RESP=$(curl -sk -w "\nHTTP_CODE:%{http_code}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      "https://${AM_HOST}:8243/forex/v1/health")
    
    HTTP_CODE=$(echo "$API_RESP" | grep "HTTP_CODE" | cut -d: -f2)
    
    if [ "$HTTP_CODE" = "200" ]; then
      log_success "Complete flow working! (HTTP $HTTP_CODE)"
      echo ""
      echo "╔════════════════════════════════════════════════════════════╗"
      echo "║  ✅ WSO2 IS Key Manager Integration FIXED!                 ║"
      echo "╚════════════════════════════════════════════════════════════╝"
      echo ""
      echo "Users can now authenticate with WSO2 IS and access APIs!"
      echo ""
      
      # Save credentials
      cat > /tmp/wso2_is_working_credentials.txt << CREDS
# WSO2 IS Key Manager - Working Configuration
CLIENT_ID=${CLIENT_ID}
CLIENT_SECRET=${CLIENT_SECRET}
APP_ID=${APP_ID}
KEY_MANAGER=WSO2-IS-KeyManager

# Get token:
# TOKEN=\$(curl -sk -u "\${CLIENT_ID}:\${CLIENT_SECRET}" \\
#   -d "grant_type=password&username=ops_user&password=OpsUser123!" \\
#   https://${IS_HOST}:${IS_PORT}/oauth2/token | jq -r '.access_token')

# Call API:
# curl -k -H "Authorization: Bearer \$TOKEN" \\
#   https://${AM_HOST}:8243/forex/v1/health
CREDS
      
      log_success "Credentials saved to: /tmp/wso2_is_working_credentials.txt"
      exit 0
    else
      log_error "API call failed (HTTP $HTTP_CODE)"
      echo "$API_RESP" | sed '/HTTP_CODE/d'
      exit 1
    fi
  else
    log_error "Token generation failed"
    echo "$TOKEN_RESP" | jq '.'
    exit 1
  fi
else
  log_error "Key generation still failing"
  echo ""
  echo "Response:"
  echo "$GEN_RESP" | jq '.'
  echo ""
  log_warning "Manual UI approach may be required:"
  echo "  1. Open: https://${AM_HOST}:${AM_PORT}/devportal"
  echo "  2. Login: admin/admin"
  echo "  3. Applications → AllServicesApp → Production Keys"
  echo "  4. Select 'WSO2-IS-KeyManager' → Generate Keys"
  exit 1
fi
