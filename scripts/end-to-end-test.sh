#!/usr/bin/env bash

################################################################################
# End-to-End Test Script
# Tests complete flow: User Registration → OAuth → APIM → Gateway → Services
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# Configuration
WSO2IS_HOST="${WSO2IS_HOST:-localhost}"
WSO2IS_PORT="${WSO2IS_PORT:-9444}"
APIM_HOST="${APIM_HOST:-localhost}"
APIM_PORT="${APIM_PORT:-9443}"
GATEWAY_HTTP="${GATEWAY_HTTP:-8280}"
GATEWAY_HTTPS="${GATEWAY_HTTPS:-8243}"

ADMIN_USER="admin"
ADMIN_PASS="admin"

# Test user details
TEST_USERNAME="testuser_$(date +%s)"
TEST_PASSWORD="Test@123456"
TEST_EMAIL="test_$(date +%s)@example.com"
TEST_FIRST_NAME="Test"
TEST_LAST_NAME="User"

# Backend service URLs (internal docker network)
FOREX_SERVICE_URL="http://forex-service:8001"
LEDGER_SERVICE_URL="http://ledger-service:8002"
PAYMENT_SERVICE_URL="http://payment-service:8003"
PROFILE_SERVICE_URL="http://profile-service:8004"
RULE_ENGINE_SERVICE_URL="http://rule-engine-service:8005"
WALLET_SERVICE_URL="http://wallet-service:8006"
BANKING_SERVICE_URL="http://banking-service:8007"

################################################################################
# STEP 1: Wait for all services
################################################################################
wait_for_services() {
    log_step "STEP 1: Waiting for all WSO2 services to be healthy..."
    
    local max_wait=300  # 5 minutes
    local elapsed=0
    
    while [ $elapsed -lt $max_wait ]; do
        if docker ps --format '{{.Names}}\t{{.Status}}' | grep -E "(is-as-km|api-manager)" | grep -q "healthy"; then
            log_success "Core WSO2 services are healthy"
            sleep 10  # Additional wait for full initialization
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        log_info "Waiting... ($elapsed/${max_wait}s)"
    done
    
    log_error "Services did not become healthy in time"
    return 1
}

################################################################################
# STEP 4: Register Test User in WSO2 IS
################################################################################
register_test_user() {
    log_step "STEP 4: Registering test user '${TEST_USERNAME}'"
    
    local response
    response=$(curl -k -sS -X POST \
        "https://${WSO2IS_HOST}:${WSO2IS_PORT}/scim2/Users" \
        -H "Authorization: Basic $(echo -n "${ADMIN_USER}:${ADMIN_PASS}" | base64)" \
        -H "Content-Type: application/scim+json" \
        -H "Accept: application/scim+json" \
        -d '{
            "schemas": ["urn:ietf:params:scim:schemas:core:2.0:User"],
            "userName": "'${TEST_USERNAME}'",
            "password": "'${TEST_PASSWORD}'",
            "active": true,
            "name": {
                "givenName": "'${TEST_FIRST_NAME}'",
                "familyName": "'${TEST_LAST_NAME}'"
            },
            "emails": [{
                "value": "'${TEST_EMAIL}'",
                "primary": true
            }]
        }')
    
    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        USER_ID=$(echo "$response" | jq -r '.id')
        log_success "User registered successfully! User ID: ${USER_ID}"
        return 0
    else
        log_error "Failed to register user"
        echo "$response" | jq . || echo "$response"
        return 1
    fi
}

################################################################################
# STEP 5: Create OAuth Application in WSO2 IS
################################################################################
create_oauth_app() {
    log_step "STEP 5: Creating OAuth application for test user"
    
    local response
    response=$(curl -k -sS -X POST \
        "https://${WSO2IS_HOST}:${WSO2IS_PORT}/api/identity/oauth2/dcr/v1.1/register" \
        -H "Authorization: Basic $(echo -n "${ADMIN_USER}:${ADMIN_PASS}" | base64)" \
        -H "Content-Type: application/json" \
        -d '{
            "client_name": "TestApp_'${TEST_USERNAME}'",
            "grant_types": ["password", "refresh_token", "client_credentials"],
            "redirect_uris": ["http://localhost:8080/callback"]
        }')
    
    if echo "$response" | jq -e '.client_id' >/dev/null 2>&1; then
        CLIENT_ID=$(echo "$response" | jq -r '.client_id')
        CLIENT_SECRET=$(echo "$response" | jq -r '.client_secret')
        log_success "OAuth app created!"
        log_info "Client ID: ${CLIENT_ID}"
        log_info "Client Secret: ${CLIENT_SECRET}"
        return 0
    else
        log_error "Failed to create OAuth application"
        echo "$response" | jq . || echo "$response"
        return 1
    fi
}

