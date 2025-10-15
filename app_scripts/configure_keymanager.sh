#!/bin/bash

################################################################################
# Configure WSO2 Identity Server as External Key Manager in API Manager
#
# This script automatically configures WSO2 IS as an external Key Manager
# in WSO2 API Manager for OAuth2 token validation and management.
#
# Usage: ./configure_keymanager.sh
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
WSO2_AM_HOST="${WSO2_AM_HOST:-localhost}"
WSO2_AM_PORT="${WSO2_AM_PORT:-9443}"
WSO2_IS_HOST="${WSO2_IS_HOST:-wso2is}"  # Internal Docker network hostname
WSO2_IS_PORT="${WSO2_IS_PORT:-9443}"    # Internal port (not host port 9444)
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin}"
KEY_MANAGER_NAME="${KEY_MANAGER_NAME:-WSO2-IS-KeyManager}"

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  WSO2 Identity Server Key Manager Configuration           ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

################################################################################
# Check Prerequisites
################################################################################
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Please install curl."
        exit 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. JSON output will not be formatted."
        JQ_AVAILABLE=false
    else
        JQ_AVAILABLE=true
    fi
    
    # Check WSO2 AM is running
    if ! curl -k -s -o /dev/null -w "%{http_code}" "https://${WSO2_AM_HOST}:${WSO2_AM_PORT}/carbon/" | grep -q "302\|200"; then
        log_error "WSO2 API Manager is not accessible at https://${WSO2_AM_HOST}:${WSO2_AM_PORT}"
        log_error "Please ensure WSO2 AM is running: docker compose up -d wso2am"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

################################################################################
# Get Existing Key Managers
################################################################################
get_key_managers() {
    log_info "Fetching existing Key Managers..."
    
    RESPONSE=$(curl -k -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
        "https://${WSO2_AM_HOST}:${WSO2_AM_PORT}/api/am/admin/v4/key-managers" 2>&1)
    
    if [ $? -ne 0 ]; then
        log_error "Failed to fetch Key Managers"
        return 1
    fi
    
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$RESPONSE" | jq .
    else
        echo "$RESPONSE"
    fi
    
    # Check if WSO2 IS Key Manager already exists
    if echo "$RESPONSE" | grep -q "\"name\":.*\"${KEY_MANAGER_NAME}\""; then
        log_warning "Key Manager '${KEY_MANAGER_NAME}' already exists"
        
        # Extract Key Manager ID
        if [ "$JQ_AVAILABLE" = true ]; then
            EXISTING_KM_ID=$(echo "$RESPONSE" | jq -r ".list[] | select(.name==\"${KEY_MANAGER_NAME}\") | .id")
            echo ""
            log_info "Existing Key Manager ID: ${EXISTING_KM_ID}"
        fi
        
        return 2
    fi
    
    return 0
}

