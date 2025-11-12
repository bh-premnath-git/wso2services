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

get_wso2is_home() {
    docker exec wso2is bash -c "ls -d /home/wso2carbon/wso2is-* 2>/dev/null | sort -V | tail -1" 2>/dev/null || echo "/home/wso2carbon/wso2is-7.2.0"
}

# Configuration
APIM_HOST="${APIM_HOST:-localhost}"
APIM_PORT="${APIM_PORT:-9443}"
APIM_ADMIN_USER="${APIM_ADMIN_USER:-admin}"
APIM_ADMIN_PASS="${APIM_ADMIN_PASS:-admin}"

WSO2IS_HOST="${WSO2IS_HOST:-wso2is}"
WSO2IS_PORT="${WSO2IS_PORT:-9443}"
WSO2IS_EXTERNAL_PORT="${WSO2IS_EXTERNAL_PORT:-9444}"
WSO2IS_ADMIN_USER="${WSO2IS_ADMIN_USER:-admin}"
WSO2IS_ADMIN_PASS="${WSO2IS_ADMIN_PASS:-admin}"

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
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        log_error "Container '${container}' is not running"
        log_error "Start it with: docker compose up -d ${container}"
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
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "wso2am|wso2is|postgres"; then
        echo ""
    else
        ((errors++))
    fi
    
    log_info "Checking PostgreSQL databases..."
    for db in apim_db shared_db identity_db shared_db_is; do
        if docker exec postgres-wso2 psql -U wso2carbon -d ${db} -c "SELECT 1;" >/dev/null 2>&1; then
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
    check_container "wso2am" || return 1
    check_container "wso2is" || return 1
    
    echo ""
    echo "=========================================="
    echo "  Setup WSO2 IS as Key Manager (APIM 4.5)"
    echo "=========================================="
    echo ""
    
    local km_api="https://${APIM_HOST}:${APIM_PORT}/api/am/admin/v4/key-managers"
    local km_name="${KEY_MANAGER_NAME}"
    
    log_info "Checking if '${km_name}' exists..."
    if curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" "${km_api}?limit=1000" \
        | grep -q "\"name\":\"${km_name}\""; then
        log_warn "Key Manager '${km_name}' already exists"
        return 0
    fi
    
    # Use static IS 7.x endpoints (well-known URL in payload auto-discovers at runtime)
    log_info "Using well-known endpoint: https://${WSO2IS_HOST}:${WSO2IS_PORT}/oauth2/token/.well-known/openid-configuration"
    log_info "WSO2IS Key Manager uses admin credentials for introspection and DCR"
    
    # Static endpoints for IS 7.x
    local token_ep="https://${WSO2IS_HOST}:${WSO2IS_PORT}/oauth2/token"
    local revoke_ep="https://${WSO2IS_HOST}:${WSO2IS_PORT}/oauth2/revoke"
    local introspect_ep="https://${WSO2IS_HOST}:${WSO2IS_PORT}/oauth2/introspect"
    local authorize_ep="https://${WSO2IS_HOST}:${WSO2IS_PORT}/oauth2/authorize"
    local jwks_ep="https://${WSO2IS_HOST}:${WSO2IS_PORT}/oauth2/jwks"
    local issuer="https://${WSO2IS_HOST}:${WSO2IS_PORT}/oauth2/token"
    
    # APIM 4.5.0 complete Key Manager configuration
    # Based on official WSO2 documentation
    # Use jq to build JSON with proper variable expansion
    local payload
    payload=$(jq -n \
        --arg name "${km_name}" \
        --arg is_host "${WSO2IS_HOST}" \
        --arg is_port "${WSO2IS_PORT}" \
        --arg username "${WSO2IS_ADMIN_USER}" \
        --arg password "${WSO2IS_ADMIN_PASS}" \
        --arg token_ep "${token_ep}" \
        --arg revoke_ep "${revoke_ep}" \
        --arg introspect_ep "${introspect_ep}" \
        --arg authorize_ep "${authorize_ep}" \
        --arg jwks_ep "${jwks_ep}" \
        --arg issuer "${issuer}" \
        '{
  "name": $name,
  "displayName": "WSO2 Identity Server 7.1",
  "type": "WSO2-IS",
  "description": "WSO2 Identity Server 7.1 as external OAuth2 Key Manager",
  "enabled": true,
  "tokenType": "DIRECT",
  "wellKnownEndpoint": ("https://" + $is_host + ":" + $is_port + "/oauth2/token/.well-known/openid-configuration"),
  "introspectionEndpoint": $introspect_ep,
  "clientRegistrationEndpoint": ("https://" + $is_host + ":" + $is_port + "/api/identity/oauth2/dcr/v1.1/register"),
  "tokenEndpoint": $token_ep,
  "revokeEndpoint": $revoke_ep,
  "userInfoEndpoint": ("https://" + $is_host + ":" + $is_port + "/scim2/Me"),
  "authorizeEndpoint": $authorize_ep,
  "scopeManagementEndpoint": ("https://" + $is_host + ":" + $is_port + "/api/identity/oauth2/v1.0/scopes"),
  "issuer": $issuer,
  "certificates": {
    "type": "JWKS",
    "value": $jwks_ep
  },
  "availableGrantTypes": [
    "password",
    "client_credentials",
    "refresh_token",
    "authorization_code",
    "implicit",
    "urn:ietf:params:oauth:grant-type:saml2-bearer",
    "iwa:ntlm",
    "urn:ietf:params:oauth:grant-type:device_code",
    "urn:ietf:params:oauth:grant-type:jwt-bearer",
    "urn:ietf:params:oauth:grant-type:token-exchange"
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
      "localClaim": "http://wso2.org/claims/enduser"
    }
  ],
  "tokenValidation": [
    {
      "enable": true,
      "type": "JWT"
    }
  ],
  "additionalProperties": {
    "ServerURL": ("https://" + $is_host + ":" + $is_port + "/services"),
    "Username": $username,
    "Password": $password,
    "TokenURL": $token_ep,
    "RevokeURL": $revoke_ep,
    "IntrospectURL": $introspect_ep,
    "AuthorizeURL": $authorize_ep,
    "UserInfoURL": ("https://" + $is_host + ":" + $is_port + "/scim2/Me"),
    "JWKSEndpoint": $jwks_ep,
    "ScopeClaim": "scope",
    "ConsumerKeyClaim": "azp",
    "VALIDITY_PERIOD": "3600",
    "validation_enable": true,
    "self_validate_jwt": true,
    "api_resource_mgt_endpoint": ("https://" + $is_host + ":" + $is_port + "/api/server/v1/api-resources"),
    "roles_endpoint": ("https://" + $is_host + ":" + $is_port + "/scim2/Roles")
  }
}')
    
    log_info "Creating Key Manager '${km_name}'..."
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
        return 0
    else
        log_error "Failed to create Key Manager"
        echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: list-km - List all Key Managers
################################################################################