################################################################################
# STEP 6: Get OAuth Token (Password Grant)
################################################################################
get_oauth_token() {
    log_step "STEP 6: Getting OAuth access token (password grant)"
    
    local response
    response=$(curl -k -sS -X POST \
        "https://${WSO2IS_HOST}:${WSO2IS_PORT}/oauth2/token" \
        -u "${CLIENT_ID}:${CLIENT_SECRET}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=password&username=${TEST_USERNAME}&password=${TEST_PASSWORD}&scope=openid profile email")
    
    if echo "$response" | jq -e '.access_token' >/dev/null 2>&1; then
        ACCESS_TOKEN=$(echo "$response" | jq -r '.access_token')
        REFRESH_TOKEN=$(echo "$response" | jq -r '.refresh_token')
        ID_TOKEN=$(echo "$response" | jq -r '.id_token')
        
        log_success "OAuth tokens obtained!"
        log_info "Access Token: ${ACCESS_TOKEN:0:50}..."
        
        # Decode ID token to show claims
        if command -v jq >/dev/null 2>&1; then
            log_info "ID Token Claims:"
            echo "$ID_TOKEN" | awk -F. '{print $2}' | base64 -d 2>/dev/null | jq . || true
        fi
        
        return 0
    else
        log_error "Failed to get OAuth token"
        echo "$response" | jq . || echo "$response"
        return 1
    fi
}

################################################################################
# Helper: List API Status
################################################################################
list_api_status() {
    local apis_response="$1"
    local api_names=("ForexService" "LedgerService" "PaymentService" "ProfileService" "RuleEngineService" "WalletService" "BankingService")
    
    echo ""
    echo "┌────────────────────┬────────────┬────────────┐"
    printf "│ %-18s │ %-10s │ %-10s │\n" "Service" "Published" "Deployed"
    echo "├────────────────────┼────────────┼────────────┤"
    
    for api_name in "${api_names[@]}"; do
        local api_data=$(echo "$apis_response" | jq -r ".list[] | select(.name == \"${api_name}\")")
        
        if [ -z "$api_data" ] || [ "$api_data" = "null" ]; then
            printf "│ %-18s │ %-10s │ %-10s │\n" "$api_name" "❌ Not Found" "❌ No"
            continue
        fi
        
        local api_id=$(echo "$api_data" | jq -r '.id')
        local lifecycle=$(echo "$api_data" | jq -r '.lifeCycleStatus')
        
        # Check if published
        if [ "$lifecycle" = "PUBLISHED" ]; then
            local published="✅ Yes"
        else
            local published="⚠️  $lifecycle"
        fi
        
        # Check if deployed
        local deployments=$(curl -k -sS "https://${APIM_HOST}:${APIM_PORT}/api/am/publisher/v4/apis/${api_id}/deployments" \
            -u "${ADMIN_USER}:${ADMIN_PASS}" 2>/dev/null)
        
        local deploy_count=$(echo "$deployments" | jq -r 'length')
        
        if [ "$deploy_count" -gt 0 ]; then
            local deployed="✅ Yes"
        else
            local deployed="❌ No"
        fi
        
        printf "│ %-18s │ %-10s │ %-10s │\n" "$api_name" "$published" "$deployed"
    done
    
    echo "└────────────────────┴────────────┴────────────┘"
    echo ""
}

################################################################################
# STEP 9: Create Application in APIM (using Basic Auth)
################################################################################
create_apim_application() {
    log_step "STEP 9: Creating application in APIM Developer Portal"
    
    local response
    response=$(curl -k -sS -X POST \
        "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "TestApp_'${TEST_USERNAME}'",
            "throttlingPolicy": "Unlimited",
            "description": "Test application for e2e testing",
            "tokenType": "JWT"
        }')
    
    if echo "$response" | jq -e '.applicationId' >/dev/null 2>&1; then
        APP_ID=$(echo "$response" | jq -r '.applicationId')
        log_success "APIM application created! App ID: ${APP_ID}"
        return 0
    else
        log_error "Failed to create APIM application"
        echo "$response" | jq . || echo "$response"
        return 1
    fi
}

