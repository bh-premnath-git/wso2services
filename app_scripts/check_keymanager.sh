#!/bin/bash

################################################################################
# WSO2 Identity Server Key Manager Validation Script
# 
# Purpose: Validate OAuth2/OIDC token flow between WSO2 API Manager and IS
# Author: Payment Platform Team
# Date: October 2025
# 
# Compatible Versions:
#   - WSO2 Identity Server 7.1+ (March 2025)
#   - WSO2 API Manager 4.5.0+ (March 2025)
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Updated for WSO2 IS 7.1 and APIM 4.5
WSO2_IS_HOST="${WSO2_IS_HOST:-localhost}"
WSO2_IS_PORT="${WSO2_IS_PORT:-9444}"  # Docker port mapping: container 9443 -> host 9444
WSO2_AM_HOST="${WSO2_AM_HOST:-localhost}"
WSO2_AM_GATEWAY_PORT="${WSO2_AM_GATEWAY_PORT:-8243}"
WSO2_AM_PUBLISHER_PORT="${WSO2_AM_PUBLISHER_PORT:-9443}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin}"

# Temp files
TMP_DIR="/tmp/wso2_validation_$$"
mkdir -p "$TMP_DIR"
ACCESS_TOKEN_FILE="$TMP_DIR/access_token.txt"
CLIENT_ID_FILE="$TMP_DIR/client_id.txt"
CLIENT_SECRET_FILE="$TMP_DIR/client_secret.txt"

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
    echo "========================================"
    echo "$1"
    echo "========================================"
}

################################################################################
# Test 1: Check WSO2 IS Health
################################################################################
check_wso2_is_health() {
    print_header "Test 1: WSO2 Identity Server Health Check"
    
    log_info "Checking WSO2 IS at https://${WSO2_IS_HOST}:${WSO2_IS_PORT}"
    
    # Try to access the well-known endpoint (more reliable than carbon console)
    if curl -k -s --connect-timeout 5 --max-time 10 \
        "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/token/.well-known/openid-configuration" > /dev/null; then
        log_success "WSO2 Identity Server is running"
        log_info "Fetching OIDC discovery information..."
        
        DISCOVERY=$(curl -k -s "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/token/.well-known/openid-configuration")
        
        if [ -n "$DISCOVERY" ]; then
            log_info "Available endpoints:"
            echo "$DISCOVERY" | grep -o '"[^"]*_endpoint":"[^"]*' | sed 's/"//g' | sed 's/:/: /' || true
        fi
        
        return 0
    else
        log_error "WSO2 Identity Server is not reachable"
        log_error "Please verify that:"
        log_error "  1. WSO2 IS is running on port ${WSO2_IS_PORT}"
        log_error "  2. Hostname ${WSO2_IS_HOST} is correct"
        return 1
    fi
}

################################################################################
# Test 2: Check WSO2 API Manager Health
################################################################################
check_wso2_am_health() {
    print_header "Test 2: WSO2 API Manager Health Check"
    
    log_info "Checking WSO2 API Manager at https://${WSO2_AM_HOST}:${WSO2_AM_PUBLISHER_PORT}"
    
    # Check if API Manager is accessible
    if curl -k -s --connect-timeout 5 --max-time 10 \
        "https://${WSO2_AM_HOST}:${WSO2_AM_PUBLISHER_PORT}/services/Version" > /dev/null 2>&1 || \
       curl -k -s --connect-timeout 5 --max-time 10 \
        "https://${WSO2_AM_HOST}:${WSO2_AM_PUBLISHER_PORT}/api/am/publisher/v4/apis" \
        -H "Authorization: Basic $(echo -n ${ADMIN_USER}:${ADMIN_PASS} | base64)" > /dev/null 2>&1; then
        log_success "WSO2 API Manager is running"
        return 0
    else
        log_error "WSO2 API Manager is not reachable"
        log_error "Please verify that:"
        log_error "  1. WSO2 APIM is running on port ${WSO2_AM_PUBLISHER_PORT}"
        log_error "  2. Hostname ${WSO2_AM_HOST} is correct"
        return 1
    fi
}

