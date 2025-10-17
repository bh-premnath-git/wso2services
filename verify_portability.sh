#!/usr/bin/env bash

################################################################################
# Portability Verification Script
#
# Verifies all portable configuration is in place and ready to work on any system
################################################################################

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Portability Verification                                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

CHECKS_PASSED=0
CHECKS_FAILED=0

# Check 1: WSO2 IS deployment.toml has password grant config
log_info "Checking WSO2 IS configuration..."
if grep -q "\[oauth.grant_type.password\]" wso2is/conf/deployment.toml && \
   grep -q "enable = true" wso2is/conf/deployment.toml; then
    log_success "Password grant configuration present in deployment.toml"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    log_error "Password grant configuration missing!"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

# Check 2: Auth module has password reset
log_info "Checking auth module..."
if [ -f "app_services/common/auth/wso2_client.py" ]; then
    if grep -q "reset_password" app_services/common/auth/wso2_client.py; then
        log_success "Auth module has reset_password method"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_warning "reset_password method not found in auth module"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
else
    log_error "Auth module not found!"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

# Check 3: Profile service has endpoints
log_info "Checking profile service endpoints..."
if [ -f "app_services/profile_service/app/main.py" ]; then
    HAS_REGISTER=$(grep -c "@app.post(\"/register\"" app_services/profile_service/app/main.py || true)
    HAS_LOGIN=$(grep -c "@app.post(\"/auth/login\"" app_services/profile_service/app/main.py || true)
    HAS_RESET=$(grep -c "@app.post(\"/auth/reset-password\"" app_services/profile_service/app/main.py || true)
    
    if [ "$HAS_REGISTER" -gt 0 ] && [ "$HAS_LOGIN" -gt 0 ] && [ "$HAS_RESET" -gt 0 ]; then
        log_success "Profile service has all auth endpoints (register, login, reset-password)"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_warning "Some endpoints missing: register=$HAS_REGISTER, login=$HAS_LOGIN, reset=$HAS_RESET"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
else
    log_error "Profile service not found!"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

# Check 4: Scripts are executable
log_info "Checking setup scripts..."
REQUIRED_SCRIPTS=(
    "complete_startup.sh"
    "app_scripts/register_test_users.sh"
    "app_scripts/reset_test_user_passwords.sh"
    "app_scripts/register_apis.sh"
)

SCRIPTS_OK=true
for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ -f "$script" ] && [ -x "$script" ]; then
        :  # Script exists and is executable
    else
        log_warning "$script not found or not executable"
        SCRIPTS_OK=false
    fi
done

if $SCRIPTS_OK; then
    log_success "All required scripts present and executable"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    log_error "Some scripts missing or not executable"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

# Check 5: Docker compose file exists
log_info "Checking Docker configuration..."
if [ -f "docker-compose.yml" ]; then
    if grep -q "profile-service:" docker-compose.yml && \
       grep -q "wso2is:" docker-compose.yml && \
       grep -q "wso2am:" docker-compose.yml; then
        log_success "Docker Compose configuration complete"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_error "Docker Compose missing required services"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
else
    log_error "docker-compose.yml not found!"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

# Check 6: Dockerfile for profile service includes common
log_info "Checking profile service Dockerfile..."
if [ -f "app_services/profile_service/Dockerfile" ]; then
    if grep -q "COPY ./common" app_services/profile_service/Dockerfile; then
        log_success "Profile service Dockerfile includes common auth module"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_warning "Dockerfile may not copy common auth module"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
else
    log_error "Profile service Dockerfile not found!"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

# Check 7: .gitignore has runtime files
log_info "Checking .gitignore..."
if [ -f ".gitignore" ]; then
    if grep -q "oauth_credentials" .gitignore; then
        log_success ".gitignore properly excludes runtime credentials"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_warning ".oauth_credentials not in .gitignore - credentials may be committed!"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
else
    log_warning ".gitignore not found"
fi

# Summary
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Verification Summary                                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  ✅ Passed: $CHECKS_PASSED"
echo "  ❌ Failed: $CHECKS_FAILED"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    log_success "All portability checks passed!"
    echo ""
    echo "This codebase is ready to be ported to another system."
    echo ""
    echo "To deploy on a new system:"
    echo "  1. Copy this directory (or git clone)"
    echo "  2. Run: ./complete_startup.sh"
    echo "  3. Done!"
    echo ""
    exit 0
else
    log_error "Some checks failed - review warnings above"
    echo ""
    echo "Fix the issues before porting to ensure everything works."
    echo ""
    exit 1
fi