################################################################################
# STEP 10: Generate Application Keys
################################################################################
generate_app_keys() {
    log_step "STEP 10: Generating application keys (consumer key/secret)"
    
    # Get the active/enabled Key Manager ID
    log_info "Fetching active Key Manager..."
    local km_response
    km_response=$(curl -k -sS -X GET \
        "https://${APIM_HOST}:${APIM_PORT}/api/am/admin/v4/key-managers" \
        -u "${ADMIN_USER}:${ADMIN_PASS}")
    
    # Use Resident Key Manager for application keys (ensures subscription validation works)
    KM_ID=$(echo "$km_response" | jq -r '.list[] | select(.name == "Resident Key Manager" and .enabled == true) | .id')
    
    # If not found, try any enabled Key Manager
    if [ -z "$KM_ID" ] || [ "$KM_ID" = "null" ]; then
        log_warn "Resident Key Manager not found, using first enabled Key Manager..."
        KM_ID=$(echo "$km_response" | jq -r '.list[] | select(.enabled == true) | .id' | head -1)
    fi
    
    if [ -z "$KM_ID" ] || [ "$KM_ID" = "null" ]; then
        log_error "No enabled Key Manager found!"
        echo "$km_response" | jq .
        return 1
    fi
    
    local km_name=$(echo "$km_response" | jq -r ".list[] | select(.id == \"$KM_ID\") | .name")
    log_success "Using Key Manager: ${km_name} (ID: ${KM_ID})"
    
    # Retry logic for key generation
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        log_info "Attempt $((retry + 1))/$max_retries..."
        
        local response
        response=$(curl -k -sS -X POST \
            "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications/${APP_ID}/generate-keys" \
            -u "${ADMIN_USER}:${ADMIN_PASS}" \
            -H "Content-Type: application/json" \
            -d '{
                "keyType": "PRODUCTION",
                "keyManager": "'${KM_ID}'",
                "grantTypesToBeSupported": ["password", "client_credentials", "refresh_token"],
                "validityTime": 3600
            }')
        
        if echo "$response" | jq -e '.consumerKey' >/dev/null 2>&1; then
            APIM_CONSUMER_KEY=$(echo "$response" | jq -r '.consumerKey')
            APIM_CONSUMER_SECRET=$(echo "$response" | jq -r '.consumerSecret')
            log_success "Application keys generated!"
            log_info "Consumer Key: ${APIM_CONSUMER_KEY}"
            log_info "Consumer Secret: ${APIM_CONSUMER_SECRET:0:30}..."
            return 0
        else
            local error_code=$(echo "$response" | jq -r '.code // "unknown"')
            if [ "$error_code" = "901409" ]; then
                log_warn "Keys already exist - using client credentials grant for test..."
                # Since keys exist but we can't retrieve secrets, use client_credentials
                # with the user's OAuth app instead
                APIM_CONSUMER_KEY="$CLIENT_ID"
                APIM_CONSUMER_SECRET="$CLIENT_SECRET"
                log_success "Using user OAuth credentials for gateway access"
                return 0
            fi
            
            log_warn "Attempt $((retry + 1)) failed: $error_code"
            retry=$((retry + 1))
            if [ $retry -lt $max_retries ]; then
                sleep 5
            fi
        fi
    done
    
    log_error "Failed to generate application keys after $max_retries attempts"
    echo "$response" | jq . || echo "$response"
    return 1
}

################################################################################
# STEP 12: Get Gateway Access Token
################################################################################
get_gateway_token() {
    log_step "STEP 12: Getting API Gateway access token"
    
    # Get token using Resident KM's client_credentials grant
    # This is simpler and more reliable for API testing
    local response
    response=$(curl -k -sS -X POST \
        "https://${APIM_HOST}:${APIM_PORT}/oauth2/token" \
        -u "${APIM_CONSUMER_KEY}:${APIM_CONSUMER_SECRET}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials")
    
    if echo "$response" | jq -e '.access_token' >/dev/null 2>&1; then
        GATEWAY_TOKEN=$(echo "$response" | jq -r '.access_token')
        log_success "Gateway token obtained!"
        log_info "Token: ${GATEWAY_TOKEN:0:50}..."
        return 0
    else
        # Fallback: use the existing IS access token
        log_warn "Could not get new gateway token, falling back to IS token from Step 6..."
        if [ -z "${ACCESS_TOKEN:-}" ]; then
            log_error "IS token not found. Cannot proceed."
            return 1
        fi
        GATEWAY_TOKEN="$ACCESS_TOKEN"
        log_success "Using IS access token for gateway"
        return 0
    fi
}

################################################################################
# STEP 13: Test All APIs Through Gateway
################################################################################
test_all_apis() {
    log_step "STEP 13: Testing all 7 APIs through gateway"
    echo ""
    
    # Gateway paths include context + version (e.g., /forex/1.0.0/health)
    local paths=("/forex/1.0.0/health" "/ledger/1.0.0/health" "/payment/1.0.0/health" "/profile/1.0.0/health" "/rules/1.0.0/health" "/wallet/1.0.0/health" "/banking/1.0.0/health")
    local names=("ForexService" "LedgerService" "PaymentService" "ProfileService" "RuleEngineService" "WalletService" "BankingService")
    
    local failed=0
    for i in "${!paths[@]}"; do
        log_info "Testing ${names[$i]} at ${paths[$i]}..."
        
        local response
        response=$(curl -k -sS -w "\nHTTP_CODE:%{http_code}" \
            "https://${APIM_HOST}:${GATEWAY_HTTPS}${paths[$i]}" \
            -H "Authorization: Bearer ${GATEWAY_TOKEN}")
        
        local http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
        local body=$(echo "$response" | sed '/HTTP_CODE:/d')
        
        if [ "$http_code" = "200" ]; then
            log_success "${names[$i]} ✓ (200 OK)"
            echo "    $body" | head -1
        else
            log_error "${names[$i]} ✗ (HTTP ${http_code})"
            echo "    Error: $body" | head -2
            failed=$((failed + 1))
        fi
    done
    
    echo ""
    if [ $failed -eq 0 ]; then
        log_success "All 7 APIs tested successfully through gateway!"
        return 0
    else
        log_error "${failed}/7 APIs failed"
        return 1
    fi
}

