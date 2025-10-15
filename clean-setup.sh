#!/bin/bash

################################################################################
# WSO2 Services - Complete Clean Setup
#
# This script performs a clean installation from scratch:
# 1. Stops all containers and removes volumes
# 2. Starts all services fresh
# 3. Waits for services to be healthy
# 4. Configures Key Manager
# 5. Creates users and roles
# 6. Validates setup
#
# Usage: ./clean-setup.sh
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  WSO2 Services - Complete Clean Setup                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Clean shutdown
log_info "Step 1/6: Stopping all containers and removing volumes..."
docker compose down -v
log_success "All containers stopped and volumes removed"
echo ""

# Step 2: Start services
log_info "Step 2/6: Starting all services..."
docker compose up -d
log_success "All services started"
echo ""

# Step 3: Wait for services
log_info "Step 3/6: Waiting for services to be healthy..."
log_info "This may take 2-3 minutes..."

# Wait for PostgreSQL
log_info "Waiting for PostgreSQL..."
for i in {1..60}; do
    if docker compose exec -T postgres pg_isready -U wso2carbon >/dev/null 2>&1; then
        log_success "PostgreSQL is ready"
        break
    fi
    if [ $i -eq 60 ]; then
        log_error "PostgreSQL failed to start"
        exit 1
    fi
    sleep 2
done

# Wait for WSO2 IS
log_info "Waiting for WSO2 Identity Server..."
for i in {1..90}; do
    if curl -sk https://localhost:9444/carbon/ -o /dev/null -w "%{http_code}" 2>/dev/null | grep -q "302\|200"; then
        log_success "WSO2 IS is ready"
        break
    fi
    if [ $i -eq 90 ]; then
        log_error "WSO2 IS failed to start"
        exit 1
    fi
    sleep 2
done

# Wait for WSO2 AM
log_info "Waiting for WSO2 API Manager..."
for i in {1..90}; do
    if curl -sk https://localhost:9443/carbon/ -o /dev/null -w "%{http_code}" 2>/dev/null | grep -q "302\|200"; then
        log_success "WSO2 AM is ready"
        break
    fi
    if [ $i -eq 90 ]; then
        log_error "WSO2 AM failed to start"
        exit 1
    fi
    sleep 2
done

log_success "All services are healthy"
echo ""

# Step 4: Configure Key Manager
log_info "Step 4/6: Configuring WSO2 IS as Key Manager..."
if ./app_scripts/configure_keymanager.sh; then
    log_success "Key Manager configured"
else
    log_error "Key Manager configuration failed"
    exit 1
fi
echo ""

# Step 5: Create users and roles
log_info "Step 5/6: Creating users and roles..."
if ./app_scripts/setup_is_users_roles.sh; then
    log_success "Users and roles created"
else
    log_error "User/role creation failed"
    exit 1
fi
echo ""

# Step 6: Validate setup
log_info "Step 6/6: Validating complete setup..."
if ./app_scripts/check_keymanager.sh; then
    log_success "Validation passed"
else
    log_warning "Some validation tests failed"
fi
echo ""

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Setup Complete!                                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
log_success "WSO2 Services are ready to use"
echo ""
echo "Services:"
echo "  • WSO2 Identity Server: https://localhost:9444/console"
echo "  • WSO2 API Manager:     https://localhost:9443/devportal"
echo "  • PostgreSQL:           localhost:5432"
echo "  • Microservices:        ports 8001-8006"
echo ""
echo "Credentials:"
echo "  • Admin user:           admin / admin"
echo "  • Test users:           See app_scripts/setup_is_users_roles.sh"
echo ""
echo "View logs:"
echo "  docker compose logs -f wso2is"
echo "  docker compose logs -f wso2am"
echo ""
