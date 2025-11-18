#!/usr/bin/env bash

################################################################################
# WSO2 Complete Toolkit - ONE FILE FOR EVERYTHING
#
# This script handles ALL WSO2 operations:
# 1. Health checks
# 2. Key Manager setup (all OAuth 2.0 grant types)
# 3. Token generation for ALL grant types
# 4. Testing and validation
#
# Usage: ./wso2-toolkit.sh <command> [options]
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Auto-detect WSO2 versions (detect once when needed - use latest version)
get_wso2am_home() {
    docker exec wso2am bash -c "ls -d /home/wso2carbon/wso2am-* 2>/dev/null | sort -V | tail -1" 2>/dev/null || echo "/home/wso2carbon/wso2am-4.6.0"
}

################################################################################
# COMMAND: km-manual-guide - Print Admin Portal checklist for KM setup
################################################################################

cmd_km_manual_guide() {
    cat <<'EOF'

═══════════════════════════════════════════════════════════════════════════════
WSO2 IS 7.x Key Manager – Admin Portal Checklist
Reference: https://apim.docs.wso2.com/en/latest/administer/key-managers/configure-wso2is7-connector/
═══════════════════════════════════════════════════════════════════════════════

Prerequisites:
  • Containers running (docker compose up -d)
  • Certificates exchanged (run ./scripts/truststorekey.sh trust)

Steps:
1. Access Admin Portal → https://localhost:9443/admin → Key Managers → Add Key Manager.
2. Provide Name / Display Name (e.g., "WSO2 Identity Server 7"). Select Key Manager Type "WSO2 Identity Server 7".
3. In Key Manager Endpoints, DO NOT use well-known URL import (doesn't work with docker port mapping).
   Enter these values MANUALLY:
     Issuer                      : https://is-as-km:9443/oauth2/token
     Client Registration Endpoint: https://is-as-km:9443/api/identity/oauth2/dcr/v1.1/register
     Introspection Endpoint      : https://is-as-km:9443/oauth2/introspect
     Token Endpoint              : https://is-as-km:9443/oauth2/token
     Display Token Endpoint      : https://is-as-km:9443/oauth2/token
     Revoke Endpoint             : https://is-as-km:9443/oauth2/revoke
     Display Revoke Endpoint     : https://is-as-km:9443/oauth2/revoke
     UserInfo Endpoint           : https://is-as-km:9443/scim2/Me
     Authorize Endpoint          : https://is-as-km:9443/oauth2/authorize
     Scope Management Endpoint   : https://is-as-km:9443/api/identity/oauth2/v1.0/scopes
   
   NOTE: Use 'is-as-km:9443' (docker network name), NOT 'localhost:9444'
4. Claim URIs:
     Consumer Key Claim URI: azp
     Scopes Claim URI: scope
5. Grant Types → enable ALL of the following:
     password, client_credentials, refresh_token,
     authorization_code, implicit,
     urn:ietf:params:oauth:grant-type:saml2-bearer,
     iwa:ntlm,
     urn:ietf:params:oauth:grant-type:device_code,
     urn:ietf:params:oauth:grant-type:jwt-bearer,
     urn:ietf:params:oauth:grant-type:token-exchange.
6. Certificates section → Type: JWKS, URL: https://is-as-km:9443/oauth2/jwks
7. Connector Configurations:
   
   OPTION A - Basic Authentication (Default):
     Authentication Type: Basic
     Username / Password: admin / admin (tenant-qualified user with required permissions)
     API Resource Management Endpoint: https://is-as-km:9443/api/server/v1/api-resources
     Roles Endpoint: https://is-as-km:9443/scim2/v2/Roles
     Enable "Create roles in WSO2 Identity Server 7" if APIM must create system_primary roles
       (deployment.toml already has [role_mgt] allow_system_prefix_for_role = true).
   
   OPTION B - Mutual TLS (Production):
     Authentication Type: Mutual SSL
     Certificate Type: Server (or Tenant based on your setup)
     Identity Username: admin@carbon.super (tenant-qualified user)
     Requirements:
       • APIM and IS must trust each other's certificates (run truststorekey.sh trust)
       • IS must map the client cert to the identity username
       • All endpoints must support client certificate authentication
     Note: The setup-km script does NOT configure mTLS - you must do this manually.
8. Advanced Configurations:
     ☑️ Token Generation: CHECKED
     ☑️ Out Of Band Provisioning: CHECKED
     ☑️ Oauth App Creation: CHECKED
     Token Validation Method: Self validate JWT
     
     Token Handling Options:
       ☐ Token Encryption: UNCHECKED
       ☐ Token Hashing: UNCHECKED
     
     Claim Mappings:
       Remote Claim: sub
       Local Claim: http://wso2.org/claims/enduser
9. Save Key Manager, verify status (Admin Portal or ./scripts/wso2-toolkit.sh list-km).
10. Optionally disable Resident Key Manager: ./scripts/wso2-toolkit.sh disable-resident-km

EOF
}

get_wso2is_home() {
    docker exec is-as-km bash -c "ls -d /home/wso2carbon/wso2is-* 2>/dev/null | sort -V | tail -1" 2>/dev/null || echo "/home/wso2carbon/wso2is-7.2.0"
}

# Configuration
APIM_HOST="${APIM_HOST:-localhost}"
APIM_PORT="${APIM_PORT:-9443}"
APIM_ADMIN_USER="${APIM_ADMIN_USER:-admin}"
APIM_ADMIN_PASS="${APIM_ADMIN_PASS:-admin}"

# CRITICAL: WSO2IS_HOST must match docker-compose service name (is-as-km)
WSO2IS_HOST="${WSO2IS_HOST:-is-as-km}"
WSO2IS_PORT="${WSO2IS_PORT:-9443}"
WSO2IS_EXTERNAL_PORT="${WSO2IS_EXTERNAL_PORT:-9444}"
WSO2IS_ADMIN_USER="${WSO2IS_ADMIN_USER:-admin}"
WSO2IS_ADMIN_PASS="${WSO2IS_ADMIN_PASS:-admin}"

# CRITICAL: This name MUST match 'header.X-WSO2-KEY-MANAGER' in IS deployment.toml
# Current value in deployment.toml: 'header.X-WSO2-KEY-MANAGER' = "WSO2IS"
KEY_MANAGER_NAME="WSO2IS"

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Dependency check
check_dependencies() {
    local missing=0
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Install it with: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
        ((missing++))
    fi
    
    if ! command -v python3 &> /dev/null; then
        log_error "python3 is not installed. Install it with your system package manager"
        ((missing++))
    fi
    
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Install it with your system package manager"
        ((missing++))
    fi
    
    if ! command -v docker &> /dev/null; then
        log_error "docker is not installed. Install it from: https://docs.docker.com/get-docker/"
        ((missing++))
    fi
    
    if [ $missing -gt 0 ]; then
        log_error "Missing $missing required dependencies"
        return 1
    fi
    
    return 0
}

# Input validation
validate_app_name() {
    local name="$1"
    # Allow alphanumeric, underscore, hyphen only
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid application name: '$name'"
        log_error "Only alphanumeric characters, underscores, and hyphens are allowed"
        return 1
    fi
    return 0
}

validate_url() {
    local url="$1"
    # Basic URL validation
    if [[ ! "$url" =~ ^https?:// ]]; then
        log_error "Invalid URL: '$url'"
        log_error "URL must start with http:// or https://"
        return 1
    fi
    return 0
}

validate_role_name() {
    local name="$1"
    # Allow alphanumeric and underscore only
    if [[ ! "$name" =~ ^[a-zA-Z0-9_]+$ ]]; then
        log_error "Invalid role name: '$name'"
        log_error "Only alphanumeric characters and underscores are allowed"
        return 1
    fi
    return 0
}

# Container verification
check_container() {
    local container="$1"
    if ! docker ps --format '{{.Names}}' | grep -q "${container}"; then
        log_error "Container matching '${container}' is not running"
        log_error "Start it with: docker compose up -d"
        return 1
    fi
    return 0
}

# Enhanced curl with retry logic
curl_with_retry() {
    local max_attempts=3
    local timeout=10
    local attempt=1
    local exit_code=0
    
    while [ $attempt -le $max_attempts ]; do
        if [ $attempt -gt 1 ]; then
            log_info "Retry attempt $attempt of $max_attempts..."
            sleep 2
        fi
        
        curl --max-time $timeout "$@"
        exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            return 0
        fi
        
        ((attempt++))
    done
    
    log_error "Failed after $max_attempts attempts"
    return $exit_code
}

# JSON response validation
validate_json_response() {
    local response="$1"
    if ! echo "$response" | python3 -m json.tool >/dev/null 2>&1; then
        log_error "Invalid JSON response received"
        return 1
    fi
    return 0
}

################################################################################
# COMMAND: health - Check all services
################################################################################

cmd_health() {
    echo ""
    echo "=========================================="
    echo "  WSO2 Infrastructure Health Check"
    echo "=========================================="
    echo ""
    
    local errors=0
    
    log_info "Checking Docker containers..."
    for svc in api-manager is-as-km mysql; do
        if docker ps --format '{{.Names}}' | grep -q "${svc}"; then
            log_success "Container matching '${svc}' is running"
        else
            log_error "Container matching '${svc}' is NOT running"
            ((errors++))
        fi
    done
    echo ""
    
    log_info "Checking MySQL databases..."
    local mysql_container=$(docker ps --format '{{.Names}}' | grep mysql | head -1)
    for db in WSO2AM_DB WSO2_IS_DB WSO2AM_SHARED_DB WSO2_IS_SHARED_DB; do
        if docker exec ${mysql_container} mysql -uroot -proot -e "USE ${db}; SELECT 1;" >/dev/null 2>&1; then
            log_success "Database '${db}' OK"
        else
            log_error "Database '${db}' FAILED"
            ((errors++))
        fi
    done
    
    echo ""
    log_info "Checking WSO2 Identity Server..."
    if curl -k -s -o /dev/null -w "%{http_code}" https://localhost:${WSO2IS_EXTERNAL_PORT}/carbon/admin/login.jsp | grep -q "200\|302"; then
        log_success "Console: https://localhost:${WSO2IS_EXTERNAL_PORT}/carbon"
    else
        log_error "WSO2 IS not accessible"
        ((errors++))
    fi
    
    if curl -k -s https://localhost:${WSO2IS_EXTERNAL_PORT}/oauth2/jwks | grep -q "keys"; then
        log_success "JWKS endpoint OK"
    else
        log_warn "JWKS endpoint issue"
    fi
    
    echo ""
    log_info "Checking WSO2 API Manager..."
    if curl -k -s -o /dev/null -w "%{http_code}" https://localhost:${APIM_PORT}/carbon/admin/login.jsp | grep -q "200\|302"; then
        log_success "Console:   https://localhost:${APIM_PORT}/carbon"
        log_success "Publisher: https://localhost:${APIM_PORT}/publisher"
        log_success "DevPortal: https://localhost:${APIM_PORT}/devportal"
        log_success "Gateway:   https://localhost:8243"
    else
        log_error "WSO2 AM not accessible"
        ((errors++))
    fi
    
    # Check Admin REST API
    if curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        "https://${APIM_HOST}:${APIM_PORT}/api/am/admin/v4/key-managers?limit=1" >/dev/null 2>&1; then
        log_success "Admin REST API OK"
    else
        log_warn "Admin REST API not reachable"
    fi
    
    echo ""
    if [ ${errors} -eq 0 ]; then
        log_success "All health checks passed!"
        return 0
    else
        log_error "Health check failed with ${errors} error(s)"
        return 1
    fi
}

################################################################################
# COMMAND: setup-km - Setup WSO2 IS as Key Manager
################################################################################

cmd_setup_km() {
    # Check if containers are running
    check_container "api-manager" || return 1
    check_container "is-as-km" || return 1

    echo ""
    echo "=========================================="
    echo "  Setup WSO2 IS 7.x as Key Manager"
    echo "=========================================="
    echo ""
    log_warn "AUTHENTICATION TYPE: BASIC AUTH"
    log_warn "This script wires IS 7.x as KM using Basic Auth (admin/admin)"
    log_warn "If you want Mutual TLS, do it via Admin Portal – see km-manual-guide"
    echo ""

    local km_api="https://${APIM_HOST}:${APIM_PORT}/api/am/admin/v4/key-managers"
    local km_name="${KEY_MANAGER_NAME}"

    log_info "Checking if '${km_name}' already exists..."
    if curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" "${km_api}?limit=1000" \
        | grep -q "\"name\":\"${km_name}\""; then
        log_warn "Key Manager '${km_name}' already exists – nothing to do"
        return 0
    fi

    # Internal IS endpoints (docker network)
    local token_ep="https://${WSO2IS_HOST}:${WSO2IS_PORT}/oauth2/token"
    local revoke_ep="https://${WSO2IS_HOST}:${WSO2IS_PORT}/oauth2/revoke"
    local introspect_ep="https://${WSO2IS_HOST}:${WSO2IS_PORT}/oauth2/introspect"
    local authorize_ep="https://${WSO2IS_HOST}:${WSO2IS_PORT}/oauth2/authorize"
    local jwks_ep="https://${WSO2IS_HOST}:${WSO2IS_PORT}/oauth2/jwks"
    local userinfo_ep="https://${WSO2IS_HOST}:${WSO2IS_PORT}/scim2/Me"
    local scopes_ep="https://${WSO2IS_HOST}:${WSO2IS_PORT}/api/identity/oauth2/v1.0/scopes"
    local dcr_ep="https://${WSO2IS_HOST}:${WSO2IS_PORT}/api/identity/oauth2/dcr/v1.1/register"
    local issuer="https://${WSO2IS_HOST}:${WSO2IS_PORT}/oauth2/token"
    local api_resources_ep="https://${WSO2IS_HOST}:${WSO2IS_PORT}/api/server/v1/api-resources"
    local roles_ep="https://${WSO2IS_HOST}:${WSO2IS_PORT}/scim2/v2/Roles"
    local server_url="https://${WSO2IS_HOST}:${WSO2IS_PORT}/services"
    local well_known="https://${WSO2IS_HOST}:${WSO2IS_PORT}/oauth2/token/.well-known/openid-configuration"

    ########################################################################
    # Build Key Manager configuration with plain object for additionalProperties
    ########################################################################
    log_info "Building Key Manager configuration..."

    local payload
    payload=$(jq -n \
        --arg name "${km_name}" \
        --arg issuer "${issuer}" \
        --arg token_ep "${token_ep}" \
        --arg revoke_ep "${revoke_ep}" \
        --arg introspect_ep "${introspect_ep}" \
        --arg authorize_ep "${authorize_ep}" \
        --arg userinfo_ep "${userinfo_ep}" \
        --arg scopes_ep "${scopes_ep}" \
        --arg dcr_ep "${dcr_ep}" \
        --arg jwks_ep "${jwks_ep}" \
        --arg username "${WSO2IS_ADMIN_USER}" \
        --arg password "${WSO2IS_ADMIN_PASS}" \
        --arg api_resources_ep "${api_resources_ep}" \
        --arg roles_ep "${roles_ep}" \
        '{
  "name": $name,
  "displayName": "WSO2 Identity Server 7.x",
  "type": "WSO2-IS-7",
  "description": "WSO2 Identity Server 7.x as external OAuth2 Key Manager (Basic Auth)",
  "enabled": true,
  "tokenType": "DIRECT",
  "issuer": $issuer,
  "wellKnownEndpoint": null,
  "introspectionEndpoint": $introspect_ep,
  "clientRegistrationEndpoint": $dcr_ep,
  "tokenEndpoint": $token_ep,
  "displayTokenEndpoint": $token_ep,
  "revokeEndpoint": $revoke_ep,
  "displayRevokeEndpoint": $revoke_ep,
  "userInfoEndpoint": $userinfo_ep,
  "authorizeEndpoint": $authorize_ep,
  "scopeManagementEndpoint": $scopes_ep,
  "consumerKeyClaim": "azp",
  "scopesClaim": "scope",
  "certificates": {
    "type": "JWKS",
    "value": $jwks_ep
  },
  "availableGrantTypes": [
    "password",
    "refresh_token",
    "authorization_code",
    "client_credentials"
  ],
  "enableTokenGeneration": true,
  "enableTokenEncryption": false,
  "enableTokenHashing": false,
  "enableMapOAuthConsumerApps": true,
  "enableOAuthAppCreation": true,
  "enableSelfValidationJWT": true,
  "claimMapping": [],
  "tokenValidation": [],
  "additionalProperties": {
    "enable_roles_creation": true,
    "self_validate_jwt": true,
    "is7_roles_endpoint": $roles_ep,
    "Password": $password,
    "user_schema_cache_enabled": true,
    "Username": $username,
    "Authentication": "BasicAuth",
    "api_resource_management_endpoint": $api_resources_ep
  }
}')

    log_info "Creating Key Manager '${km_name}' via Admin REST API..."

    local response
    response=$(curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        -X POST "${km_api}" 2>&1)

    if echo "${response}" | grep -q '"id"'; then
        log_success "Key Manager '${km_name}' created successfully"
        echo ""
        log_info "Key Manager Details:"
        echo "${response}" | python3 -m json.tool 2>/dev/null || echo "${response}"
        echo ""
        log_info "Next steps:"
        echo "  1. Verify: ./scripts/wso2-toolkit.sh list-km"
        echo "  2. Disable Resident KM: ./scripts/wso2-toolkit.sh disable-resident-km"
        echo "  3. Test health: ./scripts/wso2-toolkit.sh health"
        return 0
    else
        log_error "Failed to create Key Manager"
        echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: update-km - Update existing Key Manager
################################################################################

cmd_update_km() {
    check_container "api-manager" || return 1
    check_container "is-as-km" || return 1
    
    local km_name="${1:-WSO2IS}"
    
    echo ""
    echo "=========================================="
    echo "  Update Key Manager '${km_name}'"
    echo "=========================================="
    echo ""
    
    local km_api="https://${APIM_HOST}:${APIM_PORT}/api/am/admin/v4/key-managers"
    
    log_info "Finding Key Manager '${km_name}'..."
    local response
    response=$(curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" "${km_api}?limit=100" 2>&1)
    
    local km_id
    km_id=$(echo "${response}" | jq -r ".list[] | select(.name == \"${km_name}\") | .id" 2>/dev/null)
    
    if [ -z "${km_id}" ] || [ "${km_id}" = "null" ]; then
        log_error "Key Manager '${km_name}' not found"
        return 1
    fi
    
    log_info "Key Manager ID: ${km_id}"
    
    # Get current configuration
    log_info "Fetching current configuration..."
    local current_config
    current_config=$(curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        "${km_api}/${km_id}" 2>&1)
    
    if ! echo "${current_config}" | grep -q '"name"'; then
        log_error "Failed to fetch Key Manager configuration"
        return 1
    fi
    
    # Update display endpoints if they are null
    log_info "Updating display endpoints..."
    local updated_config
    updated_config=$(echo "${current_config}" | jq '
        .displayTokenEndpoint = .tokenEndpoint |
        .displayRevokeEndpoint = .revokeEndpoint
    ')
    
    # PUT the updated configuration
    response=$(curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d "${updated_config}" \
        -X PUT "${km_api}/${km_id}" 2>&1)
    
    if echo "${response}" | grep -q '"id"'; then
        log_success "Key Manager '${km_name}' updated successfully!"
        echo ""
        log_info "Updated Details:"
        echo "${response}" | python3 -m json.tool 2>/dev/null || echo "${response}"
        echo ""
        log_info "Refresh the Admin Portal page to see the changes"
        return 0
    else
        log_error "Failed to update Key Manager"
        echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: delete-km - Delete a Key Manager
################################################################################

cmd_delete_km() {
    check_container "api-manager" || return 1
    
    local km_name="${1:-}"
    
    if [ -z "${km_name}" ]; then
        log_error "Usage: ./wso2-toolkit.sh delete-km <key_manager_name>"
        return 1
    fi
    
    echo ""
    echo "=========================================="
    echo "  Delete Key Manager '${km_name}'"
    echo "=========================================="
    echo ""
    
    local km_api="https://${APIM_HOST}:${APIM_PORT}/api/am/admin/v4/key-managers"
    
    log_info "Finding Key Manager '${km_name}'..."
    local response
    response=$(curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" "${km_api}?limit=100" 2>&1)
    
    local km_id
    km_id=$(echo "${response}" | jq -r ".list[] | select(.name == \"${km_name}\") | .id" 2>/dev/null)
    
    if [ -z "${km_id}" ] || [ "${km_id}" = "null" ]; then
        log_error "Key Manager '${km_name}' not found"
        return 1
    fi
    
    log_info "Key Manager ID: ${km_id}"
    log_warn "This will delete the Key Manager '${km_name}'"
    
    # DELETE the Key Manager
    local http_code
    http_code=$(curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        -w "%{http_code}" -o /dev/null \
        -X DELETE "${km_api}/${km_id}" 2>&1)
    
    if [ "${http_code}" = "200" ] || [ "${http_code}" = "204" ]; then
        log_success "Key Manager '${km_name}' deleted successfully!"
        return 0
    else
        log_error "Failed to delete Key Manager (HTTP ${http_code})"
        return 1
    fi
}

################################################################################
# COMMAND: list-km - List all Key Managers
################################################################################

cmd_list_km() {
    check_container "api-manager" || return 1
    
    echo ""
    echo "=========================================="
    echo "  Configured Key Managers"
    echo "=========================================="
    echo ""
    
    local km_api="https://${APIM_HOST}:${APIM_PORT}/api/am/admin/v4/key-managers"
    
    log_info "Fetching Key Managers..."
    local response
    response=$(curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" "${km_api}?limit=100" 2>&1)
    
    if echo "${response}" | grep -q '"list"'; then
        echo "${response}" | python3 -m json.tool 2>/dev/null || echo "${response}"
        echo ""
        local count=$(echo "${response}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('count', 0))" 2>/dev/null)
        log_info "Total Key Managers: ${count}"
    else
        log_error "Failed to fetch Key Managers"
        echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: disable-resident-km - Disable Resident Key Manager
################################################################################

cmd_disable_resident_km() {
    check_container "api-manager" || return 1
    
    echo ""
    echo "=========================================="
    echo "  Disable Resident Key Manager"
    echo "=========================================="
    echo ""
    
    local km_api="https://${APIM_HOST}:${APIM_PORT}/api/am/admin/v4/key-managers"
    
    log_info "Finding Resident Key Manager..."
    local response
    response=$(curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" "${km_api}?limit=100" 2>&1)
    
    # Extract Resident KM ID using jq
    local resident_km_id
    resident_km_id=$(echo "${response}" | jq -r '.list[] | select(.name == "Resident Key Manager") | .id' 2>/dev/null)
    
    if [ -z "${resident_km_id}" ] || [ "${resident_km_id}" = "null" ]; then
        log_error "Resident Key Manager not found"
        return 1
    fi
    
    log_info "Resident KM ID: ${resident_km_id}"
    
    # Get current configuration
    log_info "Fetching Resident KM configuration..."
    local current_config
    current_config=$(curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        "${km_api}/${resident_km_id}" 2>&1)
    
    if ! echo "${current_config}" | grep -q '"name"'; then
        log_error "Failed to fetch Resident KM configuration"
        return 1
    fi
    
    # Modify enabled to false
    log_info "Disabling Resident Key Manager..."
    local updated_config
    updated_config=$(echo "${current_config}" | jq '.enabled = false')
    
    # PUT the updated configuration
    response=$(curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d "${updated_config}" \
        -X PUT "${km_api}/${resident_km_id}" 2>&1)
    
    if echo "${response}" | grep -q '"enabled":false'; then
        log_success "Resident Key Manager disabled successfully!"
        echo ""
        log_warn "⚠️  Ensure WSO2IS Key Manager is enabled and working"
        log_info "Verify with: ./scripts/wso2-toolkit.sh list-km"
        return 0
    else
        log_error "Failed to disable Resident Key Manager"
        echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: list-roles - List all roles in WSO2 IS
################################################################################
cmd_list_roles() {
    echo ""
    echo "=========================================="
    echo "  Roles in WSO2 Identity Server"
    echo "=========================================="
    echo ""
    
    log_info "Fetching roles from WSO2 IS..."
    
    # Use external port for host access
    local response
    response=$(curl -k -sS -X GET \
        "https://localhost:${WSO2IS_EXTERNAL_PORT}/scim2/v2/Roles" \
        -H "Authorization: Basic $(printf "%s:%s" "${WSO2IS_ADMIN_USER}" "${WSO2IS_ADMIN_PASS}" | base64)" \
        -H "Accept: application/scim+json" 2>&1)
    
    if echo "$response" | jq -e '.Resources' >/dev/null 2>&1; then
        local total
        total=$(echo "$response" | jq -r '.totalResults')
        
        echo "Total Roles: ${total}"
        echo ""
        
        if [ "$total" -gt 0 ]; then
            echo "$response" | jq -r '.Resources[] | "ID: " + .id + "\nName: " + .displayName + "\nAudience: " + (.audience.type // "N/A") + "\n---"'
        else
            log_warn "No roles found"
        fi
        
        return 0
    else
        log_error "Failed to fetch roles"
        echo "$response" | jq . 2>/dev/null || echo "$response"
        return 1
    fi
}

################################################################################
# COMMAND: list-users - List all users in WSO2 IS
################################################################################
cmd_list_users() {
    echo ""
    echo "=========================================="
    echo "  Users in WSO2 Identity Server"
    echo "=========================================="
    echo ""
    
    log_info "Fetching users from WSO2 IS..."
    
    # Use external port for host access
    local response
    response=$(curl -k -sS -X GET \
        "https://localhost:${WSO2IS_EXTERNAL_PORT}/scim2/Users" \
        -H "Authorization: Basic $(printf "%s:%s" "${WSO2IS_ADMIN_USER}" "${WSO2IS_ADMIN_PASS}" | base64)" \
        -H "Accept: application/scim+json" 2>&1)
    
    if echo "$response" | jq -e '.Resources' >/dev/null 2>&1; then
        local total
        total=$(echo "$response" | jq -r '.totalResults')
        
        echo "Total Users: ${total}"
        echo ""
        
        if [ "$total" -gt 0 ]; then
            echo "$response" | jq -r '.Resources[] | "ID: " + .id + "\nUsername: " + .userName + "\nName: " + (.name.givenName // "N/A") + " " + (.name.familyName // "N/A") + "\nEmail: " + ((.emails // [])[0] // "N/A") + "\nActive: " + (.active | tostring) + "\n---"'
        else
            log_warn "No users found"
        fi
        
        return 0
    else
        log_error "Failed to fetch users"
        echo "$response" | jq . 2>/dev/null || echo "$response"
        return 1
    fi
}

################################################################################
# HELPER: create_role - Create a single role in WSO2 IS
################################################################################
create_role() {
    local role_name="$1"
    local audience_type="${2:-organization}"
    local audience_value="${3:-}"
    
    validate_role_name "${role_name}" || return 1
    
    local payload
    if [ -n "$audience_value" ] && [ "$audience_type" = "organization" ]; then
        # Organization-scoped role with ID
        payload=$(jq -n --arg name "$role_name" --arg aud_type "$audience_type" --arg aud_val "$audience_value" '
        {
          "schemas": ["urn:ietf:params:scim:schemas:core:2.0:Role"],
          "displayName": $name,
          "audience": {
            "type": $aud_type,
            "value": $aud_val
          }
        }')
    else
        # Simple role (may fail without proper audience value)
        payload=$(jq -n --arg name "$role_name" --arg aud_type "$audience_type" '
        {
          "schemas": ["urn:ietf:params:scim:schemas:core:2.0:Role"],
          "displayName": $name,
          "audience": {
            "type": $aud_type
          }
        }')
    fi
    
    # Use external port for host access
    local resp
    resp=$(curl -k -sS -X POST \
        "https://localhost:${WSO2IS_EXTERNAL_PORT}/scim2/v2/Roles" \
        -H "Authorization: Basic $(printf "%s:%s" "${WSO2IS_ADMIN_USER}" "${WSO2IS_ADMIN_PASS}" | base64)" \
        -H "Content-Type: application/scim+json" \
        -d "$payload" 2>&1)
    
    if echo "$resp" | jq -e '.id' >/dev/null 2>&1; then
        local id
        id=$(echo "$resp" | jq -r '.id')
        echo "Role '${role_name}' created (id=${id})"
        return 0
    elif echo "$resp" | grep -qi "409\|already exists"; then
        echo "Role '${role_name}' already exists"
        return 2  # Special return code for "already exists"
    else
        echo "Failed to create role '${role_name}'"
        echo "$resp" | jq . 2>/dev/null || echo "$resp"
        return 1
    fi
}

################################################################################
# COMMAND: create-roles - Create multiple roles at once
################################################################################
cmd_create_roles() {
    echo ""
    echo "=========================================="
    echo "  Create Multiple Roles in WSO2 IS"
    echo "=========================================="
    echo ""
    
    # Default roles for a typical money transfer application
    local roles=(
        "ops_users"
        "finance"
        "auditor"
        "user"
        "app_admin"
    )
    
    # Fetch existing roles and get organization ID
    log_info "Checking existing roles and fetching organization ID..."
    local existing_roles_response
    existing_roles_response=$(curl -k -sS -X GET \
        "https://localhost:${WSO2IS_EXTERNAL_PORT}/scim2/v2/Roles" \
        -H "Authorization: Basic $(printf "%s:%s" "${WSO2IS_ADMIN_USER}" "${WSO2IS_ADMIN_PASS}" | base64)" \
        -H "Accept: application/scim+json" 2>&1)
    
    local existing_role_names=""
    local org_id=""
    if echo "$existing_roles_response" | jq -e '.Resources' >/dev/null 2>&1; then
        existing_role_names="|$(echo "$existing_roles_response" | jq -r '.Resources[].displayName' | tr '\n' '|')"
        # Get organization ID from any existing organization-scoped role
        org_id=$(echo "$existing_roles_response" | jq -r '.Resources[] | select(.audience.type == "organization") | .audience.value' | head -1)
    fi
    
    if [ -z "$org_id" ] || [ "$org_id" = "null" ]; then
        log_error "Could not determine organization ID from existing roles"
        return 1
    fi
    
    log_info "Organization ID: ${org_id}"
    
    log_info "Creating ${#roles[@]} roles in WSO2 Identity Server..."
    echo ""
    
    local created=0
    local skipped=0
    local failed=0
    
    for role in "${roles[@]}"; do
        echo "→ Processing: ${role}"
        
        # Check if role already exists
        if echo "${existing_role_names}" | grep -qF "|${role}|"; then
            log_warn "Role '${role}' already exists - skipped"
            skipped=$((skipped + 1))
            continue
        fi
        
        local result
        result=$(create_role "${role}" "organization" "${org_id}" 2>&1)
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            log_success "${result}"
            created=$((created + 1))
        elif [ $exit_code -eq 2 ]; then
            log_warn "${result}"
            skipped=$((skipped + 1))
        else
            log_error "${result}"
            failed=$((failed + 1))
        fi
    done
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                 Roles Creation Summary                   ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "Created:  ${created}"
    echo "Skipped:  ${skipped}"
    echo "Failed:   ${failed}"
    echo ""
    
    if [ ${failed} -eq 0 ]; then
        log_success "All roles configured successfully!"
        echo ""
        echo "Next steps:"
        echo "  1. Register users via SCIM2 API or Profile Service"
        echo "  2. Assign roles to users"
        echo "  3. Use roles in API authorization policies"
        echo ""
        echo "Access WSO2 IS Console: https://localhost:${WSO2IS_EXTERNAL_PORT}/console"
        echo ""
        return 0
    else
        log_error "${failed} role(s) failed to create"
        return 1
    fi
}

################################################################################
# MAIN DISPATCHER
################################################################################

show_help() {
    cat <<'HELP'

╔══════════════════════════════════════════════════════════════╗
║           WSO2 Toolkit - Key Manager Setup                  ║
╚══════════════════════════════════════════════════════════════╝

Usage: ./wso2-toolkit.sh <command>

COMMANDS:

  Infrastructure & Health:
  ========================
  health              Check health of all services

  Key Manager Setup:
  ==================
  km-manual-guide     Print manual Admin Portal configuration steps
  setup-km            Setup WSO2 IS as Key Manager (automated API call)
  update-km           Update existing Key Manager (fix display endpoints)
  delete-km           Delete a Key Manager by name
  list-km             List all configured Key Managers
  disable-resident-km Disable Resident Key Manager

  Role Management:
  ================
  create-roles        Create default application roles in WSO2 IS
  list-roles          List all roles in WSO2 IS
  list-users          List all users in WSO2 IS

EXAMPLES:

  # Check infrastructure health
  ./wso2-toolkit.sh health

  # View manual setup instructions for Admin Portal
  ./wso2-toolkit.sh km-manual-guide

  # Automated Key Manager setup via REST API
  ./wso2-toolkit.sh setup-km

  # Update existing Key Manager (fix UI errors)
  ./wso2-toolkit.sh update-km WSO2IS

  # Delete a Key Manager
  ./wso2-toolkit.sh delete-km WSO2IS

  # List all Key Managers
  ./wso2-toolkit.sh list-km

  # Disable Resident Key Manager (after adding WSO2 IS)
  ./wso2-toolkit.sh disable-resident-km

  # Create default application roles
  ./wso2-toolkit.sh create-roles

  # List all roles
  ./wso2-toolkit.sh list-roles

  # List all users
  ./wso2-toolkit.sh list-users

NOTES:
  • Ensure containers are running: docker compose up -d
  • Exchange certificates first: ./scripts/truststorekey.sh trust
  • Role creation enabled in deployment.toml: [role_mgt] allow_system_prefix_for_role = true

HELP
}

COMMAND=${1:-help}

# Check dependencies before running commands
if [ "${COMMAND}" != "help" ] && [ "${COMMAND}" != "--help" ] && [ "${COMMAND}" != "-h" ] && [ "${COMMAND}" != "km-manual-guide" ]; then
    check_dependencies || exit 1
fi

case "${COMMAND}" in
    health)
        cmd_health
        ;;
    km-manual-guide)
        cmd_km_manual_guide
        ;;
    setup-km)
        cmd_setup_km
        ;;
    update-km)
        shift
        cmd_update_km "$@"
        ;;
    delete-km)
        shift
        cmd_delete_km "$@"
        ;;
    list-km)
        cmd_list_km
        ;;
    disable-resident-km)
        cmd_disable_resident_km
        ;;
    create-roles)
        cmd_create_roles
        ;;
    list-roles)
        cmd_list_roles
        ;;
    list-users)
        cmd_list_users
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "Unknown command: ${COMMAND}"
        show_help
        exit 1
        ;;
esac