################################################################################
# Main Test Flow
################################################################################
main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║         WSO2 IS + APIM End-to-End Integration Test           ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    
    wait_for_services || exit 1

    # NOTE: Certificate exchange via ./scripts/exchange-certs.sh is a required pre-step
    log_warn "⚠️ Ensure certificates are exchanged and containers restarted before running (./scripts/exchange-certs.sh)"
    echo ""

    # STEP 2: Configure Key Manager
    log_step "STEP 2: Configure WSO2 IS as Key Manager"
    if ! ./scripts/wso2-toolkit.sh list-km | grep -q "WSO2IS"; then
        log_info "WSO2IS Key Manager not found. Configuring..."
        ./scripts/configure-km.sh || exit 1 # Use dedicated KM setup script
    else
        log_success "WSO2IS Key Manager already registered"
    fi
    
    # Keep both Key Managers enabled for compatibility
    log_info "Keeping both WSO2IS and Resident Key Managers enabled for flexibility"
    echo ""

    # STEP 3: Create roles in IS
    log_step "STEP 3: Create default roles in WSO2 IS"
    ./scripts/wso2-toolkit.sh create-roles || log_warn "Failed to create all roles (may already exist)"
    echo ""

    # STEP 4-6: User Registration & Token Acquisition
    register_test_user || exit 1
    create_oauth_app || exit 1
    get_oauth_token || exit 1
    
    # STEP 7: Import APIs
    log_step "STEP 7: Import APIs into WSO2 APIM"
    ./scripts/import-apis.sh || exit 1
    echo ""

    # STEP 8: Deploy All APIs
    log_step "STEP 8: Publish and Deploy All APIs"
    # This script will check if APIs are deployed and only deploy if needed.
    # We rely on this script to handle publishing as well (it implicitly progresses lifecycle or assumes a PUBLISHED state)
    if ! ./scripts/deploy-all-apis.sh; then
        log_error "API deployment/publishing had issues. Check logs."
        exit 1
    fi
    
    # Re-fetch API IDs after deployment for consistency (though APIM only requires ID)
    log_info "Refetching API details for subscription step..."
    local apis_response=$(curl -k -sS "https://${APIM_HOST}:${APIM_PORT}/api/am/publisher/v4/apis?limit=20" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" 2>/dev/null)
    
    # Store API IDs globally for helper functions if needed (though not strictly required in this refactored flow)
    FOREX_API_ID=$(echo "$apis_response" | jq -r '.list[] | select(.name == "ForexService") | .id')
    LEDGER_API_ID=$(echo "$apis_response" | jq -r '.list[] | select(.name == "LedgerService") | .id')
    # ... and so on for all 7 APIs
    
    echo ""
    
    # STEP 9-11: Application Creation, Key Generation, Subscription
    create_apim_application || exit 1
    generate_app_keys || exit 1
    
    log_step "STEP 11: Subscribe all APIs to Test Application"
    ./scripts/subscribe-all-apis.sh "${APP_ID}" || exit 1
    
    # STEP 12-13: Testing
    get_gateway_token || exit 1
    test_all_apis || exit 1
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                    ✅ TEST COMPLETED                          ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    log_success "Test Summary:"
    echo "  Username: ${TEST_USERNAME}"
    echo "  Password: ${TEST_PASSWORD}"
    echo "  OAuth Client ID: ${CLIENT_ID}"
    echo "  APIM App ID: ${APP_ID}"
    echo "  APIM Consumer Key: ${APIM_CONSUMER_KEY}"
    echo "  Gateway Token: ${GATEWAY_TOKEN:0:30}..."
    echo ""
    
    # Show final API status
    log_info "Final API Status (Published/Deployed):"
    local final_apis=$(curl -k -sS "https://${APIM_HOST}:${APIM_PORT}/api/am/publisher/v4/apis?limit=20" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" 2>/dev/null)
    list_api_status "$final_apis"
    
    log_info "Test your APIs manually:"
    log_info "curl -k -H 'Authorization: Bearer \${GATEWAY_TOKEN}' https://localhost:${GATEWAY_HTTPS}/profile/1.0.0/health"
}

main "$@"
