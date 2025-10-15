#!/bin/bash

################################################################################
# Apply Consent Management Schema to WSO2 Identity Server Database
#
# Purpose: Add missing CM_* tables to identity_db for OAuth DCR support
# Usage: ./apply-consent-schema.sh
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  WSO2 Identity Server - Consent Management Schema Setup   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check if postgres container is running
if ! docker compose ps postgres | grep -q "Up"; then
    echo -e "${RED}[ERROR]${NC} PostgreSQL container is not running"
    echo "Start it with: docker compose up -d postgres"
    exit 1
fi

echo -e "${BLUE}[INFO]${NC} Checking for existing consent management tables..."

# Check if tables already exist
EXISTING_TABLES=$(docker compose exec -T postgres psql -U wso2carbon -d identity_db -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name LIKE 'cm_%';" 2>/dev/null | xargs)

if [ "$EXISTING_TABLES" = "10" ]; then
    echo -e "${GREEN}[SUCCESS]${NC} Consent management tables already exist (10 tables found)"
    echo ""
    echo "Tables:"
    docker compose exec -T postgres psql -U wso2carbon -d identity_db -c "\dt cm_*"
    exit 0
elif [ "$EXISTING_TABLES" -gt "0" ]; then
    echo -e "${YELLOW}[WARNING]${NC} Found $EXISTING_TABLES consent tables (expected 10)"
    echo -e "${YELLOW}[WARNING]${NC} Schema may be partially installed"
    read -p "Continue with installation? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo -e "${BLUE}[INFO]${NC} Applying consent management schema..."

# Apply the schema
if docker compose exec -T postgres psql -U wso2carbon -d identity_db < conf/postgres/scripts/06-identity-consent-mgmt-schema.sql > /dev/null 2>&1; then
    echo -e "${GREEN}[SUCCESS]${NC} Consent management schema applied successfully"
else
    echo -e "${RED}[ERROR]${NC} Failed to apply schema"
    exit 1
fi

# Verify installation
FINAL_COUNT=$(docker compose exec -T postgres psql -U wso2carbon -d identity_db -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name LIKE 'cm_%';" 2>/dev/null | xargs)

echo ""
echo -e "${BLUE}[INFO]${NC} Verification:"
echo -e "${GREEN}[SUCCESS]${NC} Created $FINAL_COUNT consent management tables"
echo ""

if [ "$FINAL_COUNT" = "10" ]; then
    echo "Tables created:"
    docker compose exec -T postgres psql -U wso2carbon -d identity_db -c "\dt cm_*"
    echo ""
    echo -e "${GREEN}✓${NC} Consent management schema installation complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Restart WSO2 Identity Server: docker compose restart wso2is"
    echo "  2. Test OAuth DCR endpoint"
    echo "  3. Run validation script: ./app_scripts/check_keymanager.sh"
else
    echo -e "${RED}[ERROR]${NC} Expected 10 tables but found $FINAL_COUNT"
    echo "Please check the logs and try again"
    exit 1
fi
