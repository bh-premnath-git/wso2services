#!/usr/bin/env bash

################################################################################
# Setup WSO2 IS as External Key Manager in API Manager
#
# This is the DEFINITIVE script for configuring WSO2 Identity Server as the
# external Key Manager in WSO2 API Manager.
#
# What it does:
# 1. Checks if WSO2 IS and APIM are running
# 2. Checks if Key Manager already exists
# 3. Creates or updates the Key Manager configuration
# 4. Validates the configuration
#
# Usage: ./setup_wso2is_keymanager.sh
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
WSO2_IS_HOST="${WSO2_IS_HOST:-wso2is}"
WSO2_IS_PORT="${WSO2_IS_PORT:-9443}"
WSO2_IS_EXTERNAL="${WSO2_IS_EXTERNAL:-localhost:9444}"
WSO2_AM_HOST="${WSO2_AM_HOST:-localhost}"
WSO2_AM_PORT="${WSO2_AM_PORT:-9443}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin}"
KM_NAME="WSO2-IS-KeyManager"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

print_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Setup WSO2 IS as External Key Manager                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

################################################################################
# Step 1: Health Checks
################################################################################
print_header "Step 1: Health Checks"

log_info "Checking WSO2 Identity Server..."
if ! curl -sk --max-time 10 \
    "https://${WSO2_IS_EXTERNAL}/oauth2/token/.well-known/openid-configuration" > /dev/null 2>&1; then
    log_error "WSO2 IS is not accessible at https://${WSO2_IS_EXTERNAL}"
    log_error "Make sure WSO2 IS is running: docker compose ps wso2is"
    exit 1
fi
log_success "WSO2 IS is running"

log_info "Checking WSO2 API Manager..."
if ! curl -sk --max-time 10 -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "https://${WSO2_AM_HOST}:${WSO2_AM_PORT}/api/am/admin/v4/key-managers" > /dev/null 2>&1; then
    log_error "WSO2 APIM is not accessible at https://${WSO2_AM_HOST}:${WSO2_AM_PORT}"
    log_error "Make sure WSO2 APIM is running: docker compose ps wso2am"
    exit 1
fi
log_success "WSO2 APIM is running"
echo ""

################################################################################
# Step 2: Check Existing Key Manager
################################################################################
print_header "Step 2: Check for Existing Key Manager"

log_info "Fetching Key Manager list..."
KM_LIST=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "https://${WSO2_AM_HOST}:${WSO2_AM_PORT}/api/am/admin/v4/key-managers" 2>/dev/null)

EXISTING_KM_ID=$(echo "$KM_LIST" | grep -o "\"id\":\"[^\"]*\"[^}]*\"name\":\"${KM_NAME}\"" | grep -o "\"id\":\"[^\"]*\"" | cut -d'"' -f4 || echo "")

if [ -n "$EXISTING_KM_ID" ]; then
    log_warning "Key Manager '${KM_NAME}' already exists (ID: ${EXISTING_KM_ID})"
    
    read -p "Do you want to UPDATE it? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Keeping existing Key Manager"
        log_info "To validate, run: ./app_scripts/check_keymanager.sh"
        exit 0
    fi
    
    ACTION="UPDATE"
    KM_ID="$EXISTING_KM_ID"
    log_info "Will update existing Key Manager"
else
    ACTION="CREATE"
    log_info "No existing Key Manager found - will create new one"
fi
echo ""

################################################################################
# Step 3: Prepare Key Manager Configuration
################################################################################
print_header "Step 3: Prepare Configuration"

log_info "Building Key Manager configuration..."

# Key Manager JSON payload (APIM 4.5.0 format)
KM_CONFIG=$(cat <<EOF
{
  "name": "${KM_NAME}",
  "displayName": "WSO2 Identity Server 7.1",
  "type": "WSO2-IS",
  "description": "WSO2 Identity Server 7.1 as external OAuth2 Key Manager",
  "wellKnownEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/token/.well-known/openid-configuration",
  "introspectionEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/introspect",
  "clientRegistrationEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/api/identity/oauth2/dcr/v1.1/register",
  "tokenEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/token",
  "revokeEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/revoke",
  "userInfoEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/userinfo",
  "authorizeEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/authorize",
  "scopeManagementEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/api/identity/oauth2/v1.0/scopes",
  "issuer": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/token",
  "certificates": {
    "type": "JWKS",
    "value": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/jwks"
  },
  "availableGrantTypes": [
    "client_credentials",
    "password",
    "refresh_token",
    "authorization_code"
  ],
  "enableTokenGeneration": true,
  "enableTokenEncryption": false,
  "enableTokenHashing": false,
  "enableMapOAuthConsumerApps": true,
  "enableOAuthAppCreation": true,
  "enableSelfValidationJWT": false,
  "claimMapping": [
    {
      "remoteClaim": "sub",
      "localClaim": "http://wso2.org/claims/enduser"
    }
  ],
  "tokenValidation": [
    {
      "enable": true,
      "type": "REFERENCE",
      "value": "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}"
    }
  ],
  "additionalProperties": {
    "ServerURL": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/services",
    "Username": "${ADMIN_USER}",
    "Password": "${ADMIN_PASS}",
    "VALIDITY_PERIOD": "3600",
    "validation_enable": true,
    "self_validate_jwt": false
  },
  "enabled": true,
  "tokenType": "DIRECT"
}
EOF
)

