#!/usr/bin/env bash

################################################################################
# WSO2 Complete Startup - Master Script
#
# This script performs a complete fresh setup:
# 1. Stops all containers
# 2. Removes volumes (clean slate)
# 3. Starts containers
# 4. Waits for services to be ready
# 5. Runs all setup scripts in order
#
# Usage: ./complete_startup.sh
################################################################################

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_step() { 
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_header() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  WSO2 Complete Startup - Fresh Installation               ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

wait_for_container() {
    local container=$1
    local max_attempts=120
    local attempt=0
    
    log_info "Waiting for container '$container' to be healthy..."
    
    while [ $attempt -lt $max_attempts ]; do
        local status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "not_found")
        local health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no_health{{end}}' "$container" 2>/dev/null || echo "no_health")
        
        if [ "$status" = "running" ]; then
            if [ "$health" = "healthy" ]; then
                log_success "Container '$container' is healthy!"
                return 0
            elif [ "$health" = "no_health" ]; then
                # Container has no health check, verify it's running
                log_success "Container '$container' is running!"
                return 0
            fi
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 5
    done
    
    echo ""
    log_error "Container '$container' failed to become healthy after $((max_attempts * 5)) seconds"
    log_error "Status: $status, Health: $health"
    return 1
}

wait_for_service_url() {
    local service=$1
    local url=$2
    local max_attempts=60
    local attempt=0
    
    log_info "Waiting for $service to respond at $url..."
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -sk --connect-timeout 5 --max-time 10 "$url" >/dev/null 2>&1; then
            log_success "$service is responding!"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 5
    done
    
    echo ""
    log_error "$service failed to respond after $((max_attempts * 5)) seconds"
    return 1
}

show_container_status() {
    echo ""
    log_info "Container Status:"
    docker compose ps
    echo ""
}

print_header

# Confirmation prompt
log_warning "This will:"
echo "  • Stop all WSO2 containers"
echo "  • Remove all volumes (DELETES ALL DATA)"
echo "  • Start fresh containers"
echo "  • Run complete setup"
echo ""
read -p "Continue? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log_info "Aborted by user"
    exit 0
fi

# Step 0: Stop and clean containers
log_step "STEP 0/9: Stopping containers and cleaning volumes"

log_info "Stopping all containers..."
docker compose down

log_success "Containers stopped"

log_info "Removing volumes..."
docker compose down -v

log_success "Volumes removed"
echo ""

# Step 1: Start containers
log_step "STEP 1/9: Starting containers"

log_info "Starting PostgreSQL..."
docker compose up -d postgres
echo ""

# Wait for PostgreSQL
wait_for_container "postgres-wso2" || wait_for_container "postgres" || exit 1
echo ""

log_info "Starting infrastructure services (Redis, DynamoDB, Redpanda, Jaeger, OTel)..."
docker compose up -d redis dynamodb-local redpanda jaeger otel-collector
echo ""

# Wait for key infrastructure
log_info "Waiting for infrastructure services to be ready..."
wait_for_container "redis" || exit 1
wait_for_container "dynamodb-local" || exit 1
wait_for_container "redpanda" || exit 1
echo ""

log_info "Starting WSO2 services..."
docker compose up -d wso2is wso2am

log_success "Containers started"
show_container_status

# Step 2: Wait for services
log_step "STEP 2/9: Waiting for services to be ready"

log_info "This may take 5-15 minutes for first startup..."
log_info "PostgreSQL + Infrastructure + WSO2 + 6 Microservices"
log_info "All services need time to initialize and become healthy"
echo ""

# Wait for WSO2 IS container
wait_for_container "wso2is" || exit 1
echo ""

# Wait for WSO2 AM container  
wait_for_container "wso2am" || exit 1
echo ""

log_info "Starting microservices..."
docker compose up -d forex-service ledger-service payment-service profile-service rule-engine-service wallet-service
echo ""

log_info "Waiting for microservices to be ready..."
wait_for_container "forex-service" || exit 1
wait_for_container "ledger-service" || exit 1
wait_for_container "payment-service" || exit 1
wait_for_container "profile-service" || exit 1
wait_for_container "rule-engine-service" || exit 1
wait_for_container "wallet-service" || exit 1
echo ""

# Now verify services are actually responding
log_info "Verifying service endpoints..."
echo ""

wait_for_service_url "WSO2 IS Carbon Console" "https://localhost:9444/carbon/admin/login.jsp" || exit 1
echo ""

wait_for_service_url "WSO2 AM Carbon Console" "https://localhost:9443/carbon/admin/login.jsp" || exit 1
echo ""

# Critical: Wait for WSO2 IS APIs to be fully functional
log_info "Waiting for WSO2 IS APIs to be fully ready..."
wait_for_service_url "WSO2 IS SCIM2 API" "https://localhost:9444/scim2/Users" || exit 1
echo ""

wait_for_service_url "WSO2 IS DCR API" "https://localhost:9444/api/identity/oauth2/dcr/v1.1/applications" || exit 1
echo ""

