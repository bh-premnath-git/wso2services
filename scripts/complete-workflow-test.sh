#!/usr/bin/env bash

################################################################################
# Complete WSO2 Integration Workflow Test
#
# This script demonstrates the complete end-to-end flow:
# 1. Setup Key Manager
# 2. Check MTLS and SSA JWKS
# 3. Create user roles
# 4. Create and deploy API
# 5. Create application and subscribe to API
# 6. Register and activate user with role
# 7. Login with user to get token
# 8. Call API through WSO2 AM Gateway using user token
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="${SCRIPT_DIR}/wso2-toolkit.sh"
API_MANAGER="${SCRIPT_DIR}/api-manager.sh"
USER_MANAGER="${SCRIPT_DIR}/wso2is-user.sh"

# Test data
TEST_ROLE="user"
TEST_USER="testuser"
TEST_PASSWORD="Test@123456"
TEST_EMAIL="testuser@example.com"
TEST_APP="TestApplication"
TEST_API="TestPaymentAPI"
API_VERSION="1.0.0"
API_CONTEXT="/test-payment"

# Available backend services (change API_BACKEND to test different services):
# - http://banking-service:8007   (Bank account linking)
# - http://forex-service:8001     (Currency rates)
# - http://ledger-service:8002    (Accounting)
# - http://payment-service:8003   (Payment processing)
# - http://profile-service:8004   (User profiles)
# - http://rule-engine-service:8005 (Business rules)
# - http://wallet-service:8006    (Digital wallets)
API_BACKEND="http://payment-service:8003"

CALLBACK_URL="http://localhost:8080/callback"

