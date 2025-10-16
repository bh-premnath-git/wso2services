#!/bin/bash

################################################################################
# WSO2 Identity Server Key Manager Validation Script
# 
# Purpose: Validate WSO2 IS external Key Manager configuration in APIM
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WSO2_IS_HOST="${WSO2_IS_HOST:-localhost}"
WSO2_IS_PORT="${WSO2_IS_PORT:-9444}"
WSO2_IS_INTERNAL="${WSO2_IS_INTERNAL:-wso2is:9443}"
WSO2_AM_HOST="${WSO2_AM_HOST:-localhost}"
WSO2_AM_PORT="${WSO2_AM_PORT:-9443}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin}"

TMP_DIR="/tmp/wso2_km_validation_$$"
mkdir -p "$TMP_DIR"

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

################################################################################
# Test 1: Check WSO2 IS Health
################################################################################
check_wso2_is_health() {
    print_header "Test 1: WSO2 Identity Server Health"
    
    log_info "Checking WSO2 IS OIDC discovery endpoint..."
    
    if DISCOVERY=$(curl -sk --max-time 10 \
        "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/token/.well-known/openid-configuration" 2>/dev/null); then
        
        TOKEN_ENDPOINT=$(echo "$DISCOVERY" | grep -o '"token_endpoint":"[^"]*' | cut -d'"' -f4)
        INTROSPECT_ENDPOINT=$(echo "$DISCOVERY" | grep -o '"introspection_endpoint":"[^"]*' | cut -d'"' -f4)
        
        log_success "WSO2 IS is accessible"
        log_info "Token endpoint: $TOKEN_ENDPOINT"
        log_info "Introspection endpoint: $INTROSPECT_ENDPOINT"
        return 0
    else
        log_error "Cannot reach WSO2 IS at https://${WSO2_IS_HOST}:${WSO2_IS_PORT}"
        return 1
    fi
}

################################################################################
# Test 2: Check WSO2 IS Key Manager Configuration in APIM
################################################################################
check_keymanager_config() {
    print_header "Test 2: WSO2 IS Key Manager Configuration in APIM"
    
    log_info "Fetching Key Manager list from APIM..."
    
    KM_RESPONSE=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
        "https://${WSO2_AM_HOST}:${WSO2_AM_PORT}/api/am/admin/v4/key-managers" 2>/dev/null)
    
    if [ -z "$KM_RESPONSE" ]; then
        log_error "Failed to fetch Key Managers from APIM"
        return 1
    fi
    
    # Check if WSO2 IS Key Manager exists
    IS_KM_NAME=$(echo "$KM_RESPONSE" | grep -o '"name":"[^"]*WSO2-IS[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -z "$IS_KM_NAME" ]; then
        log_error "WSO2 IS Key Manager NOT found in APIM"
        log_error "Available Key Managers:"
        echo "$KM_RESPONSE" | grep -o '"name":"[^"]*"' | cut -d'"' -f4
        echo ""
        log_error "Please run: ./app_scripts/register_wso2is_keymanager.sh"
        return 1
    fi
    
    log_success "Found Key Manager: $IS_KM_NAME"
    
    # Get detailed configuration - extract ID for WSO2-IS-KeyManager only
    KM_ID=$(echo "$KM_RESPONSE" | jq -r ".list[] | select(.name==\"${IS_KM_NAME}\") | .id" 2>/dev/null)
    
    if [ -n "$KM_ID" ]; then
        log_info "Key Manager ID: $KM_ID"
        
        KM_DETAILS=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" \
            "https://${WSO2_AM_HOST}:${WSO2_AM_PORT}/api/am/admin/v4/key-managers/${KM_ID}" 2>/dev/null)
        
        # Validate endpoints
        log_info "Validating Key Manager endpoints..."
        
        TOKEN_EP=$(echo "$KM_DETAILS" | grep -o '"tokenEndpoint":"[^"]*' | cut -d'"' -f4)
        INTROSPECT_EP=$(echo "$KM_DETAILS" | grep -o '"introspectionEndpoint":"[^"]*' | cut -d'"' -f4)
        DCR_EP=$(echo "$KM_DETAILS" | grep -o '"clientRegistrationEndpoint":"[^"]*' | cut -d'"' -f4)
        ENABLED=$(echo "$KM_DETAILS" | grep -o '"enabled":[^,}]*' | cut -d':' -f2 | tr -d ' ')
        
        echo ""
        log_info "Configuration:"
        log_info "  Token Endpoint: ${TOKEN_EP:-NOT SET}"
        log_info "  Introspection Endpoint: ${INTROSPECT_EP:-NOT SET}"
        log_info "  DCR Endpoint: ${DCR_EP:-NOT SET}"
        log_info "  Enabled: ${ENABLED:-false}"
        echo ""
        
        # Check if endpoints point to WSO2 IS
        if echo "$TOKEN_EP" | grep -q "wso2is\|${WSO2_IS_HOST}"; then
            log_success "Token endpoint correctly points to WSO2 IS"
        else
            log_error "Token endpoint does NOT point to WSO2 IS"
            return 1
        fi
        
        if echo "$INTROSPECT_EP" | grep -q "wso2is\|${WSO2_IS_HOST}"; then
            log_success "Introspection endpoint correctly points to WSO2 IS"
        else
            log_error "Introspection endpoint does NOT point to WSO2 IS"
            return 1
        fi
        
        if [ "$ENABLED" = "true" ]; then
            log_success "Key Manager is enabled"
        else
            log_error "Key Manager is DISABLED"
            return 1
        fi
        
        return 0
    else
        log_error "Could not fetch Key Manager details"
        return 1
    fi
}