# Critical: Wait for WSO2 AM REST APIs to be fully functional
log_info "Waiting for WSO2 AM REST APIs to be fully ready..."
wait_for_service_url "WSO2 AM Publisher API" "https://localhost:9443/api/am/publisher/v4/apis" || exit 1
echo ""

wait_for_service_url "WSO2 AM DevPortal API" "https://localhost:9443/api/am/devportal/v3/apis" || exit 1
echo ""

wait_for_service_url "WSO2 AM Admin API" "https://localhost:9443/api/am/admin/v4/key-managers" || exit 1
echo ""

# Extra wait for WSO2 services to be fully stable
log_info "Waiting additional 30 seconds for WSO2 services to stabilize..."
sleep 30

log_success "All services are ready and responding!"
echo ""

# Step 3: Fix consent tables
log_step "STEP 3/9: Fixing consent management tables"

if [ -f "app_scripts/fix_consent_tables.sh" ]; then
    ./app_scripts/fix_consent_tables.sh
    if [ $? -ne 0 ]; then
        log_error "Failed to fix consent tables"
        exit 1
    fi
else
    log_error "fix_consent_tables.sh not found"
    exit 1
fi

# Step 4: Fix SSL certificates
log_step "STEP 4/9: Configuring SSL certificates"

if [ -f "app_scripts/fix_ssl_certificates.sh" ]; then
    ./app_scripts/fix_ssl_certificates.sh
    if [ $? -ne 0 ]; then
        log_error "Failed to fix SSL certificates"
        exit 1
    fi
else
    log_error "fix_ssl_certificates.sh not found"
    exit 1
fi

# Step 5: Setup Key Manager
log_step "STEP 5/9: Setting up WSO2 IS as Key Manager"

if [ -f "app_scripts/setup_wso2is_keymanager.sh" ]; then
    # Auto-confirm if key manager exists (but CATCH FAILURES!)
    if ! echo "y" | ./app_scripts/setup_wso2is_keymanager.sh; then
        log_error "Key Manager setup failed!"
        exit 1
    fi
    
    # Wait for Key Manager to be fully synced and ready
    log_info "Waiting 30 seconds for Key Manager to sync with APIM..."
    sleep 30
    
    # Verify Key Manager is properly configured with endpoints
    log_info "Verifying Key Manager configuration..."
    
    KM_ID=$(curl -sk -u "admin:admin" \
        "https://localhost:9443/api/am/admin/v4/key-managers" 2>/dev/null | \
        jq -r '.list[] | select(.name=="WSO2-IS-KeyManager") | .id' || echo "")
    
    if [ -z "$KM_ID" ]; then
        log_error "WSO2-IS-KeyManager not found!"
        exit 1
    fi
    
    # Verify endpoints are configured (not null)
    TOKEN_EP=$(curl -sk -u "admin:admin" \
        "https://localhost:9443/api/am/admin/v4/key-managers/${KM_ID}" 2>/dev/null | \
        jq -r '.tokenEndpoint // empty')
    
    if [ -z "$TOKEN_EP" ] || [ "$TOKEN_EP" = "null" ]; then
        log_error "Key Manager endpoints not configured properly!"
        log_error "Token endpoint is: $TOKEN_EP"
        echo ""
        echo "Run manually to debug:"
        echo "  ./app_scripts/setup_wso2is_keymanager.sh"
        exit 1
    fi
    
    log_success "Key Manager is properly configured"
    log_info "Token endpoint: $TOKEN_EP"
else
    log_error "setup_wso2is_keymanager.sh not found"
    exit 1
fi

# Step 6: Create roles in WSO2 IS
log_step "STEP 6/9: Creating roles in WSO2 IS"

if [ -f "app_scripts/setup_roles_only.sh" ]; then
    ./app_scripts/setup_roles_only.sh
    if [ $? -ne 0 ]; then
        log_error "Failed to setup roles"
        exit 1
    fi
else
    log_error "setup_roles_only.sh not found"
    exit 1
fi

# Step 7: Register APIs
log_step "STEP 7/9: Registering APIs in WSO2 AM"

if [ -f "app_scripts/register_apis.sh" ]; then
    ./app_scripts/register_apis.sh
    if [ $? -ne 0 ]; then
        log_error "Failed to register APIs"
        exit 1
    fi
else
    log_error "register_apis.sh not found"
    exit 1
fi

# Step 8: Deploy APIs
log_step "STEP 8/10: Deploying APIs to Gateway"

if [ -f "app_scripts/deploy_apis_to_gateway.sh" ]; then
    ./app_scripts/deploy_apis_to_gateway.sh
    if [ $? -ne 0 ]; then
        log_error "Failed to deploy APIs"
        exit 1
    fi
else
    log_error "deploy_apis_to_gateway.sh not found"
    exit 1
fi

# Step 9: Register test users via Registration API
log_step "STEP 9/11: Registering test users via Registration API"

if [ -f "app_scripts/register_test_users.sh" ]; then
    ./app_scripts/register_test_users.sh
    if [ $? -ne 0 ]; then
        log_warning "Some test users failed to register (may already exist)"
        # Don't fail - users might already exist
    fi