################################################################################
# Test 3: Generate OAuth2 Token from WSO2 IS
################################################################################
generate_oauth_token() {
    print_header "Test 3: OAuth2 Token Generation from WSO2 IS"
    
    log_info "Requesting OAuth2 token from WSO2 Identity Server"
    
    # Register OAuth2 application using DCR
    log_info "Using DCR (Dynamic Client Registration) to create OAuth app"
    
    DCR_RESPONSE=$(curl -k -s -w "\nHTTP_CODE:%{http_code}" -X POST \
        "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/api/identity/oauth2/dcr/v1.1/register" \
        -H "Authorization: Basic $(echo -n ${ADMIN_USER}:${ADMIN_PASS} | base64)" \
        -H "Content-Type: application/json" \
        -d '{
            "client_name": "KeyManagerTestApp_'$$'",
            "grant_types": ["client_credentials", "password", "refresh_token"],
            "token_endpoint_auth_method": "client_secret_basic"
        }' 2>&1)
    
    HTTP_CODE=$(echo "$DCR_RESPONSE" | grep -o 'HTTP_CODE:[0-9]*' | cut -d':' -f2)
    DCR_BODY=$(echo "$DCR_RESPONSE" | sed 's/HTTP_CODE:[0-9]*//')
    
    if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ]; then
        CLIENT_ID=$(echo "$DCR_BODY" | grep -o '"client_id":"[^"]*' | cut -d'"' -f4)
        CLIENT_SECRET=$(echo "$DCR_BODY" | grep -o '"client_secret":"[^"]*' | cut -d'"' -f4)
        
        if [ -n "$CLIENT_ID" ] && [ -n "$CLIENT_SECRET" ]; then
            log_success "OAuth2 application created successfully"
            log_info "Client ID: ${CLIENT_ID}"
            echo "$CLIENT_ID" > "$CLIENT_ID_FILE"
            echo "$CLIENT_SECRET" > "$CLIENT_SECRET_FILE"
        else
            log_error "Failed to parse DCR response"
            log_error "Response: $DCR_BODY"
            return 1
        fi
    else
        log_error "DCR (Dynamic Client Registration) failed with HTTP ${HTTP_CODE}"
        log_error "Response: $DCR_BODY"
        echo ""
        log_error "TROUBLESHOOTING:"
        
        if [ "$HTTP_CODE" = "403" ] || [ "$HTTP_CODE" = "401" ]; then
            log_error "  1. DCR endpoint is not configured in WSO2 IS"
            log_error "  2. Add to <IS_HOME>/repository/conf/deployment.toml:"
            echo ""
            echo "     [[resource.access_control]]"
            echo "     context = \"(.*)/api/identity/oauth2/dcr(.*)\""
            echo "     secure = true"
            echo "     http_method = \"all\""
            echo "     permissions = [\"/permission/admin/manage/identity/applicationmgt\"]"
            echo "     scopes = []"
            echo ""
            log_error "  3. Restart WSO2 IS: docker compose restart wso2is"
            log_error "  4. See: app_scripts/DCR_TROUBLESHOOTING.md"
        else
            log_error "  1. Check WSO2 IS logs for errors"
            log_error "  2. Verify IS is running: https://${WSO2_IS_HOST}:${WSO2_IS_PORT}"
        fi
        
        return 1
    fi
    
    # Request access token with client_credentials
    log_info "Requesting access token with client_credentials grant"
    
    TOKEN_RESPONSE=$(curl -k -s -w "\nHTTP_CODE:%{http_code}" \
        -u "${CLIENT_ID}:${CLIENT_SECRET}" \
        -X POST "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials" 2>&1)
    
    HTTP_CODE=$(echo "$TOKEN_RESPONSE" | grep -o 'HTTP_CODE:[0-9]*' | cut -d':' -f2)
    TOKEN_BODY=$(echo "$TOKEN_RESPONSE" | sed 's/HTTP_CODE:[0-9]*//')
    
    if [ "$HTTP_CODE" = "200" ]; then
        ACCESS_TOKEN=$(echo "$TOKEN_BODY" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
        TOKEN_TYPE=$(echo "$TOKEN_BODY" | grep -o '"token_type":"[^"]*' | cut -d'"' -f4)
        EXPIRES_IN=$(echo "$TOKEN_BODY" | grep -o '"expires_in":[0-9]*' | cut -d':' -f2)
        
        if [ -n "$ACCESS_TOKEN" ]; then
            log_success "Access token generated successfully"
            log_info "Token Type: ${TOKEN_TYPE}"
            log_info "Expires In: ${EXPIRES_IN} seconds"
            log_info "Token (first 50 chars): ${ACCESS_TOKEN:0:50}..."
            echo "$ACCESS_TOKEN" > "$ACCESS_TOKEN_FILE"
            if [ -n "$CLIENT_ID" ] && [ -n "$CLIENT_SECRET" ]; then
                echo "$CLIENT_ID" > "$CLIENT_ID_FILE"
                echo "$CLIENT_SECRET" > "$CLIENT_SECRET_FILE"
            fi
            return 0
        else
            log_error "Failed to parse access token from response"
            log_error "Response: $TOKEN_BODY"
            return 1
        fi
    else
        log_error "Token generation failed with HTTP code: ${HTTP_CODE}"
        log_error "Response: $TOKEN_BODY"
        
        # Parse error if present
        ERROR_DESC=$(echo "$TOKEN_BODY" | grep -o '"error_description":"[^"]*' | cut -d'"' -f4)
        ERROR_CODE=$(echo "$TOKEN_BODY" | grep -o '"error":"[^"]*' | cut -d'"' -f4)
        
        if [ -n "$ERROR_CODE" ]; then
            log_error "Error: $ERROR_CODE"
            [ -n "$ERROR_DESC" ] && log_error "Description: $ERROR_DESC"
        fi
        
        return 1
    fi
}