################################################################################
# Test 3: Test OAuth Token Generation via WSO2 IS
################################################################################
test_token_generation() {
    print_header "Test 3: OAuth Token Generation via WSO2 IS"
    
    log_info "Creating OAuth client via DCR..."
    
    DCR_RESPONSE=$(curl -sk -w "\nHTTP_CODE:%{http_code}" -X POST \
        "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/api/identity/oauth2/dcr/v1.1/register" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d '{
            "client_name": "KM_Validation_Test_'$$'",
            "grant_types": ["client_credentials", "password"],
            "redirect_uris": ["https://localhost/callback"]
        }' 2>&1)
    
    HTTP_CODE=$(echo "$DCR_RESPONSE" | grep -o 'HTTP_CODE:[0-9]*' | cut -d':' -f2)
    DCR_BODY=$(echo "$DCR_RESPONSE" | sed 's/HTTP_CODE:[0-9]*//')
    
    if [ "$HTTP_CODE" != "201" ] && [ "$HTTP_CODE" != "200" ]; then
        log_error "DCR failed (HTTP $HTTP_CODE)"
        echo "$DCR_BODY"
        return 1
    fi
    
    CLIENT_ID=$(echo "$DCR_BODY" | grep -o '"client_id":"[^"]*' | cut -d'"' -f4)
    CLIENT_SECRET=$(echo "$DCR_BODY" | grep -o '"client_secret":"[^"]*' | cut -d'"' -f4)
    
    echo "$CLIENT_ID" > "$TMP_DIR/client_id.txt"
    echo "$CLIENT_SECRET" > "$TMP_DIR/client_secret.txt"
    
    log_success "OAuth client created"
    log_info "Client ID: $CLIENT_ID"
    
    # Generate token
    log_info "Generating access token..."
    
    TOKEN_RESPONSE=$(curl -sk -w "\nHTTP_CODE:%{http_code}" \
        -u "${CLIENT_ID}:${CLIENT_SECRET}" \
        -X POST "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/token" \
        -d "grant_type=client_credentials" 2>&1)
    
    HTTP_CODE=$(echo "$TOKEN_RESPONSE" | grep -o 'HTTP_CODE:[0-9]*' | cut -d':' -f2)
    TOKEN_BODY=$(echo "$TOKEN_RESPONSE" | sed 's/HTTP_CODE:[0-9]*//')
    
    if [ "$HTTP_CODE" != "200" ]; then
        log_error "Token generation failed (HTTP $HTTP_CODE)"
        echo "$TOKEN_BODY"
        return 1
    fi
    
    ACCESS_TOKEN=$(echo "$TOKEN_BODY" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
    echo "$ACCESS_TOKEN" > "$TMP_DIR/access_token.txt"
    
    log_success "Access token generated successfully"
    log_info "Token (first 40 chars): ${ACCESS_TOKEN:0:40}..."
    
    return 0
}

################################################################################
# Test 4: Validate Token Introspection
################################################################################
test_token_introspection() {
    print_header "Test 4: Token Introspection via WSO2 IS"
    
    if [ ! -f "$TMP_DIR/access_token.txt" ]; then
        log_error "No access token available"
        return 1
    fi
    
    ACCESS_TOKEN=$(cat "$TMP_DIR/access_token.txt")
    
    log_info "Introspecting token..."
    
    INTROSPECT_RESPONSE=$(curl -sk -w "\nHTTP_CODE:%{http_code}" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -X POST "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/introspect" \
        -d "token=${ACCESS_TOKEN}" 2>&1)
    
    HTTP_CODE=$(echo "$INTROSPECT_RESPONSE" | grep -o 'HTTP_CODE:[0-9]*' | cut -d':' -f2)
    INTROSPECT_BODY=$(echo "$INTROSPECT_RESPONSE" | sed 's/HTTP_CODE:[0-9]*//')
    
    if [ "$HTTP_CODE" != "200" ]; then
        log_error "Introspection failed (HTTP $HTTP_CODE)"
        echo "$INTROSPECT_BODY"
        return 1
    fi
    
    ACTIVE=$(echo "$INTROSPECT_BODY" | grep -o '"active":[^,}]*' | cut -d':' -f2 | tr -d ' ')
    
    if [ "$ACTIVE" = "true" ]; then
        log_success "Token is valid and active"
        
        CLIENT_ID=$(echo "$INTROSPECT_BODY" | grep -o '"client_id":"[^"]*' | cut -d'"' -f4)
        TOKEN_TYPE=$(echo "$INTROSPECT_BODY" | grep -o '"token_type":"[^"]*' | cut -d'"' -f4)
        
        log_info "Client ID: $CLIENT_ID"
        log_info "Token Type: $TOKEN_TYPE"
        return 0
    else
        log_error "Token is invalid"
        echo "$INTROSPECT_BODY"
        return 1
    fi
}

################################################################################
# Test 5: Test with User Password Grant (if user exists)
################################################################################
test_password_grant() {
    print_header "Test 5: Password Grant with WSO2 IS User"
    
    if [ ! -f "$TMP_DIR/client_id.txt" ]; then
        log_warning "No client credentials available, skipping password grant test"
        return 0
    fi
    
    CLIENT_ID=$(cat "$TMP_DIR/client_id.txt")
    CLIENT_SECRET=$(cat "$TMP_DIR/client_secret.txt")
    
    log_info "Testing password grant for user 'ops_user'..."
    
    TOKEN_RESPONSE=$(curl -sk -w "\nHTTP_CODE:%{http_code}" \
        -u "${CLIENT_ID}:${CLIENT_SECRET}" \
        -X POST "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/token" \
        -d "grant_type=password&username=ops_user&password=OpsUser123!" 2>&1)
    
    HTTP_CODE=$(echo "$TOKEN_RESPONSE" | grep -o 'HTTP_CODE:[0-9]*' | cut -d':' -f2)
    TOKEN_BODY=$(echo "$TOKEN_RESPONSE" | sed 's/HTTP_CODE:[0-9]*//')
    
    if [ "$HTTP_CODE" = "200" ]; then
        ACCESS_TOKEN=$(echo "$TOKEN_BODY" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
        log_success "Password grant successful for ops_user"
        log_info "User token (first 40 chars): ${ACCESS_TOKEN:0:40}..."
        return 0
    else
        log_warning "Password grant failed (HTTP $HTTP_CODE)"
        log_info "This is expected if user 'ops_user' doesn't exist"
        log_info "Run: ./app_scripts/setup_is_users_roles.sh"
        return 0
    fi
}

################################################################################
# Cleanup
################################################################################
cleanup() {
    log_info "Cleaning up test resources..."
    
    if [ -f "$TMP_DIR/client_id.txt" ]; then
        CLIENT_ID=$(cat "$TMP_DIR/client_id.txt")
        
        curl -sk -X DELETE \
            "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/api/identity/oauth2/dcr/v1.1/register/${CLIENT_ID}" \
            -u "${ADMIN_USER}:${ADMIN_PASS}" > /dev/null 2>&1
        
        log_success "Test OAuth client deleted"
    fi
    
    rm -rf "$TMP_DIR"
}

################################################################################
# Main
################################################################################
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  WSO2 IS External Key Manager Validation                  ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    trap cleanup EXIT
    
    FAILED=0
    
    check_wso2_is_health || ((FAILED++))
    check_keymanager_config || ((FAILED++))
    test_token_generation || ((FAILED++))
    test_token_introspection || ((FAILED++))
    test_password_grant
    
    print_header "Validation Summary"
    
    if [ $FAILED -eq 0 ]; then
        log_success "All tests passed!"
        echo ""
        log_success "✓ WSO2 IS is healthy"
        log_success "✓ WSO2 IS Key Manager is correctly configured in APIM"
        log_success "✓ Token generation works"
        log_success "✓ Token introspection works"
        echo ""
        log_info "Key Manager integration is working correctly"
        exit 0
    else
        log_error "$FAILED critical test(s) failed"
        echo ""
        log_error "Please check:"
        log_error "  1. WSO2 IS is running and accessible"
        log_error "  2. Key Manager is registered: ./app_scripts/register_wso2is_keymanager.sh"
        log_error "  3. SSL certificates are configured: ./app_scripts/fix_ssl_certificates.sh"
        exit 1
    fi
}

main "$@"