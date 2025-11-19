#!/usr/bin/env bash

################################################################################
# Configure WSO2 IS as Key Manager in APIM
# Registers WSO2 IS 7.1.0 as a Key Manager in WSO2 APIM 4.6.0
################################################################################

set -euo pipefail

# Configuration
APIM_HOST="${APIM_HOST:-localhost}"
APIM_PORT="${APIM_PORT:-9443}" # External port for APIM
IS_HOST_EXT="${IS_HOST_EXT:-localhost}"
IS_PORT_EXT="${IS_PORT_EXT:-9444}" # External port for IS

# Internal Docker Network Configuration (used by APIM to reach IS)
IS_HOST_INT="${IS_HOST_INT:-is-as-km}"
IS_PORT_INT="${IS_PORT_INT:-9443}"

ADMIN_USER="admin"
ADMIN_PASS="admin"

# KM Configuration
KM_NAME="WSO2IS"
KM_TYPE="WSO2-IS" # Standard type for WSO2 IS connector
KM_DISPLAY_NAME="WSO2 Identity Server 7.1.0"
KM_DESC="WSO2 IS 7.1.0 Key Manager (Auto-configured)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "╔════════════════════════════════════════════════════════════╗"
echo "║       Configuring WSO2 IS as Key Manager in APIM           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check if APIM is reachable
echo -n "Checking APIM availability..."
if curl -k -s -o /dev/null "https://${APIM_HOST}:${APIM_PORT}/services/Version"; then
    echo -e "${GREEN} OK${NC}"
else
    echo -e "${RED} FAIL${NC}"
    echo "APIM is not reachable at https://${APIM_HOST}:${APIM_PORT}"
    exit 1
fi

# Check if KM already exists
echo -n "Checking for existing Key Manager '${KM_NAME}'..."
KM_EXISTS=$(curl -k -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "https://${APIM_HOST}:${APIM_PORT}/api/am/admin/v4/key-managers" | \
    jq -r ".list[] | select(.name == \"${KM_NAME}\") | .id")

if [ -n "$KM_EXISTS" ] && [ "$KM_EXISTS" != "null" ]; then
    echo -e "${GREEN} FOUND${NC}"
    
    # Check if it's enabled
    KM_ENABLED=$(curl -k -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
        "https://${APIM_HOST}:${APIM_PORT}/api/am/admin/v4/key-managers/${KM_EXISTS}" | \
        jq -r '.enabled')
    
    if [ "$KM_ENABLED" = "true" ]; then
        echo -e "${GREEN}Key Manager '${KM_NAME}' is already configured and enabled (ID: ${KM_EXISTS})${NC}"
        echo "Skipping configuration - Key Manager is ready to use."
        exit 0
    else
        echo -e "${YELLOW}Key Manager exists but is disabled. Enabling...${NC}"
        # Enable the Key Manager by updating only the enabled field
        RESPONSE=$(curl -k -s -X PUT \
            "https://${APIM_HOST}:${APIM_PORT}/api/am/admin/v4/key-managers/${KM_EXISTS}" \
            -u "${ADMIN_USER}:${ADMIN_PASS}" \
            -H "Content-Type: application/json" \
            -d '{"enabled": true}')
        
        if echo "$RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
            echo -e "${GREEN}Key Manager enabled successfully!${NC}"
            exit 0
        else
            echo -e "${RED}Failed to enable Key Manager!${NC}"
            echo "Response: $RESPONSE"
            exit 1
        fi
    fi
fi

echo -e "${YELLOW} NOT FOUND${NC}"

echo "Registering '${KM_NAME}'..."

# Use internal docker hostname/port for the service URL
IS_SERVICE_URL="https://${IS_HOST_INT}:${IS_PORT_INT}/services/"
IS_BASE_URL="https://${IS_HOST_INT}:${IS_PORT_INT}"

PAYLOAD=$(cat <<EOF
{
  "name": "${KM_NAME}",
  "type": "OAuth2",
  "displayName": "${KM_DISPLAY_NAME}",
  "description": "${KM_DESC}",
  "enabled": true,
  "additionalProperties": {
    "client_registration_endpoint": "${IS_BASE_URL}/api/identity/oauth2/dcr/v1.1/register",
    "introspection_endpoint": "${IS_BASE_URL}/oauth2/introspect",
    "token_endpoint": "${IS_BASE_URL}/oauth2/token",
    "revoke_endpoint": "${IS_BASE_URL}/oauth2/revoke",
    "userinfo_endpoint": "${IS_BASE_URL}/oauth2/userinfo",
    "authorize_endpoint": "${IS_BASE_URL}/oauth2/authorize",
    "jwks_endpoint": "${IS_BASE_URL}/oauth2/jwks",
    "scope_management_endpoint": "${IS_BASE_URL}/api/identity/oauth2/v1.0/scopes",
    "grant_types": "password,client_credentials,refresh_token,authorization_code,implicit",
    "Username": "${ADMIN_USER}",
    "Password": "${ADMIN_PASS}"
  }
}
EOF
)

RESPONSE=$(curl -k -s -X POST \
    "https://${APIM_HOST}:${APIM_PORT}/api/am/admin/v4/key-managers" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

if echo "$RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
    NEW_KM_ID=$(echo "$RESPONSE" | jq -r '.id')
    echo -e "${GREEN}SUCCESS!${NC}"
    echo "Registered Key Manager '${KM_NAME}' with ID: ${NEW_KM_ID}"
else
    echo -e "${RED}FAILED!${NC}"
    echo "Response: $RESPONSE"
    exit 1
fi