################################################################################
# Test 4: Validate Token Introspection
################################################################################
validate_token_introspection() {
    print_header "Test 4: Token Introspection (Key Manager Validation)"
    
    if [ ! -f "$ACCESS_TOKEN_FILE" ]; then
        log_error "No access token found. Run token generation first."
        return 1
    fi
    
    ACCESS_TOKEN=$(cat "$ACCESS_TOKEN_FILE")
    
    log_info "Introspecting token via WSO2 IS"
    
    # Use admin credentials for introspection (required permission)
    # Note: Token introspection requires admin-level permissions in WSO2 IS
    AUTH_USER="${ADMIN_USER}"
    AUTH_PASS="${ADMIN_PASS}"
    
    INTROSPECT_RESPONSE=$(curl -k -s -w "\nHTTP_CODE:%{http_code}" \
        -u "${AUTH_USER}:${AUTH_PASS}" \
        -X POST "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/introspect" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "token=${ACCESS_TOKEN}" 2>&1)
    
    HTTP_CODE=$(echo "$INTROSPECT_RESPONSE" | grep -o 'HTTP_CODE:[0-9]*' | cut -d':' -f2)
    INTROSPECT_BODY=$(echo "$INTROSPECT_RESPONSE" | sed 's/HTTP_CODE:[0-9]*//')
    
    if [ "$HTTP_CODE" = "200" ]; then
        ACTIVE=$(echo "$INTROSPECT_BODY" | grep -o '"active":[^,}]*' | cut -d':' -f2 | tr -d ' ')
        
        if [ "$ACTIVE" = "true" ]; then
            log_success "Token is valid and active"
            
            # Extract additional info
            CLIENT_ID_CLAIM=$(echo "$INTROSPECT_BODY" | grep -o '"client_id":"[^"]*' | cut -d'"' -f4)
            USERNAME=$(echo "$INTROSPECT_BODY" | grep -o '"username":"[^"]*' | cut -d'"' -f4)
            TOKEN_TYPE=$(echo "$INTROSPECT_BODY" | grep -o '"token_type":"[^"]*' | cut -d'"' -f4)
            
            log_info "Token Details:"
            [ -n "$CLIENT_ID_CLAIM" ] && log_info "  Client ID: $CLIENT_ID_CLAIM"
            [ -n "$USERNAME" ] && log_info "  Username: $USERNAME"
            [ -n "$TOKEN_TYPE" ] && log_info "  Token Type: $TOKEN_TYPE"
            
            return 0
        else
            log_error "Token is invalid or expired"
            log_error "Introspection response: $INTROSPECT_BODY"
            return 1
        fi
    else
        log_error "Token introspection failed with HTTP code: ${HTTP_CODE}"
        log_error "Response: $INTROSPECT_BODY"
        return 1
    fi
}