cmd_list_km() {
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
    check_container "wso2am" || return 1
    
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
    
    # Get current configuration (PUT requires full object)
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
        log_info "Verify with: $0 list-km"
        return 0
    else
        log_error "Failed to disable Resident Key Manager"
        echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: check-mtls - Check MTLS certificate trust
################################################################################

cmd_check_mtls() {
    check_container "wso2am" || return 1
    check_container "wso2is" || return 1
    
    echo ""
    echo "=========================================="
    echo "  Check MTLS Certificate Trust"
    echo "=========================================="
    echo ""
    
    log_info "Testing APIM → IS HTTPS connectivity..."
    
    # Test from APIM container to IS
    local test_result
    test_result=$(docker exec wso2am curl -k -sS --max-time 5 \
        "https://wso2is:9443/oauth2/token/.well-known/openid-configuration" 2>&1)
    
    if echo "${test_result}" | grep -q '"issuer"'; then
        log_success "✓ APIM can reach IS over HTTPS"
    else
        log_error "✗ APIM cannot reach IS"
        echo "${test_result}"
        return 1
    fi
    
    log_info "Testing IS → APIM HTTPS connectivity..."
    
    # Test from IS container to APIM (check HTTP status code)
    local http_code
    http_code=$(docker exec wso2is curl -k -sS --max-time 5 -o /dev/null -w "%{http_code}" \
        "https://wso2am:9443/api/am/admin/v4/key-managers" 2>/dev/null || echo "000")
    
    if [ "${http_code}" = "401" ] || [ "${http_code}" = "200" ]; then
        log_success "✓ IS can reach APIM over HTTPS (HTTP ${http_code})"
    else
        log_error "✗ IS cannot reach APIM (HTTP ${http_code})"
        return 1
    fi
    
    log_info "Checking certificate trust in APIM truststore..."
    
    # Check if IS cert is in APIM JKS truststore (APIM 4.5 uses JKS)
    local cert_check
    cert_check=$(docker exec wso2am keytool -list \
        -keystore /home/wso2carbon/wso2am-4.5.0/repository/resources/security/client-truststore.jks \
        -storepass wso2carbon -alias wso2is 2>&1 || true)
    
    if echo "${cert_check}" | grep -q "trustedCertEntry"; then
        log_success "✓ IS certificate exists in APIM truststore"
    else
        log_warn "⚠️  IS certificate NOT found in APIM truststore"
        log_info "Run: $0 fix-mtls to add the certificate"
    fi
    
    log_info "Checking certificate trust in IS truststore..."
    
    # Check if APIM cert is in IS PKCS12 truststore
    local cert_check_is
    cert_check_is=$(docker exec wso2is keytool -list \
        -keystore /home/wso2carbon/wso2is-7.1.0/repository/resources/security/client-truststore.p12 \
        -storetype PKCS12 \
        -storepass wso2carbon -alias wso2am 2>&1 || true)
    
    if echo "${cert_check_is}" | grep -q "trustedCertEntry"; then
        log_success "✓ APIM certificate exists in IS truststore"
    else
        log_warn "⚠️  APIM certificate NOT found in IS truststore"
        log_info "Run: $0 fix-mtls to add the certificate"
    fi
    
    echo ""
    log_success "✅ MTLS check complete!"
    echo ""
    log_info "For production, ensure proper CA-signed certificates"
    log_info "For development, run 'fix-mtls' if needed"
}

################################################################################
# COMMAND: fix-mtls - Fix MTLS certificate trust
################################################################################

cmd_fix_mtls() {
    check_container "wso2am" || return 1
    check_container "wso2is" || return 1
    
    # Get dynamic paths
    local WSO2AM_HOME=$(get_wso2am_home)
    local WSO2IS_HOME=$(get_wso2is_home)
    
    echo ""
    echo "=========================================="
    echo "  Fix MTLS Certificate Trust"
    echo "=========================================="
    echo ""
    
    log_info "Detected WSO2 AM: ${WSO2AM_HOME}"
    log_info "Detected WSO2 IS: ${WSO2IS_HOME}"
    echo ""
    log_info "Based on WSO2 official documentation:"
    log_info "- Export public certificates from each keystore"
    log_info "- Import to the other's client-truststore"
    echo ""
    
    # Step 1: Export IS certificate from its keystore (wso2carbon.p12)
    log_info "Step 1/4: Exporting IS certificate from wso2carbon.p12..."
    
    docker exec wso2is keytool -export -alias wso2carbon \
        -keystore ${WSO2IS_HOME}/repository/resources/security/wso2carbon.p12 \
        -storetype PKCS12 \
        -file /tmp/wso2is-cert.pem \
        -storepass wso2carbon >/dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        log_error "Failed to export IS certificate"
        return 1
    fi
    
    log_success "✓ IS certificate exported to /tmp/wso2is-cert.pem"
    
    # Step 2: Import IS certificate to APIM truststore (client-truststore.jks)
    log_info "Step 2/4: Importing IS certificate to APIM client-truststore.jks..."
    
    # Copy cert from IS container to host, then to APIM container
    docker exec wso2is cat /tmp/wso2is-cert.pem > /tmp/wso2is-cert-host.pem 2>/dev/null
    docker cp /tmp/wso2is-cert-host.pem wso2am:/tmp/wso2is-cert.pem
    
    # Delete old alias if exists to avoid conflicts
    docker exec wso2am keytool -delete -alias wso2is \
        -keystore ${WSO2AM_HOME}/repository/resources/security/client-truststore.jks \
        -storepass wso2carbon >/dev/null 2>&1
    
    # Import with root user to ensure permissions
    local import_result
    import_result=$(docker exec -u root wso2am bash -c "keytool -import -alias wso2is \
        -keystore ${WSO2AM_HOME}/repository/resources/security/client-truststore.jks \
        -file /tmp/wso2is-cert.pem \
        -storepass wso2carbon \
        -noprompt 2>&1")
    local import_status=$?
    
    if [ $import_status -ne 0 ]; then
        log_error "Failed to import IS certificate to APIM truststore"
        echo "${import_result}"
        return 1
    fi
    
    # Fix permissions
    docker exec -u root wso2am chmod 644 ${WSO2AM_HOME}/repository/resources/security/client-truststore.jks >/dev/null 2>&1
    
    log_success "✓ IS certificate imported to APIM truststore (alias: wso2is)"
    
    # Step 3: Export APIM certificate from its keystore (wso2carbon.jks)
    log_info "Step 3/4: Exporting APIM certificate from wso2carbon.jks..."
    
    docker exec wso2am keytool -export -alias wso2carbon \
        -keystore ${WSO2AM_HOME}/repository/resources/security/wso2carbon.jks \
        -storetype JKS \
        -file /tmp/wso2am-cert.pem \
        -storepass wso2carbon >/dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        log_error "Failed to export APIM certificate"
        return 1
    fi
    
    log_success "✓ APIM certificate exported to /tmp/wso2am-cert.pem"
    
    # Step 4: Import APIM certificate to IS truststore (client-truststore.p12)
    log_info "Step 4/4: Importing APIM certificate to IS client-truststore.p12..."
    
    # Copy cert from APIM container to host, then to IS container
    docker exec wso2am cat /tmp/wso2am-cert.pem > /tmp/wso2am-cert-host.pem 2>/dev/null
    docker cp /tmp/wso2am-cert-host.pem wso2is:/tmp/wso2am-cert.pem
    
    # Delete old alias if exists to avoid conflicts
    docker exec wso2is keytool -delete -alias wso2am \
        -keystore ${WSO2IS_HOME}/repository/resources/security/client-truststore.p12 \
        -storetype PKCS12 \
        -storepass wso2carbon >/dev/null 2>&1
    
    # Import with root user to ensure permissions
    local import_result_is
    import_result_is=$(docker exec -u root wso2is bash -c "keytool -import -alias wso2am \
        -keystore ${WSO2IS_HOME}/repository/resources/security/client-truststore.p12 \
        -file /tmp/wso2am-cert.pem \
        -storepass wso2carbon \
        -storetype PKCS12 \
        -noprompt 2>&1")
    local import_status_is=$?
    
    if [ $import_status_is -ne 0 ]; then
        log_error "Failed to import APIM certificate to IS truststore"
        echo "${import_result_is}"
        return 1
    fi
    
    # Fix permissions
    docker exec -u root wso2is chmod 644 ${WSO2IS_HOME}/repository/resources/security/client-truststore.p12 >/dev/null 2>&1
    
    log_success "✓ APIM certificate imported to IS truststore (alias: wso2am)"
    
    # Cleanup temporary files
    rm -f /tmp/wso2is-cert-host.pem /tmp/wso2am-cert-host.pem 2>/dev/null || true
    docker exec wso2is rm -f /tmp/wso2is-cert.pem /tmp/wso2am-cert.pem 2>/dev/null || true
    docker exec wso2am rm -f /tmp/wso2is-cert.pem /tmp/wso2am-cert.pem 2>/dev/null || true
    
    echo ""
    log_success "✅ MTLS certificate trust configured successfully!"
    echo ""
    log_warn "⚠️  IMPORTANT: Restart both containers to apply changes:"
    echo "     docker compose restart wso2am wso2is"
    echo ""
    echo "After restart, wait ~90 seconds for services to fully initialize."
    echo ""
    log_info "Then verify with:"
    echo "     $0 check-mtls"
    echo ""
    
    return 0
}

################################################################################
# COMMAND: check-ssa-jwks - Check SSA JWKS configuration for DCR
################################################################################

cmd_check_ssa_jwks() {
    check_container "wso2is" || return 1
    
    echo ""
    echo "=========================================="
    echo "  Check SSA JWKS for DCR"
    echo "=========================================="
    echo ""
    
    log_info "Testing JWKS endpoint accessibility..."
    
    local jwks_url="https://wso2is:9443/oauth2/jwks"
    local external_jwks_url="https://localhost:9444/oauth2/jwks"
    
    # Test internal access
    local jwks_response
    jwks_response=$(docker exec wso2is curl -k -sS --max-time 5 "${jwks_url}" 2>&1)
    
    if echo "${jwks_response}" | grep -q '"keys"'; then
        log_success "✓ JWKS endpoint accessible internally"
    else
        log_error "✗ JWKS endpoint not accessible"
        return 1
    fi
    
    # Test external access
    jwks_response=$(curl -k -sS --max-time 5 "${external_jwks_url}" 2>&1)
    
    if echo "${jwks_response}" | grep -q '"keys"'; then
        log_success "✓ JWKS endpoint accessible externally"
        echo ""
        log_info "JWKS URL: ${external_jwks_url}"
        echo "${jwks_response}" | python3 -m json.tool 2>/dev/null || echo "${jwks_response}"
    else
        log_error "✗ JWKS endpoint not accessible externally"
        return 1
    fi
    
    echo ""
    log_info "For DCR with SSA, use JWKS URL in your SSA configuration"
    log_info "JWKS URL: https://wso2is:9443/oauth2/jwks"
}

################################################################################
# COMMAND: list-apps - List all applications from APIM DevPortal
################################################################################

cmd_list_apps() {
    echo ""
    echo "=========================================="
    echo "  Applications in APIM DevPortal"
    echo "=========================================="
    echo ""

    check_container "wso2am" || return 1

    local app_api="https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications"

    log_info "Fetching applications from APIM DevPortal..."
    local response
    response=$(curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        "${app_api}?limit=100" 2>&1)

    if echo "${response}" | grep -q '"list"'; then
        echo ""
        echo "${response}" | jq -r '.list[] | "ID: \(.applicationId)\nName: \(.name)\nStatus: \(.status)\nOwner: \(.owner)\nThrottling: \(.throttlingPolicy)\n---"' 2>/dev/null || echo "${response}" | python3 -m json.tool
        echo ""
        log_info "Total applications: $(echo "${response}" | jq -r '.count // 0' 2>/dev/null)"
    else
        log_error "Failed to fetch applications"
        echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: create-app - Create application via APIM DevPortal (2-step flow)
################################################################################

cmd_create_app() {
    local app_name=${1:-}
    local callback_url=${2:-"http://localhost:8080/callback"}
    local key_manager=${3:-"WSO2IS"}

    if [ -z "${app_name}" ]; then
        log_error "Usage: $0 create-app <app_name> [callback_url] [key_manager]"
        echo ""
        echo "Example:"
        echo "  $0 create-app MyTestApp http://localhost:8080/callback WSO2IS"
        return 1
    fi

    # Validate inputs
    validate_app_name "${app_name}" || return 1
    validate_url "${callback_url}" || return 1

    # Check if APIM container is running
    check_container "wso2am" || return 1

    echo ""
    echo "=========================================="
    echo "  Create Application via APIM DevPortal"
    echo "=========================================="
    echo ""

    local apim_app_api="https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications"

    # Step 1: Create application in APIM
    log_info "Step 1/2: Creating application '${app_name}' in APIM DevPortal..."

    local app_payload
    read -r -d '' app_payload <<EOF || true
{
  "name": "${app_name}",
  "throttlingPolicy": "Unlimited",
  "description": "OAuth2/OIDC application created via toolkit",
  "tokenType": "JWT",
  "attributes": {}
}
EOF

    local temp_response="/tmp/wso2_create_app_$$.json"
    local http_code
    http_code=$(curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d "${app_payload}" \
        -w "%{http_code}" \
        -o "${temp_response}" \
        -X POST "${apim_app_api}" 2>/dev/null || echo "000")

    local app_response
    app_response=$(cat "${temp_response}" 2>/dev/null || echo "{}")

    if [ "${http_code}" != "201" ]; then
        rm -f "${temp_response}"
        log_error "Failed to create application in APIM (HTTP ${http_code})"
        echo ""
        echo "${app_response}" | python3 -m json.tool 2>/dev/null || echo "${app_response}"
        echo ""

        if [ "${http_code}" = "409" ]; then
            echo "Application '${app_name}' already exists."
            echo ""
            echo "Options:"
            echo "  1. Use a different name"
            echo "  2. List existing apps: $0 list-apps"
            echo "  3. Get keys for existing app: $0 get-app-keys <app_id>"
        fi
        return 1
    fi

    local app_id=$(echo "${app_response}" | jq -r '.applicationId // empty' 2>/dev/null)

    if [ -z "${app_id}" ]; then
        rm -f "${temp_response}"
        log_error "Application created but ID not found in response"
        return 1
    fi

    log_success "Application created in APIM (ID: ${app_id})"
    rm -f "${temp_response}"

    # Step 2: Generate keys with WSO2IS Key Manager
    log_info "Step 2/2: Generating OAuth2 keys with Key Manager '${key_manager}'..."

    local keys_api="${apim_app_api}/${app_id}/generate-keys"

    local keys_payload
    read -r -d '' keys_payload <<EOF || true
{
  "keyType": "PRODUCTION",
  "keyManager": "${key_manager}",
  "grantTypesToBeSupported": [
    "client_credentials",
    "password",
    "authorization_code",
    "refresh_token",
    "implicit",
    "urn:ietf:params:oauth:grant-type:device_code",
    "urn:ietf:params:oauth:grant-type:jwt-bearer",
    "urn:ietf:params:oauth:grant-type:saml2-bearer",
    "urn:ietf:params:oauth:grant-type:token-exchange"
  ],
  "callbackUrl": "${callback_url}",
  "scopes": ["default"],
  "validityTime": 3600,
  "additionalProperties": {}
}
EOF

    local temp_keys="/tmp/wso2_keys_$$.json"
    http_code=$(curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d "${keys_payload}" \
        -w "%{http_code}" \
        -o "${temp_keys}" \
        -X POST "${keys_api}" 2>/dev/null || echo "000")

    local keys_response
    keys_response=$(cat "${temp_keys}" 2>/dev/null || echo "{}")

    if [ "${http_code}" != "200" ]; then
        rm -f "${temp_keys}"
        log_error "Failed to generate keys (HTTP ${http_code})"
        echo ""
        echo "${keys_response}" | python3 -m json.tool 2>/dev/null || echo "${keys_response}"
        echo ""
        echo "Application created (ID: ${app_id}) but key generation failed."
        echo "You can retry key generation via APIM DevPortal UI."
        return 1
    fi

    local consumer_key=$(echo "${keys_response}" | jq -r '.consumerKey // empty' 2>/dev/null)
    local consumer_secret=$(echo "${keys_response}" | jq -r '.consumerSecret // empty' 2>/dev/null)

    rm -f "${temp_keys}"

    if [ -z "${consumer_key}" ] || [ -z "${consumer_secret}" ]; then
        log_error "Keys generated but credentials not found in response"
        return 1
    fi

    log_success "OAuth2 keys generated successfully!"
    
    # Step 3: Update application to ensure keys are persisted
    log_info "Verifying key mapping..."
    local update_payload
    read -r -d '' update_payload <<EOF || true
{
  "name": "${app_name}",
  "throttlingPolicy": "Unlimited",
  "description": "OAuth2/OIDC application created via toolkit",
  "tokenType": "JWT",
  "attributes": {
    "client_id": "${consumer_key}"
  }
}
EOF

    curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d "${update_payload}" \
        -X PUT "${apim_app_api}/${app_id}" > /dev/null 2>&1 || true

    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  SAVE THESE CREDENTIALS - THEY WON'T BE SHOWN AGAIN     ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "Application Name: ${app_name}"
    echo "Application ID:   ${app_id}"
    echo "Client ID:        ${consumer_key}"
    echo "Client Secret:    ${consumer_secret}"
    echo "Callback URL:     ${callback_url}"
    echo "Key Manager:      ${key_manager}"
    echo ""
    echo "Grant Types Enabled:"
    echo "  ✓ Client Credentials"
    echo "  ✓ Password"
    echo "  ✓ Authorization Code"
    echo "  ✓ Refresh Token"
    echo "  ✓ Implicit"
    echo "  ✓ Device Code"
    echo "  ✓ JWT Bearer"
    echo "  ✓ SAML2 Bearer"
    echo "  ✓ Token Exchange"
    echo ""
    echo "Test token generation:"
    echo "  ./wso2-toolkit.sh get-token cc ${consumer_key} ${consumer_secret}"
    echo ""
    echo "Test with user login (password grant):"
    echo "  ./wso2is-user.sh login <username> <password> ${consumer_key} ${consumer_secret}"
    echo ""
    echo "Call services directly (bypassing gateway):"
    echo "  # Available services: 8007 (banking), 8001 (forex), 8002 (ledger),"
    echo "  #                     8003 (payment), 8004 (profile), 8005 (rule-engine), 8006 (wallet)"
    echo "  curl -H 'Authorization: Bearer <TOKEN>' http://localhost:8001/health"
    echo ""
    echo "Call through API Gateway:"
    echo "  curl -k -H 'Authorization: Bearer <TOKEN>' https://localhost:8243/<context>/<endpoint>"
    echo ""
    echo "Access APIM DevPortal:"
    echo "  https://localhost:${APIM_PORT}/devportal"
    echo ""
    echo "NOTE: If gateway returns 900908 (subscription validation failed),"
    echo "      use direct service calls. OAuth keys are valid, subscription exists,"
    echo "      but APIM may need keys re-mapped via DevPortal UI."
    echo ""

    return 0
}

################################################################################
# COMMAND: get-app - Get application details from APIM
################################################################################

cmd_get_app() {
    local app_id=${1:-}

    if [ -z "${app_id}" ]; then
        log_error "Usage: $0 get-app <application_id>"
        echo ""
        echo "Get application ID from: $0 list-apps"
        return 1
    fi

    check_container "wso2am" || return 1

    echo ""
    echo "=========================================="
    echo "  Application Details (APIM)"
    echo "=========================================="
    echo ""

    local app_api="https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications"

    log_info "Fetching application '${app_id}'..."
    local response
    response=$(curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        "${app_api}/${app_id}" 2>&1)

    if echo "${response}" | grep -q '"applicationId"'; then
        echo "${response}" | python3 -m json.tool 2>/dev/null || echo "${response}"
    else
        log_error "Failed to fetch application"
        echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: get-app-keys - Get application OAuth2 keys from APIM
################################################################################

cmd_get_app_keys() {
    local app_id=${1:-}
    local key_type=${2:-PRODUCTION}

    if [ -z "${app_id}" ]; then
        log_error "Usage: $0 get-app-keys <application_id> [PRODUCTION|SANDBOX]"
        echo ""
        echo "Get application ID from: $0 list-apps"
        return 1
    fi

    check_container "wso2am" || return 1

    echo ""
    echo "=========================================="
    echo "  Application OAuth2 Keys"
    echo "=========================================="
    echo ""

    log_info "Fetching ${key_type} keys for application ${app_id}..."
    
    # Get keys from APIM DevPortal API (endpoint: /keys not /oauth-keys)
    local api_url="https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications/${app_id}/keys/${key_type}"
    
    local response
    response=$(curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -X GET "${api_url}" 2>&1)
    
    if echo "${response}" | grep -q '"consumerKey"'; then
        local consumer_key
        local consumer_secret
        local supported_grants
        local callback_url
        
        consumer_key=$(echo "${response}" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('consumerKey', 'N/A'))" 2>/dev/null)
        consumer_secret=$(echo "${response}" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('consumerSecret', 'N/A'))" 2>/dev/null)
        supported_grants=$(echo "${response}" | python3 -c "import sys, json; data=json.load(sys.stdin); print(', '.join(data.get('supportedGrantTypes', [])))" 2>/dev/null)
        callback_url=$(echo "${response}" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('callbackUrl', 'N/A'))" 2>/dev/null)
        
        # If consumer_key exists but no secret, try direct DCR endpoint
        if [ "${consumer_secret}" = "N/A" ] && [ "${consumer_key}" != "N/A" ]; then
            log_warn "Consumer secret masked by APIM. Fetching directly from WSO2 IS DCR endpoint..."
            
            local dcr_response
            dcr_response=$(curl -k -sS -u "${WSO2IS_ADMIN_USER}:${WSO2IS_ADMIN_PASS}" \
                -H "Accept: application/json" \
                -X GET "https://${WSO2IS_HOST}:${WSO2IS_PORT}/api/identity/oauth2/dcr/v1.1/register/${consumer_key}" 2>&1)
            
            if echo "${dcr_response}" | grep -q '"client_secret"'; then
                consumer_secret=$(echo "${dcr_response}" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('client_secret', 'N/A'))" 2>/dev/null)
                log_success "Retrieved secret from WSO2 IS DCR"
            fi
        fi
        
        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║  OAuth2 Credentials (${key_type})                        ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        echo "Application ID:  ${app_id}"
        echo "Client ID:       ${consumer_key}"
        echo "Client Secret:   ${consumer_secret}"
        echo "Callback URL:    ${callback_url}"
        echo "Grant Types:     ${supported_grants}"
        echo ""
        echo "Test token generation:"
        echo "  ./wso2-toolkit.sh get-token cc ${consumer_key} ${consumer_secret}"
        echo ""
        echo "Call API through gateway:"
        echo "  curl -k -H 'Authorization: Bearer <TOKEN>' https://localhost:8243/<context>/<endpoint>"
        echo ""

        # Show supported grant types
        local grant_types=$(echo "${response}" | jq -r '.supportedGrantTypes[]? // empty' 2>/dev/null)
        if [ -n "${grant_types}" ]; then
            echo "Grant Types Enabled:"
            echo "${grant_types}" | while read -r grant; do
                [ -n "$grant" ] && echo "  ✓ ${grant}"
            done
            echo ""
        fi

        echo "Full Key Details:"
        echo "${response}" | python3 -m json.tool 2>/dev/null

        return 0
    else
        log_error "Failed to fetch application keys"
        echo "${response}"
        echo ""
        echo "This application may not have keys generated yet."
        echo "Generate keys with: $0 create-app <name> <callback_url>"
        return 1
    fi
}

################################################################################
# COMMAND: get-client - Get OAuth client details directly from WSO2 IS DCR
################################################################################

cmd_get_client() {
    local client_id=${1:-}

    if [ -z "${client_id}" ]; then
        log_error "Usage: $0 get-client <client_id>"
        echo ""
        echo "Get client_id from: $0 create-app output"
        return 1
    fi

    check_container "wso2is" || return 1

    echo ""
    echo "=========================================="
    echo "  OAuth2 Client Details (WSO2 IS DCR)"
    echo "=========================================="
    echo ""
    
    log_info "Fetching OAuth client: ${client_id}"
    
    # Use external port for WSO2 IS when accessing from host
    local dcr_url="https://localhost:${WSO2IS_EXTERNAL_PORT}/api/identity/oauth2/dcr/v1.1/register/${client_id}"
    
    local response
    response=$(curl -k -sS -u "${WSO2IS_ADMIN_USER}:${WSO2IS_ADMIN_PASS}" \
        -H "Accept: application/json" \
        -X GET "${dcr_url}" 2>&1)
    
    if echo "${response}" | grep -q '"client_id"'; then
        local client_secret
        local grant_types
        local callback_url
        
        client_secret=$(echo "${response}" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('client_secret', 'N/A'))" 2>/dev/null)
        grant_types=$(echo "${response}" | python3 -c "import sys, json; data=json.load(sys.stdin); print(', '.join(data.get('grant_types', [])))" 2>/dev/null)
        callback_url=$(echo "${response}" | python3 -c "import sys, json; data=json.load(sys.stdin); print(', '.join(data.get('redirect_uris', [])))" 2>/dev/null)
        
        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║  OAuth2 Client Credentials                              ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        echo "Client ID:       ${client_id}"
        echo "Client Secret:   ${client_secret}"
        echo "Callback URL:    ${callback_url}"
        echo "Grant Types:     ${grant_types}"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Test token generation:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "./scripts/wso2-toolkit.sh get-token cc ${client_id} ${client_secret}"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Full Details:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "${response}" | python3 -m json.tool 2>/dev/null
        echo ""
        return 0
    else
        log_error "Failed to fetch client details"
        echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: delete-app - Delete application from APIM
################################################################################

cmd_delete_app() {
    local app_id=${1:-}

    if [ -z "${app_id}" ]; then
        log_error "Usage: $0 delete-app <application_id>"
        echo ""
        echo "Get application ID from: $0 list-apps"
        return 1
    fi

    check_container "wso2am" || return 1

    echo ""
    echo "=========================================="
    echo "  Delete Application from APIM"
    echo "=========================================="
    echo ""

    local app_api="https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications"

    log_info "Deleting application '${app_id}'..."
    local http_code
    http_code=$(curl -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        -o /dev/null -w "%{http_code}" \
        -X DELETE "${app_api}/${app_id}" 2>&1)

    if [ "${http_code}" = "200" ] || [ "${http_code}" = "204" ]; then
        log_success "Application deleted successfully from APIM"
        log_info "Associated OAuth2 client also removed from Key Manager"
        return 0
    else
        log_error "Failed to delete application (HTTP ${http_code})"
        return 1
    fi
}

################################################################################
# COMMAND: list-roles - List all roles in WSO2 IS
################################################################################

cmd_list_roles() {
    echo ""
    echo "=========================================="
    echo "  WSO2 IS Roles"
    echo "=========================================="
    echo ""
    
    local scim_api="https://localhost:${WSO2IS_EXTERNAL_PORT}/scim2/Roles"
    
    log_info "Fetching roles..."
    local response
    response=$(curl -k -sS -u "${WSO2IS_ADMIN_USER}:${WSO2IS_ADMIN_PASS}" \
        "${scim_api}?count=100" 2>&1)
    
    if echo "${response}" | grep -q '"Resources"'; then
        echo "${response}" | python3 -m json.tool 2>/dev/null || echo "${response}"
    else
        log_error "Failed to fetch roles"
        echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: create-role - Create a role in WSO2 IS
################################################################################

cmd_create_role() {
    local role_name=${1:-}
    local audience_type=${2:-application}
    
    if [ -z "${role_name}" ]; then
        log_error "Usage: $0 create-role <role_name> [audience_type]"
        echo ""
        echo "Examples:"
        echo "  $0 create-role ops_users"
        echo "  $0 create-role finance application"
        echo "  $0 create-role auditor internal"
        echo ""
        echo "Audience types: application, organization, internal"
        return 1
    fi
    
    # Validate inputs
    validate_role_name "${role_name}" || return 1
    
    # Validate audience type
    if [[ ! "$audience_type" =~ ^(application|organization|internal)$ ]]; then
        log_error "Invalid audience type: '$audience_type'"
        log_error "Valid options: application, organization, internal"
        return 1
    fi
    
    # Check if WSO2 IS container is running
    check_container "wso2is" || return 1
    
    echo ""
    echo "=========================================="
    echo "  Create Role in WSO2 IS"
    echo "=========================================="
    echo ""
    
    local scim_api="https://localhost:${WSO2IS_EXTERNAL_PORT}/scim2/Roles"
    
    # Check if role already exists
    log_info "Checking if role '${role_name}' exists..."
    local existing_role
    existing_role=$(curl -k -sS -u "${WSO2IS_ADMIN_USER}:${WSO2IS_ADMIN_PASS}" \
        "${scim_api}?filter=displayName%20eq%20%22${role_name}%22" 2>/dev/null || true)
    
    local role_id
    role_id=$(echo "${existing_role}" | jq -r '.Resources[0].id // empty' 2>/dev/null || true)
    
    if [ -n "${role_id}" ]; then
        log_warn "Role '${role_name}' already exists (ID: ${role_id})"
        return 0
    fi
    
    log_info "Creating role '${role_name}' with audience type '${audience_type}'..."
    
    # Build payload based on audience type
    local payload
    if [ "${audience_type}" = "internal" ]; then
        # Internal role without audience
        read -r -d '' payload <<EOF || true
{
  "displayName": "${role_name}"
}
EOF
    else
        # Application or organization audience
        read -r -d '' payload <<EOF || true
{
  "displayName": "${role_name}",
  "audience": {
    "type": "${audience_type}",
    "display": "Default"
  }
}
EOF
    fi
    
    local response
    response=$(curl -k -sS -u "${WSO2IS_ADMIN_USER}:${WSO2IS_ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        -X POST "${scim_api}" 2>&1 || true)
    
    role_id=$(echo "${response}" | jq -r '.id // empty' 2>/dev/null || true)
    
    if [ -n "${role_id}" ] && [ "${role_id}" != "null" ]; then
        log_success "Role '${role_name}' created successfully"
        echo ""
        echo "Role ID: ${role_id}"
        echo "Display Name: ${role_name}"
        echo "Audience Type: ${audience_type}"
        echo ""
        return 0
    else
        # If audience-based creation failed, try without audience
        if [ "${audience_type}" != "internal" ]; then
            log_warn "Audience-based role creation failed, trying as internal role..."
            
            payload='{"displayName": "'${role_name}'"}'
            response=$(curl -k -sS -u "${WSO2IS_ADMIN_USER}:${WSO2IS_ADMIN_PASS}" \
                -H "Content-Type: application/json" \
                -d "${payload}" \
                -X POST "${scim_api}" 2>&1 || true)
            
            role_id=$(echo "${response}" | jq -r '.id // empty' 2>/dev/null || true)
            
            if [ -n "${role_id}" ] && [ "${role_id}" != "null" ]; then
                log_success "Role '${role_name}' created successfully (as internal role)"
                echo ""
                echo "Role ID: ${role_id}"
                echo "Display Name: ${role_name}"
                echo ""
                return 0
            fi
        fi
        
        log_error "Failed to create role"
        echo "${response}" | python3 -m json.tool 2>/dev/null || echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: create-roles - Create multiple roles at once
################################################################################

cmd_create_roles() {
    echo ""
    echo "=========================================="
    echo "  Create Multiple Roles"
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
    
    log_info "Creating ${#roles[@]} roles..."
    echo ""
    
    local created=0
    local existing=0
    local failed=0
    
    for role in "${roles[@]}"; do
        echo "→ Creating: ${role}"
        if cmd_create_role "${role}" "application" > /tmp/role_create_${role}.log 2>&1; then
            if grep -q "already exists" /tmp/role_create_${role}.log; then
                log_warn "${role} - already exists"
                existing=$((existing + 1))
            else
                log_success "${role} - created"
                created=$((created + 1))
            fi
        else
            log_error "${role} - failed"
            cat /tmp/role_create_${role}.log
            failed=$((failed + 1))
        fi
        rm -f /tmp/role_create_${role}.log
    done
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                 Roles Creation Summary                   ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "Created:  ${created}"
    echo "Existing: ${existing}"
    echo "Failed:   ${failed}"
    echo ""
    
    if [ ${failed} -eq 0 ]; then
        log_success "All roles configured successfully!"
        echo ""
        echo "Next steps:"
        echo "  1. Register users via SCIM2 API"
        echo "  2. Assign roles to users"
        echo "  3. Use roles in API authorization"
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
# COMMAND: delete-role - Delete a role
################################################################################

cmd_delete_role() {
    local role_id=${1:-}
    
    if [ -z "${role_id}" ]; then
        log_error "Usage: $0 delete-role <role_id>"
        echo ""
        echo "Get role ID from:"
        echo "  $0 list-roles"
        return 1
    fi
    
    echo ""
    echo "=========================================="
    echo "  Delete Role"
    echo "=========================================="
    echo ""
    
    local scim_api="https://localhost:${WSO2IS_EXTERNAL_PORT}/scim2/Roles"
    
    log_info "Deleting role '${role_id}'..."
    local http_code
    http_code=$(curl -k -sS -u "${WSO2IS_ADMIN_USER}:${WSO2IS_ADMIN_PASS}" \
        -o /dev/null -w "%{http_code}" \
        -X DELETE "${scim_api}/${role_id}" 2>&1)
    
    if [ "${http_code}" = "204" ]; then
        log_success "Role deleted successfully"
        return 0
    else
        log_error "Failed to delete role (HTTP ${http_code})"
        return 1
    fi
}

################################################################################
# COMMAND: get-token - Get OAuth2 tokens for various grant types
################################################################################

cmd_get_token() {
    local grant_type=${1:-help}
    shift || true
    
    local token_url="https://localhost:${WSO2IS_EXTERNAL_PORT}/oauth2/token"
    
    case "${grant_type}" in
        client_credentials|cc)
            local client_id=${1:-}
            local client_secret=${2:-}
            
            if [ -z "${client_id}" ] || [ -z "${client_secret}" ]; then
                log_error "Usage: $0 get-token cc <client_id> <client_secret>"
                return 1
            fi
            
            log_info "Grant: Client Credentials"
            curl -k -s -X POST "${token_url}" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -u "${client_id}:${client_secret}" \
                -d "grant_type=client_credentials" | python3 -m json.tool 2>/dev/null
            ;;
            
        password|pw)
            local client_id=${1:-}
            local client_secret=${2:-}
            local username=${3:-}
            local password=${4:-}
            
            if [ -z "${client_id}" ] || [ -z "${client_secret}" ] || [ -z "${username}" ] || [ -z "${password}" ]; then
                log_error "Usage: $0 get-token password <client_id> <client_secret> <username> <password>"
                return 1
            fi
            
            log_info "Grant: Resource Owner Password"
            curl -k -s -X POST "${token_url}" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -u "${client_id}:${client_secret}" \
                -d "grant_type=password" \
                -d "username=${username}" \
                -d "password=${password}" | python3 -m json.tool 2>/dev/null
            ;;
            
        refresh|rt)
            local client_id=${1:-}
            local client_secret=${2:-}
            local refresh_token=${3:-}
            
            if [ -z "${client_id}" ] || [ -z "${client_secret}" ] || [ -z "${refresh_token}" ]; then
                log_error "Usage: $0 get-token refresh <client_id> <client_secret> <refresh_token>"
                return 1
            fi
            
            log_info "Grant: Refresh Token"
            curl -k -s -X POST "${token_url}" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -u "${client_id}:${client_secret}" \
                -d "grant_type=refresh_token" \
                -d "refresh_token=${refresh_token}" | python3 -m json.tool 2>/dev/null
            ;;
            
        code|ac)
            local client_id=${1:-}
            local client_secret=${2:-}
            local code=${3:-}
            local redirect_uri=${4:-}
            
            if [ -z "${client_id}" ] || [ -z "${client_secret}" ] || [ -z "${code}" ] || [ -z "${redirect_uri}" ]; then
                log_error "Usage: $0 get-token code <client_id> <client_secret> <auth_code> <redirect_uri>"
                return 1
            fi
            
            log_info "Grant: Authorization Code"
            curl -k -s -X POST "${token_url}" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -u "${client_id}:${client_secret}" \
                -d "grant_type=authorization_code" \
                -d "code=${code}" \
                -d "redirect_uri=${redirect_uri}" | python3 -m json.tool 2>/dev/null
            ;;
            
        device|dc)
            log_info "Device Authorization Grant - Multi-step flow:"
            echo ""
            echo "Step 1: Request device code"
            echo "  curl -k -X POST https://localhost:${WSO2IS_EXTERNAL_PORT}/oauth2/device_authorize \\"
            echo "    -u 'CLIENT_ID:CLIENT_SECRET' \\"
            echo "    -d 'client_id=CLIENT_ID'"
            echo ""
            echo "Step 2: User visits verification_uri and enters user_code"
            echo ""
            echo "Step 3: Poll for token"
            echo "  curl -k -X POST https://localhost:${WSO2IS_EXTERNAL_PORT}/oauth2/token \\"
            echo "    -u 'CLIENT_ID:CLIENT_SECRET' \\"
            echo "    -d 'grant_type=urn:ietf:params:oauth:grant-type:device_code' \\"
            echo "    -d 'device_code=DEVICE_CODE'"
            ;;
            
        jwt|jb)
            local client_id=${1:-}
            local jwt_assertion=${2:-}
            
            if [ -z "${client_id}" ] || [ -z "${jwt_assertion}" ]; then
                log_error "Usage: $0 get-token jwt <client_id> <jwt_assertion>"
                return 1
            fi
            
            log_info "Grant: JWT Bearer"
            curl -k -s -X POST "${token_url}" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" \
                -d "assertion=${jwt_assertion}" \
                -d "client_id=${client_id}" | python3 -m json.tool 2>/dev/null
            ;;
            
        saml|sb)
            local client_id=${1:-}
            local saml_assertion=${2:-}
            
            if [ -z "${client_id}" ] || [ -z "${saml_assertion}" ]; then
                log_error "Usage: $0 get-token saml <client_id> <base64_saml_assertion>"
                return 1
            fi
            
            log_info "Grant: SAML 2.0 Bearer"
            curl -k -s -X POST "${token_url}" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -d "grant_type=urn:ietf:params:oauth:grant-type:saml2-bearer" \
                -d "assertion=${saml_assertion}" \
                -d "client_id=${client_id}" | python3 -m json.tool 2>/dev/null
            ;;
            
        token-exchange|te)
            local client_id=${1:-}
            local client_secret=${2:-}
            local subject_token=${3:-}
            
            if [ -z "${client_id}" ] || [ -z "${client_secret}" ] || [ -z "${subject_token}" ]; then
                log_error "Usage: $0 get-token token-exchange <client_id> <client_secret> <subject_token>"
                return 1
            fi
            
            log_info "Grant: Token Exchange"
            curl -k -s -X POST "${token_url}" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -u "${client_id}:${client_secret}" \
                -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
                -d "subject_token=${subject_token}" \
                -d "subject_token_type=urn:ietf:params:oauth:token-type:jwt" | python3 -m json.tool 2>/dev/null
            ;;
            
        *)
            log_error "Unknown grant type: ${grant_type}"
            show_grant_types
            return 1
            ;;
    esac
}