else
    log_warning "register_test_users.sh not found - skipping test user registration"
fi

# Step 10: Reset test user passwords (ensures password grant works)
log_step "STEP 10/11: Resetting test user passwords for OAuth"

if [ -f "app_scripts/reset_test_user_passwords.sh" ]; then
    ./app_scripts/reset_test_user_passwords.sh
    if [ $? -ne 0 ]; then
        log_warning "Password reset had some failures"
    fi
else
    log_warning "reset_test_user_passwords.sh not found - passwords may not work"
fi

# Step 11: Test integration
log_step "STEP 11/11: Testing WSO2 IS integration"

if [ -f "app_scripts/test_wso2is_integration.sh" ]; then
    # Run test in non-interactive mode
    echo "n" | ./app_scripts/test_wso2is_integration.sh
    TEST_RESULT=$?
else
    log_error "test_wso2is_integration.sh not found"
    exit 1
fi

# Final summary
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Complete Startup Finished                                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

if [ $TEST_RESULT -eq 0 ]; then
    log_success "All steps completed successfully!"
    echo ""
    echo "✅ What was configured:"
    echo "   • PostgreSQL database with clean schema"
    echo "   • Infrastructure: Redis, DynamoDB, Redpanda (Kafka), Jaeger, OTel"
    echo "   • 6 microservices: forex, ledger, payment, profile, rule-engine, wallet"
    echo "   • WSO2 IS with roles (ops_users, finance, auditor, user, app_admin)"
    echo "   • 5 test users registered via Registration API (ops_user, finance, auditor, user, app_admin)"
    echo "   • WSO2 AM with WSO2-IS-KeyManager"
    echo "   • 6 microservice APIs registered and deployed to gateway"
    echo "   • OAuth credentials generated (.oauth_credentials file)"
    echo "   • SSL certificates configured"
    echo "   • User registration API with JWT authentication"
    echo "   • Integration tested and verified"
    echo ""
    echo "🌐 Access URLs:"
    echo "   WSO2 Services:"
    echo "   • WSO2 AM Publisher:  https://localhost:9443/publisher"
    echo "   • WSO2 AM DevPortal:  https://localhost:9443/devportal"
    echo "   • WSO2 AM Admin:      https://localhost:9443/admin"
    echo "   • WSO2 IS Console:    https://localhost:9444/console"
    echo "   • API Gateway:        https://localhost:8243"
    echo ""
    echo "   Microservices (Direct Access):"
    echo "   • Forex Service:      http://localhost:8001/health"
    echo "   • Ledger Service:     http://localhost:8002/health"
    echo "   • Payment Service:    http://localhost:8003/health"
    echo "   • Profile Service:    http://localhost:8004/health"
    echo "   • Rule Engine:        http://localhost:8005/health"
    echo "   • Wallet Service:     http://localhost:8006/health"
    echo ""
    echo "   Monitoring & Infrastructure:"
    echo "   • Jaeger UI:          http://localhost:16686"
    echo "   • Redpanda Console:   http://localhost:9644"
    echo "   • Redis:              localhost:6379"
    echo "   • DynamoDB Local:     http://localhost:8000"
    echo ""
    echo "🔑 Credentials:"
    echo "   • WSO2 Admin:         admin / admin"
    echo "   • OAuth Credentials:  .oauth_credentials file"
    echo "   • Test Users:         See app_scripts/register_test_users.sh"
    echo "   • Integration Status: /tmp/wso2is_integration_success.txt"
    echo ""
    echo "📝 Next Steps:"
    echo "   • Test all APIs:          ./test_all_users_apis.sh"
    echo "   • List registered users:  ./list_users_simple.sh"
    echo "   • Register new user:      curl -X POST http://localhost:8004/register -d '{...}'"
    echo "   • View documentation:     cat USER_REGISTRATION_GUIDE.md"
    echo ""
    echo "🎯 User Registration API:"
    echo "   • Register:  POST   http://localhost:8004/register"
    echo "   • Login:     POST   http://localhost:8004/auth/login"
    echo "   • UserInfo:  GET    http://localhost:8004/auth/userinfo"
    echo "   • Refresh:   POST   http://localhost:8004/auth/refresh"
    echo ""
    
    # Optional: Create password grant app
    read -p "Create dedicated password grant OAuth app? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ -f "app_scripts/create_working_password_grant_app.sh" ]; then
            ./app_scripts/create_working_password_grant_app.sh
        fi
    fi
    
    exit 0
else
    log_error "Integration test failed"
    echo ""
    show_container_status
    echo "⚠️  What to check:"
    echo "   1. Check logs: docker compose logs wso2am | tail -100"
    echo "   2. Check logs: docker compose logs wso2is | tail -100"
    echo "   3. Check logs: docker compose logs mysql | tail -50"
    echo "   4. Run validation: ./app_scripts/check_keymanager.sh"
    echo "   5. View full logs: docker compose logs --tail=200"
    echo ""
    exit 1
fi