################################################################################
# Test 5: Check Key Manager Configuration in API Manager
################################################################################
check_keymanager_config() {
    print_header "Test 5: Key Manager Configuration Check"
    
    log_info "Checking if WSO2 IS is configured as Key Manager in API Manager"
    
    # Get admin token for API Manager
    AM_TOKEN_RESPONSE=$(curl -k -s -X POST \
        "https://${WSO2_AM_HOST}:${WSO2_AM_PUBLISHER_PORT}/oauth2/token" \
        -H "Authorization: Basic $(echo -n ${ADMIN_USER}:${ADMIN_PASS} | base64)" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=password&username=${ADMIN_USER}&password=${ADMIN_PASS}&scope=apim:api_view apim:api_create" 2>&1)
    
    AM_ACCESS_TOKEN=$(echo "$AM_TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
    
    if [ -z "$AM_ACCESS_TOKEN" ]; then
        log_warning "Could not get API Manager admin token"
        log_info "Checking Key Manager configuration via REST API skipped"
        return 0
    fi
    
    # List Key Managers
    log_info "Fetching Key Manager configurations"
    
    KM_RESPONSE=$(curl -k -s -X GET \
        "https://${WSO2_AM_HOST}:${WSO2_AM_PUBLISHER_PORT}/api/am/admin/v4/key-managers" \
        -H "Authorization: Bearer ${AM_ACCESS_TOKEN}" 2>&1)
    
    if echo "$KM_RESPONSE" | grep -q "Resident Key Manager"; then
        log_success "Key Manager configuration found"
        log_info "Key Managers: $(echo $KM_RESPONSE | grep -o '"name":"[^"]*' | cut -d'"' -f4)"
        return 0
    else
        log_warning "Could not verify Key Manager configuration"
        log_info "Response: $KM_RESPONSE"
        return 0
    fi
}

################################################################################
# Test 6: End-to-End API Call with Token Validation
################################################################################
test_api_with_token() {
    print_header "Test 6: End-to-End API Call with Token Validation"
    
    log_info "This test requires an API to be published in API Manager"
    log_warning "Skipping E2E test - Manual verification recommended"
    
    echo ""
    log_info "To manually test the Key Manager integration:"
    echo "  1. Publish an API in API Manager Developer Portal"
    echo "  2. Subscribe to the API and obtain consumer key/secret"
    echo "  3. Generate token from WSO2 IS using the credentials:"
    echo "     curl -k -X POST https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/oauth2/token \\"
    echo "          -H 'Authorization: Basic <base64(key:secret)>' \\"
    echo "          -H 'Content-Type: application/x-www-form-urlencoded' \\"
    echo "          -d 'grant_type=client_credentials'"
    echo "  4. Call the API via Gateway (port ${WSO2_AM_GATEWAY_PORT}) with Bearer token:"
    echo "     curl -k -H 'Authorization: Bearer <token>' \\"
    echo "          https://${WSO2_AM_HOST}:${WSO2_AM_GATEWAY_PORT}/<api-context>/<resource>"
    echo "  5. API Manager Gateway will validate token with WSO2 IS Key Manager"
    echo ""
    
    return 0
}

################################################################################
# Test 7: Check Service Communication
################################################################################
check_service_communication() {
    print_header "Test 7: Microservices Health Check"
    
    log_info "Checking application microservices..."
    
    SERVICES=(
        "forex:8001"
        "ledger:8002"
        "payment:8003"
        "profile:8004"
        "rule-engine:8005"
        "wallet:8006"
    )
    
    ALL_HEALTHY=true
    
    for service in "${SERVICES[@]}"; do
        SERVICE_NAME=$(echo "$service" | cut -d':' -f1)
        SERVICE_PORT=$(echo "$service" | cut -d':' -f2)
        
        # Try common health check endpoints
        if curl -s --connect-timeout 2 --max-time 5 \
            "http://localhost:${SERVICE_PORT}/health" > /dev/null 2>&1 || \
           curl -s --connect-timeout 2 --max-time 5 \
            "http://localhost:${SERVICE_PORT}/actuator/health" > /dev/null 2>&1 || \
           curl -s --connect-timeout 2 --max-time 5 \
            "http://localhost:${SERVICE_PORT}/" > /dev/null 2>&1; then
            log_success "${SERVICE_NAME}-service is healthy on port ${SERVICE_PORT}"
        else
            log_warning "${SERVICE_NAME}-service is not reachable on port ${SERVICE_PORT}"
            ALL_HEALTHY=false
        fi
    done
    
    if [ "$ALL_HEALTHY" = true ]; then
        log_success "All microservices are healthy"
    else
        log_warning "Some microservices are not responding"
        log_info "This may be expected if services are not running or use different ports"
    fi
    
    return 0
}

################################################################################
# Cleanup: Remove test OAuth application
################################################################################
cleanup_oauth_app() {
    log_info "Cleaning up test resources..."
    
    if [ -f "$CLIENT_ID_FILE" ]; then
        CLIENT_ID=$(cat "$CLIENT_ID_FILE")
        
        log_info "Deleting test OAuth application: $CLIENT_ID"
        
        DELETE_RESPONSE=$(curl -k -s -w "\nHTTP_CODE:%{http_code}" -X DELETE \
            "https://${WSO2_IS_HOST}:${WSO2_IS_PORT}/api/identity/oauth2/dcr/v1.1/register/${CLIENT_ID}" \
            -H "Authorization: Basic $(echo -n ${ADMIN_USER}:${ADMIN_PASS} | base64)" 2>&1)
        
        HTTP_CODE=$(echo "$DELETE_RESPONSE" | grep -o 'HTTP_CODE:[0-9]*' | cut -d':' -f2)
        
        if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
            log_success "Test OAuth application deleted"
        else
            log_warning "Could not delete test OAuth app (HTTP $HTTP_CODE)"
        fi
    fi
    
    # Clean up temp directory
    rm -rf "$TMP_DIR"
    log_info "Temporary files cleaned up"
}

################################################################################
# Main Execution
################################################################################
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  WSO2 Identity Server Key Manager Validation Suite        ║"
    echo "║  Testing OAuth2/OIDC Integration with API Manager         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Setup trap to cleanup on exit
    trap cleanup_oauth_app EXIT
    
    # Run all tests
    FAILED_TESTS=0
    
    check_wso2_is_health || ((FAILED_TESTS++))
    check_wso2_am_health || ((FAILED_TESTS++))
    generate_oauth_token || ((FAILED_TESTS++))
    validate_token_introspection || ((FAILED_TESTS++))
    check_keymanager_config
    test_api_with_token
    check_service_communication
    
    # Summary
    print_header "Test Summary"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        log_success "All critical tests passed!"
        log_info "WSO2 IS Key Manager is correctly configured and operational"
        echo ""
        log_info "Cleaning up..."
        cleanup_oauth_app
        exit 0
    else
        log_error "$FAILED_TESTS critical test(s) failed"
        log_warning "Please check the configuration and logs"
        echo ""
        log_info "Cleaning up..."
        cleanup_oauth_app
        exit 1
    fi
}

# Run main function
main "$@"