################################################################################
# Create WSO2 IS Key Manager
################################################################################
create_key_manager() {
    log_info "Creating WSO2 Identity Server as External Key Manager..."
    
    # Prepare JSON payload
    PAYLOAD=$(cat <<EOF
{
  "name": "${KEY_MANAGER_NAME}",
  "displayName": "WSO2 Identity Server",
  "type": "WSO2-IS",
  "description": "WSO2 Identity Server 7.1 as external Key Manager for OAuth2 token management",
  "enabled": true,
  "introspectionEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/introspect",
  "clientRegistrationEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/api/identity/oauth2/dcr/v1.1/register",
  "tokenEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/token",
  "revokeEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/revoke",
  "userInfoEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/userinfo",
  "authorizeEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/authorize",
  "scopeManagementEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/api/identity/oauth2/v1.0/scopes",
  "issuer": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/token",
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
  "enableSelfValidationJWT": true,
  "claimMapping": [
    {
      "remoteClaim": "sub",
      "localClaim": "http://wso2.org/claims/username"
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
    "ServerURL": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/services/",
    "Username": "${ADMIN_USER}",
    "Password": "${ADMIN_PASS}",
    "VALIDITY_PERIOD": "3600",
    "self_validate_jwt": true,
    "enable_token_generation": true
  },
  "tokenType": "DIRECT"
}
EOF
)
    
    # Create Key Manager
    RESPONSE=$(curl -k -s -w "\nHTTP_CODE:%{http_code}" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -X POST "https://${WSO2_AM_HOST}:${WSO2_AM_PORT}/api/am/admin/v4/key-managers" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" 2>&1)
    
    HTTP_CODE=$(echo "$RESPONSE" | grep -o 'HTTP_CODE:[0-9]*' | cut -d':' -f2)
    RESPONSE_BODY=$(echo "$RESPONSE" | sed 's/HTTP_CODE:[0-9]*//')
    
    if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ]; then
        log_success "Key Manager created successfully!"
        echo ""
        log_info "Response:"
        
        if [ "$JQ_AVAILABLE" = true ]; then
            echo "$RESPONSE_BODY" | jq .
            KM_ID=$(echo "$RESPONSE_BODY" | jq -r '.id')
            KM_NAME=$(echo "$RESPONSE_BODY" | jq -r '.name')
        else
            echo "$RESPONSE_BODY"
            KM_ID=$(echo "$RESPONSE_BODY" | grep -o '"id":"[^"]*' | cut -d'"' -f4 | head -1)
            KM_NAME=$(echo "$RESPONSE_BODY" | grep -o '"name":"[^"]*' | cut -d'"' -f4 | head -1)
        fi
        
        echo ""
        log_success "Key Manager ID: ${KM_ID}"
        log_success "Key Manager Name: ${KM_NAME}"
        
        return 0
    else
        log_error "Failed to create Key Manager (HTTP ${HTTP_CODE})"
        log_error "Response: ${RESPONSE_BODY}"
        return 1
    fi
}

################################################################################
# Verify Key Manager Configuration
################################################################################
verify_key_manager() {
    log_info "Verifying Key Manager configuration..."
    
    RESPONSE=$(curl -k -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
        "https://${WSO2_AM_HOST}:${WSO2_AM_PORT}/api/am/admin/v4/key-managers" 2>&1)
    
    if echo "$RESPONSE" | grep -q "\"name\":.*\"${KEY_MANAGER_NAME}\""; then
        log_success "Key Manager '${KEY_MANAGER_NAME}' is configured and active"
        
        if [ "$JQ_AVAILABLE" = true ]; then
            echo ""
            log_info "Key Manager Details:"
            echo "$RESPONSE" | jq ".list[] | select(.name==\"${KEY_MANAGER_NAME}\")"
        fi
        
        return 0
    else
        log_error "Key Manager '${KEY_MANAGER_NAME}' not found in configuration"
        return 1
    fi
}

################################################################################
# Update Existing Key Manager
################################################################################
update_key_manager() {
    local KM_ID=$1
    
    log_info "Updating existing Key Manager (ID: ${KM_ID})..."
    
    PAYLOAD=$(cat <<EOF
{
  "name": "${KEY_MANAGER_NAME}",
  "displayName": "WSO2 Identity Server",
  "type": "WSO2-IS",
  "description": "WSO2 Identity Server 7.1 as external Key Manager for OAuth2 token management",
  "enabled": true,
  "introspectionEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/introspect",
  "clientRegistrationEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/api/identity/oauth2/dcr/v1.1/register",
  "tokenEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/token",
  "revokeEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/revoke",
  "userInfoEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/userinfo",
  "authorizeEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/authorize",
  "scopeManagementEndpoint": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/api/identity/oauth2/v1.0/scopes",
  "issuer": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/token",
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
  "enableSelfValidationJWT": true,
  "claimMapping": [
    {
      "remoteClaim": "sub",
      "localClaim": "http://wso2.org/claims/username"
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
    "ServerURL": "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/services/",
    "Username": "${ADMIN_USER}",
    "Password": "${ADMIN_PASS}",
    "VALIDITY_PERIOD": "3600",
    "self_validate_jwt": true,
    "enable_token_generation": true
  },
  "tokenType": "DIRECT"
}
EOF
)
    
    RESPONSE=$(curl -k -s -w "\nHTTP_CODE:%{http_code}" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -X PUT "https://${WSO2_AM_HOST}:${WSO2_AM_PORT}/api/am/admin/v4/key-managers/${KM_ID}" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" 2>&1)
    
    HTTP_CODE=$(echo "$RESPONSE" | grep -o 'HTTP_CODE:[0-9]*' | cut -d':' -f2)
    
    if [ "$HTTP_CODE" = "200" ]; then
        log_success "Key Manager updated successfully!"
        return 0
    else
        log_error "Failed to update Key Manager (HTTP ${HTTP_CODE})"
        return 1
    fi
}

################################################################################
# Main Execution
################################################################################
main() {
    print_header
    
    check_prerequisites
    
    echo ""
    get_key_managers
    KM_STATUS=$?
    
    echo ""
    if [ $KM_STATUS -eq 2 ]; then
        # Key Manager already exists
        read -p "Key Manager already exists. Update it? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [ -n "$EXISTING_KM_ID" ]; then
                update_key_manager "$EXISTING_KM_ID"
            else
                log_error "Could not determine existing Key Manager ID"
                exit 1
            fi
        else
            log_info "Skipping update. Key Manager configuration unchanged."
            exit 0
        fi
    else
        # Create new Key Manager
        create_key_manager
    fi
    
    echo ""
    verify_key_manager
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Configuration Complete                                    ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "WSO2 Identity Server is now configured as an external Key Manager"
    log_info "You can now create OAuth applications in WSO2 IS and use them with API Manager"
    echo ""
    log_info "Next steps:"
    echo "  1. Create an OAuth application in WSO2 IS"
    echo "  2. Use the client credentials to generate access tokens"
    echo "  3. Use tokens to call APIs published in API Manager"
    echo ""
    log_info "Run validation: ./app_scripts/check_keymanager.sh"
}

# Run main function
main "$@"