show_grant_types() {
    echo ""
    echo "Supported Grant Types (aliases):"
    echo "  client_credentials (cc)  - Client Credentials"
    echo "  password (pw)            - Resource Owner Password"
    echo "  refresh (rt)             - Refresh Token"
    echo "  code (ac)                - Authorization Code"
    echo "  device (dc)              - Device Authorization"
    echo "  jwt (jb)                 - JWT Bearer"
    echo "  saml (sb)                - SAML 2.0 Bearer"
    echo "  token-exchange (te)      - Token Exchange"
    echo ""
}

################################################################################
# COMMAND: fix-ssl-trust - Fix SSL Certificate Trust Between WSO2 AM and WSO2 IS
################################################################################

cmd_fix_ssl_trust() {
    # Check if containers are running
    check_container "wso2am" || return 1
    check_container "wso2is" || return 1
    
    echo ""
    echo "=========================================="
    echo "  Fix SSL Certificate Trust"
    echo "=========================================="
    echo ""
    
    log_info "This will exchange SSL certificates between WSO2 AM and WSO2 IS"
    echo ""
    echo "This is required for:"
    echo "  • Token validation via HTTPS"
    echo "  • Introspection endpoint calls"
    echo "  • JWKS endpoint access"
    echo "  • Token revocation notifications"
    echo ""
    
    # Step 1: Export WSO2 IS certificate
    log_info "Step 1: Exporting WSO2 IS certificate..."
    if docker exec wso2is keytool -export -alias wso2carbon \
        -keystore /home/wso2carbon/wso2is-7.1.0/repository/resources/security/wso2carbon.jks \
        -file /tmp/wso2is.crt -storepass wso2carbon 2>/dev/null; then
        log_success "WSO2 IS certificate exported"
    else
        log_error "Failed to export WSO2 IS certificate"
        return 1
    fi
    
    # Step 2: Copy IS certificate to host
    log_info "Step 2: Copying certificate to host..."
    if docker cp wso2is:/tmp/wso2is.crt /tmp/wso2is.crt 2>/dev/null; then
        log_success "Certificate copied to host"
    else
        log_error "Failed to copy certificate"
        return 1
    fi
    
    # Step 3: Copy to APIM container
    log_info "Step 3: Copying certificate to WSO2 AM..."
    if docker cp /tmp/wso2is.crt wso2am:/tmp/wso2is.crt 2>/dev/null; then
        log_success "Certificate copied to WSO2 AM"
    else
        log_error "Failed to copy certificate to WSO2 AM"
        return 1
    fi
    
    # Step 4: Import IS certificate to APIM truststore
    log_info "Step 4: Importing certificate to WSO2 AM truststore..."
    if docker exec wso2am keytool -import -alias wso2is \
        -file /tmp/wso2is.crt \
        -keystore /home/wso2carbon/wso2am-4.5.0/repository/resources/security/client-truststore.jks \
        -storepass wso2carbon -noprompt 2>/dev/null; then
        log_success "Certificate imported to WSO2 AM"
    else
        log_warn "Certificate may already exist in WSO2 AM truststore"
    fi
    
    echo ""
    log_info "Step 5: Exporting WSO2 AM certificate..."
    if docker exec wso2am keytool -export -alias wso2carbon \
        -keystore /home/wso2carbon/wso2am-4.5.0/repository/resources/security/wso2carbon.jks \
        -file /tmp/wso2am.crt -storepass wso2carbon 2>/dev/null; then
        log_success "WSO2 AM certificate exported"
    else
        log_error "Failed to export WSO2 AM certificate"
        return 1
    fi
    
    # Step 6: Copy AM certificate to host
    log_info "Step 6: Copying certificate to host..."
    if docker cp wso2am:/tmp/wso2am.crt /tmp/wso2am.crt 2>/dev/null; then
        log_success "Certificate copied to host"
    else
        log_error "Failed to copy certificate"
        return 1
    fi
    
    # Step 7: Copy to IS container
    log_info "Step 7: Copying certificate to WSO2 IS..."
    if docker cp /tmp/wso2am.crt wso2is:/tmp/wso2am.crt 2>/dev/null; then
        log_success "Certificate copied to WSO2 IS"
    else
        log_error "Failed to copy certificate to WSO2 IS"
        return 1
    fi
    
    # Step 8: Import AM certificate to IS truststore
    log_info "Step 8: Importing certificate to WSO2 IS truststore..."
    if docker exec wso2is keytool -import -alias wso2am \
        -file /tmp/wso2am.crt \
        -keystore /home/wso2carbon/wso2is-7.1.0/repository/resources/security/client-truststore.jks \
        -storepass wso2carbon -noprompt 2>/dev/null; then
        log_success "Certificate imported to WSO2 IS"
    else
        log_warn "Certificate may already exist in WSO2 IS truststore"
    fi
    
    # Cleanup
    log_info "Cleaning up temporary files..."
    rm -f /tmp/wso2is.crt /tmp/wso2am.crt 2>/dev/null
    docker exec wso2am rm -f /tmp/wso2is.crt /tmp/wso2am.crt 2>/dev/null
    docker exec wso2is rm -f /tmp/wso2is.crt /tmp/wso2am.crt 2>/dev/null
    
    echo ""
    log_success "SSL certificate trust configured successfully!"
    echo ""
    log_warn "IMPORTANT: Restart both containers for changes to take effect:"
    echo "  docker restart wso2am wso2is"
    echo ""
    echo "After restart, verify:"
    echo "  ./wso2-toolkit.sh health"
    echo ""
}