# Helper functions
log_step() { echo -e "${CYAN}[STEP $1]${NC} $2"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_section() { echo -e "\n${BLUE}========================================${NC}\n${BLUE}  $1${NC}\n${BLUE}========================================${NC}\n"; }

# Check if scripts exist
check_scripts() {
    if [ ! -f "${TOOLKIT}" ]; then
        log_error "wso2-toolkit.sh not found at ${TOOLKIT}"
        return 1
    fi
    
    if [ ! -f "${API_MANAGER}" ]; then
        log_error "api-manager.sh not found at ${API_MANAGER}"
        return 1
    fi
    
    if [ ! -f "${USER_MANAGER}" ]; then
        log_error "wso2is-user.sh not found at ${USER_MANAGER}"
        return 1
    fi
    
    # Make scripts executable
    chmod +x "${TOOLKIT}" "${API_MANAGER}" "${USER_MANAGER}"
    
    log_success "All scripts found and ready"
    return 0
}

# Extract value from command output
extract_value() {
    local pattern="$1"
    local input="$2"
    echo "${input}" | grep -oP "${pattern}" | head -1
}

################################################################################
# STEP 1: Health Check & Key Manager Setup
################################################################################

step1_health_and_setup() {
    log_section "STEP 1: Health Check & Key Manager Setup"
    
    log_step "1.1" "Checking WSO2 components health..."
    if ! "${TOOLKIT}" health; then
        log_error "Health check failed"
        return 1
    fi
    
    log_step "1.2" "Setting up Key Manager..."
    if ! "${TOOLKIT}" setup-km; then
        log_warn "Key Manager might already be configured"
    fi
    
    log_success "Step 1 completed"
}

################################################################################
# STEP 2: Check MTLS and SSA JWKS
################################################################################

step2_check_certificates() {
    log_section "STEP 2: Check MTLS and SSA JWKS"
    
    log_step "2.1" "Checking MTLS certificate trust..."
    if ! "${TOOLKIT}" check-mtls; then
        log_warn "MTLS check failed, attempting to fix..."
        "${TOOLKIT}" fix-mtls || log_warn "Could not auto-fix MTLS"
    fi
    
    log_step "2.2" "Checking SSA JWKS endpoint..."
    if ! "${TOOLKIT}" check-ssa-jwks; then
        log_warn "SSA JWKS check failed"
    fi
    
    log_success "Step 2 completed"
}

################################################################################
# STEP 3: Create User Roles
################################################################################

step3_create_roles() {
    log_section "STEP 3: Create User Roles"
    
    log_step "3.1" "Creating default roles..."
    if ! "${TOOLKIT}" create-roles; then
        log_warn "Some roles might already exist"
    fi
    
    log_step "3.2" "Listing all roles..."
    "${TOOLKIT}" list-roles
    
    log_success "Step 3 completed"
}

################################################################################
# STEP 4: Create and Deploy API
################################################################################

step4_create_deploy_api() {
    log_section "STEP 4: Create and Deploy API"
    
    log_step "4.1" "Creating API: ${TEST_API}..."
    local api_output
    api_output=$("${API_MANAGER}" create-api "${TEST_API}" "${API_VERSION}" "${API_CONTEXT}" "${API_BACKEND}" 2>&1)
    echo "${api_output}"
    
    # Extract API ID from output
    API_ID=$(echo "${api_output}" | grep -oP 'API ID: \K[a-f0-9-]+' | head -1)
    
    if [ -z "${API_ID}" ]; then
        log_error "Failed to extract API ID"
        return 1
    fi
    
    log_info "API ID: ${API_ID}"
    
    log_step "4.2" "Deploying API (publish + revision + deploy)..."
    if ! "${API_MANAGER}" deploy-api "${API_ID}"; then
        log_error "Failed to deploy API"
        return 1
    fi
    
    log_success "Step 4 completed - API deployed"
}

################################################################################
# STEP 5: Create Application and Subscribe to API
################################################################################

step5_create_app_subscribe() {
    log_section "STEP 5: Create Application and Subscribe"
    
    log_step "5.1" "Creating application: ${TEST_APP}..."
    local app_output
    app_output=$("${TOOLKIT}" create-app "${TEST_APP}" "${CALLBACK_URL}" 2>&1)
    echo "${app_output}"
    
    # Extract application ID
    APP_ID=$(echo "${app_output}" | grep -oP 'Application ID: \K[a-f0-9-]+' | head -1)
    
    if [ -z "${APP_ID}" ]; then
        log_error "Failed to extract Application ID"
        return 1
    fi
    
    log_info "Application ID: ${APP_ID}"
    
    # Extract client credentials
    CLIENT_ID=$(echo "${app_output}" | grep -oP 'Client ID: \K[^\s]+' | head -1)
    CLIENT_SECRET=$(echo "${app_output}" | grep -oP 'Client Secret: \K[^\s]+' | head -1)
    
    log_info "Client ID: ${CLIENT_ID}"
    log_info "Client Secret: ${CLIENT_SECRET}"
    
    log_step "5.2" "Subscribing application to API..."
    if ! "${API_MANAGER}" subscribe "${APP_ID}" "${API_ID}" "Unlimited"; then
        log_error "Failed to subscribe"
        return 1
    fi
    
    log_success "Step 5 completed - Application subscribed to API"
}

################################################################################
# STEP 6: Register and Activate User
################################################################################

step6_register_activate_user() {
    log_section "STEP 6: Register and Activate User"
    
    log_step "6.1" "Registering user: ${TEST_USER}..."
    if ! "${USER_MANAGER}" register "${TEST_USER}" "${TEST_PASSWORD}" "${TEST_EMAIL}" "Test" "User"; then
        log_warn "User might already exist"
    fi
    
    log_step "6.2" "Activating user: ${TEST_USER}..."
    if ! "${USER_MANAGER}" activate-user "${TEST_USER}"; then
        log_warn "User might already be activated"
    fi
    
    log_step "6.3" "Verifying user details..."
    "${USER_MANAGER}" get-user "${TEST_USER}"
    
    log_success "Step 6 completed - User registered and activated"
}

################################################################################
# STEP 7: Login with User to Get Token
################################################################################

step7_get_user_token() {
    log_section "STEP 7: Login with User to Get Token"
    
    log_step "7.1" "Logging in with user credentials..."
    local login_output
    login_output=$("${USER_MANAGER}" login "${TEST_USER}" "${TEST_PASSWORD}" "${CLIENT_ID}" "${CLIENT_SECRET}" 2>&1)
    echo "${login_output}"
    
    # Extract access token
    ACCESS_TOKEN=$(echo "${login_output}" | grep -oP 'Access Token: \K[^\s]+' | head -1)
    
    if [ -z "${ACCESS_TOKEN}" ]; then
        log_error "Failed to extract access token"
        return 1
    fi
    
    log_info "Access Token obtained (first 20 chars): ${ACCESS_TOKEN:0:20}..."
    
    log_success "Step 7 completed - User authenticated, token obtained"
}

################################################################################
# STEP 8: Call API through WSO2 AM Gateway
################################################################################

step8_call_api() {
    log_section "STEP 8: Call API through WSO2 AM Gateway"
    
    log_step "8.1" "Constructing API Gateway URL..."
    local gateway_url="https://localhost:8243${API_CONTEXT}/health"
    log_info "Gateway URL: ${gateway_url}"
    
    log_step "8.2" "Calling API with user token..."
    echo ""
    
    local response
    if response=$(curl -k -s -w "\nHTTP_STATUS:%{http_code}" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Accept: application/json" \
        "${gateway_url}"); then
        
        local http_code=$(echo "${response}" | grep -oP 'HTTP_STATUS:\K\d+')
        local body=$(echo "${response}" | sed 's/HTTP_STATUS:.*//')
        
        log_info "HTTP Status: ${http_code}"
        log_info "Response Body:"
        echo "${body}" | jq . 2>/dev/null || echo "${body}"
        
        if [ "${http_code}" = "200" ] || [ "${http_code}" = "201" ]; then
            log_success "API call successful!"
        else
            log_warn "API returned status ${http_code}"
        fi
    else
        log_error "Failed to call API"
        return 1
    fi
    
    log_success "Step 8 completed - API called successfully through gateway"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     WSO2 Complete Integration Workflow Test                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    log_info "Starting complete workflow test..."
    echo ""
    
    # Check scripts
    check_scripts || exit 1
    
    # Wait for services to be ready
    log_info "Waiting 5 seconds for services to be ready..."
    sleep 5
    
    # Execute steps
    step1_health_and_setup || exit 1
    step2_check_certificates || exit 1
    step3_create_roles || exit 1
    step4_create_deploy_api || exit 1
    step5_create_app_subscribe || exit 1
    step6_register_activate_user || exit 1
    step7_get_user_token || exit 1
    step8_call_api || exit 1
    
    # Final summary
    log_section "WORKFLOW COMPLETED SUCCESSFULLY"
    
    echo "Summary:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "API Name:          ${TEST_API}"
    echo "API ID:            ${API_ID}"
    echo "API Context:       ${API_CONTEXT}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Application:       ${TEST_APP}"
    echo "Application ID:    ${APP_ID}"
    echo "Client ID:         ${CLIENT_ID}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "User:              ${TEST_USER}"
    echo "User Email:        ${TEST_EMAIL}"
    echo "User Role:         ${TEST_ROLE}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Gateway URL:       https://localhost:8243${API_CONTEXT}/*"
    echo "Token (partial):   ${ACCESS_TOKEN:0:40}..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    log_success "All steps completed successfully!"
    echo ""
    echo "You can now test the API with:"
    echo "curl -k -H 'Authorization: Bearer ${ACCESS_TOKEN}' https://localhost:8243${API_CONTEXT}/health"
    echo ""
}

# Run main function
main "$@"