log_success "Configuration prepared"
echo ""

################################################################################
# Step 4: Create or Update Key Manager
################################################################################
print_header "Step 4: ${ACTION} Key Manager"

if [ "$ACTION" = "CREATE" ]; then
    log_info "Creating new Key Manager..."
    
    RESPONSE=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$KM_CONFIG" \
        -w "\n%{http_code}" \
        "https://${WSO2_AM_HOST}:${WSO2_AM_PORT}/api/am/admin/v4/key-managers" 2>&1)
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ]; then
        KM_ID=$(echo "$BODY" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
        log_success "Key Manager created successfully"
        log_info "ID: ${KM_ID}"
    else
        log_error "Failed to create Key Manager (HTTP ${HTTP_CODE})"
        echo "$BODY"
        exit 1
    fi
    
else
    log_info "Updating existing Key Manager (ID: ${KM_ID})..."
    
    RESPONSE=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -X PUT \
        -H "Content-Type: application/json" \
        -d "$KM_CONFIG" \
        -w "\n%{http_code}" \
        "https://${WSO2_AM_HOST}:${WSO2_AM_PORT}/api/am/admin/v4/key-managers/${KM_ID}" 2>&1)
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        log_success "Key Manager updated successfully"
    else
        log_error "Failed to update Key Manager (HTTP ${HTTP_CODE})"
        echo "$BODY"
        exit 1
    fi
fi
echo ""

################################################################################
# Step 5: Validate Configuration
################################################################################
print_header "Step 5: Validate Configuration"

log_info "Fetching Key Manager details..."
KM_DETAILS=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "https://${WSO2_AM_HOST}:${WSO2_AM_PORT}/api/am/admin/v4/key-managers/${KM_ID}" 2>/dev/null)

# Extract key fields
TOKEN_EP=$(echo "$KM_DETAILS" | grep -o '"tokenEndpoint":"[^"]*' | cut -d'"' -f4)
INTROSPECT_EP=$(echo "$KM_DETAILS" | grep -o '"introspectionEndpoint":"[^"]*' | cut -d'"' -f4)
ENABLED=$(echo "$KM_DETAILS" | grep -o '"enabled":[^,}]*' | cut -d':' -f2 | tr -d ' ')
TOKEN_TYPE=$(echo "$KM_DETAILS" | grep -o '"tokenType":"[^"]*' | cut -d'"' -f4)

echo ""
log_info "Configuration Summary:"
echo "  Name: ${KM_NAME}"
echo "  ID: ${KM_ID}"
echo "  Token Endpoint: ${TOKEN_EP}"
echo "  Introspection Endpoint: ${INTROSPECT_EP}"
echo "  Token Type: ${TOKEN_TYPE}"
echo "  Enabled: ${ENABLED}"
echo ""

# Validate endpoints point to WSO2 IS
if echo "$TOKEN_EP" | grep -q "${WSO2_IS_HOST}"; then
    log_success "Token endpoint correctly configured"
else
    log_warning "Token endpoint may not point to WSO2 IS"
fi

if echo "$INTROSPECT_EP" | grep -q "${WSO2_IS_HOST}"; then
    log_success "Introspection endpoint correctly configured"
else
    log_warning "Introspection endpoint may not point to WSO2 IS"
fi

if [ "$ENABLED" = "true" ]; then
    log_success "Key Manager is enabled"
else
    log_error "Key Manager is DISABLED"
fi

echo ""
print_header "Setup Complete"
echo ""
log_success "WSO2 IS Key Manager is now configured!"
echo ""
echo "What was configured:"
echo "  ✅ Key Manager: ${KM_NAME}"
echo "  ✅ Token endpoint: WSO2 IS OAuth2 server"
echo "  ✅ Validation method: Token introspection"
echo "  ✅ Grant types: client_credentials, password, refresh_token, authorization_code"
echo ""
echo "Next steps:"
echo "  1. Validate: ./app_scripts/check_keymanager.sh"
echo "  2. Test integration: ./app_scripts/test_wso2is_integration.sh"
echo "  3. Create application keys with IS users"
echo ""
echo "Users can now:"
echo "  • Authenticate with WSO2 IS (ops_user, finance, etc.)"
echo "  • Get OAuth tokens from WSO2 IS"
echo "  • Access APIs via API Manager Gateway"
echo ""