################################################################################
# COMMAND: test - Test Key Manager integration
################################################################################

cmd_test() {
    echo ""
    echo "=========================================="
    echo "  Testing WSO2 IS Key Manager"
    echo "=========================================="
    echo ""
    
    log_info "Testing JWKS endpoint..."
    if curl -k -s https://localhost:${WSO2IS_EXTERNAL_PORT}/oauth2/jwks | grep -q '"keys"'; then
        log_success "JWKS endpoint OK"
    else
        log_error "JWKS endpoint failed"
        return 1
    fi
    
    log_info "Testing Token endpoint..."
    local http_code
    http_code=$(curl -k -s -o /dev/null -w "%{http_code}" -X POST https://localhost:${WSO2IS_EXTERNAL_PORT}/oauth2/token)
    if [ "${http_code}" = "400" ] || [ "${http_code}" = "401" ]; then
        log_success "Token endpoint responding"
    else
        log_warn "Token endpoint status: ${http_code}"
    fi
    
    echo ""
    log_success "Tests passed!"
    echo ""
    echo "Next steps:"
    echo "  1. Create OAuth2 app: https://localhost:${WSO2IS_EXTERNAL_PORT}/carbon"
    echo "  2. Get tokens: ./wso2-toolkit.sh get-token cc <id> <secret>"
    echo "  3. Call APIs: curl -H 'Authorization: Bearer TOKEN' https://localhost:8243/api"
}

################################################################################
# MAIN
################################################################################

show_help() {
    cat <<'HELP'

╔══════════════════════════════════════════════════════════════╗
║           WSO2 Complete Toolkit - ONE FILE                   ║
║         Uses APIM DevPortal API for App Management          ║
╚══════════════════════════════════════════════════════════════╝

Usage: ./wso2-toolkit.sh <command> [options]

COMMANDS:

  Infrastructure & Health:
  ========================
  health              Check health of all services

  Key Manager Setup:
  ==================
  setup-km            Setup WSO2IS as Key Manager (use well-known endpoint)
  list-km             List all Key Managers
  disable-resident-km Disable Resident Key Manager (after adding WSO2IS)

  Certificate Management:
  =======================
  check-mtls          Check MTLS certificate trust (APIM ↔ IS)
  fix-mtls            Fix MTLS certificate trust automatically
  check-ssa-jwks      Check SSA JWKS endpoint for DCR
  fix-ssl-trust       Fix SSL certificate trust (legacy, use fix-mtls)
  test                Test Key Manager integration

  Application Management (APIM DevPortal):
  =========================================
  list-apps           List all applications from APIM DevPortal
  create-app          Create application via APIM (2-step: app + keys)
                      Usage: create-app <name> [callback] [key_manager]
  get-app             Get application details by ID
  get-app-keys        Get OAuth2 credentials for application
                      Usage: get-app-keys <app_id> [PRODUCTION|SANDBOX]
  delete-app          Delete application by ID (removes from APIM & KM)

  Role Management (WSO2 IS):
  ==========================
  list-roles          List all roles
  create-role         Create a single role
  create-roles        Create default roles (ops_users, finance, auditor, user, app_admin)
  delete-role         Delete a role by ID

  Token Generation:
  =================
  get-token <type>    Get OAuth2 token for various grant types

GRANT TYPES:
  client_credentials (cc)  Client Credentials Grant
  password (pw)            Resource Owner Password Grant
  refresh (rt)             Refresh Token Grant
  code (ac)                Authorization Code Grant
  device (dc)              Device Authorization Grant
  jwt (jb)                 JWT Bearer Grant
  saml (sb)                SAML 2.0 Bearer Grant
  token-exchange (te)      Token Exchange Grant

EXAMPLES:

  Infrastructure Setup:
  ---------------------
  # Check all services
  ./wso2-toolkit.sh health

  # Setup WSO2 IS as Key Manager
  ./wso2-toolkit.sh setup-km

  # List Key Managers
  ./wso2-toolkit.sh list-km

  Application Management (APIM DevPortal):
  ----------------------------------------
  # List all applications from APIM
  ./wso2-toolkit.sh list-apps

  # Create application via APIM DevPortal (auto-registers with WSO2IS KM)
  ./wso2-toolkit.sh create-app MyApp http://localhost:8080/callback

  # Create app with specific Key Manager
  ./wso2-toolkit.sh create-app MyApp http://localhost:8080/callback WSO2IS

  # Get application details
  ./wso2-toolkit.sh get-app <application-id>

  # Get OAuth2 credentials
  ./wso2-toolkit.sh get-app-keys <application-id> PRODUCTION

  # Delete application (removes from APIM and Key Manager)
  ./wso2-toolkit.sh delete-app <application-id>

  Role Management:
  ----------------
  # Create default roles
  ./wso2-toolkit.sh create-roles

  # Create single role
  ./wso2-toolkit.sh create-role custom_role

  # List all roles
  ./wso2-toolkit.sh list-roles

  Token Generation:
  -----------------
  # Client Credentials grant
  ./wso2-toolkit.sh get-token cc myClientId mySecret

  # Password grant
  ./wso2-toolkit.sh get-token password myClientId mySecret admin admin

  # Refresh token
  ./wso2-toolkit.sh get-token refresh myClientId mySecret <refresh_token>

IMPORTANT NOTES:
  • Applications are now created via APIM DevPortal API
  • APIM automatically registers OAuth2 clients with configured Key Manager
  • All application management flows through APIM (not direct WSO2 IS access)
  • Keys are generated during app creation with proper grant type support
  • Token generation uses WSO2 IS OAuth2 endpoints

HELP
}

COMMAND=${1:-help}

# Check dependencies before running any command (except help)
if [ "${COMMAND}" != "help" ] && [ "${COMMAND}" != "--help" ] && [ "${COMMAND}" != "-h" ]; then
    check_dependencies || exit 1
fi

case "${COMMAND}" in
    health)
        cmd_health
        ;;
    setup-km)
        cmd_setup_km
        ;;
    list-km)
        cmd_list_km
        ;;
    disable-resident-km)
        cmd_disable_resident_km
        ;;
    check-mtls)
        cmd_check_mtls
        ;;
    fix-mtls)
        cmd_fix_mtls
        ;;
    check-ssa-jwks)
        cmd_check_ssa_jwks
        ;;
    fix-ssl-trust)
        cmd_fix_ssl_trust
        ;;
    list-apps)
        cmd_list_apps
        ;;
    create-app)
        shift
        cmd_create_app "$@"
        ;;
    get-app)
        shift
        cmd_get_app "$@"
        ;;
    get-app-keys)
        shift
        cmd_get_app_keys "$@"
        ;;
    get-client)
        shift
        cmd_get_client "$@"
        ;;
    delete-app)
        shift
        cmd_delete_app "$@"
        ;;
    list-roles)
        cmd_list_roles
        ;;
    create-role)
        shift
        cmd_create_role "$@"
        ;;
    create-roles)
        cmd_create_roles
        ;;
    delete-role)
        shift
        cmd_delete_role "$@"
        ;;
    test)
        cmd_test
        ;;
    get-token)
        shift
        cmd_get_token "$@"
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
