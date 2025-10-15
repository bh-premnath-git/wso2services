#!/usr/bin/env bash

################################################################################
# WSO2 Complete Setup - Master Script
#
# Runs all setup steps in correct order:
# 1. Create users in WSO2 IS
# 2. Fix SSL certificates
# 3. Register APIs in WSO2 AM
# 4. Deploy APIs to Gateway
# 5. Register WSO2-IS as Key Manager
# 6. Test integration
#
# Usage: ./complete_setup.sh
################################################################################

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}\n${GREEN}$1${NC}\n${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"; }

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  WSO2 Complete Setup                                       ║"
echo "║  Sets up WSO2 IS + WSO2 AM Integration                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check if containers are running
log_info "Checking containers..."
if ! docker compose ps wso2is | grep -q "Up"; then
  log_error "WSO2 IS container not running"
  echo "Run: docker compose up -d"
  exit 1
fi

if ! docker compose ps wso2am | grep -q "Up"; then
  log_error "WSO2 AM container not running"
  echo "Run: docker compose up -d"
  exit 1
fi

log_success "All containers running"
echo ""

# Step 1: Setup WSO2 IS users and roles
log_step "STEP 1/6: Setting up WSO2 IS users and roles"

if [ -f "app_scripts/setup_is_users_roles.sh" ]; then
  ./app_scripts/setup_is_users_roles.sh
  if [ $? -ne 0 ]; then
    log_error "Failed to setup IS users"
    exit 1
  fi
else
  log_error "setup_is_users_roles.sh not found"
  exit 1
fi

# Step 2: Fix SSL certificates
log_step "STEP 2/6: Fixing SSL certificates (WSO2 AM ↔ WSO2 IS)"

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

# Step 3: Register APIs
log_step "STEP 3/6: Registering APIs in WSO2 AM"

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

# Step 4: Deploy APIs to Gateway
log_step "STEP 4/6: Deploying APIs to Gateway"

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

# Step 5: Register WSO2-IS-KeyManager
log_step "STEP 5/6: Registering WSO2 IS as Key Manager"

if [ -f "app_scripts/register_wso2is_keymanager.sh" ]; then
  ./app_scripts/register_wso2is_keymanager.sh || true
  # Don't exit on error, as it might already exist
else
  log_error "register_wso2is_keymanager.sh not found"
  exit 1
fi

# Step 6: Test integration
log_step "STEP 6/6: Testing WSO2 IS integration"

if [ -f "app_scripts/test_wso2is_integration.sh" ]; then
  ./app_scripts/test_wso2is_integration.sh
  TEST_RESULT=$?
else
  log_error "test_wso2is_integration.sh not found"
  exit 1
fi

# Final summary
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Setup Complete                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

if [ $TEST_RESULT -eq 0 ]; then
  log_success "All steps completed successfully!"
  echo ""
  echo "What was configured:"
  echo "  ✅ WSO2 IS users: ops_user, finance, auditor, user, app_admin"
  echo "  ✅ SSL certificates: AM ↔ IS trust established"
  echo "  ✅ APIs registered: 6 microservices"
  echo "  ✅ APIs deployed: All with revisions"
  echo "  ✅ Key Manager: WSO2-IS-KeyManager configured"
  echo "  ✅ Integration: Tested and working"
  echo ""
  echo "Next steps:"
  echo "  • Check credentials: /tmp/wso2is_integration_success.txt"
  echo "  • DevPortal: https://localhost:9443/devportal"
  echo "  • Admin Portal: https://localhost:9443/admin"
  echo "  • IS Console: https://localhost:9444/console"
  echo ""
else
  log_error "Integration test failed"
  echo ""
  echo "What to check:"
  echo "  1. Run diagnostic: ./app_scripts/diagnose_and_fix_keymanager.sh"
  echo "  2. Check AM logs: docker compose logs wso2am | tail -100"
  echo "  3. Check IS logs: docker compose logs wso2is | tail -100"
  echo ""
  exit 1
fi
