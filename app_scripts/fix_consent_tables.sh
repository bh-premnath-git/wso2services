#!/bin/bash

# =====================================================================
# Fix Missing Consent Management Tables in WSO2 Identity Server
# =====================================================================
# This script checks if consent management tables exist and applies
# the schema if they are missing.
#
# Usage: ./fix_consent_tables.sh
# =====================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONSENT_SCHEMA="$PROJECT_ROOT/conf/postgres/scripts/06-identity-consent-mgmt-schema.sql"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Consent Management Tables Check${NC}"
echo -e "${BLUE}========================================${NC}"

# Check if PostgreSQL is running
echo -e "${YELLOW}[INFO]${NC} Checking PostgreSQL container..."
if ! docker compose -f "$PROJECT_ROOT/docker-compose.yml" ps postgres | grep -q "Up"; then
    echo -e "${RED}[ERROR]${NC} PostgreSQL container is not running"
    echo -e "${YELLOW}[INFO]${NC} Start it with: docker compose up -d postgres"
    exit 1
fi
echo -e "${GREEN}[SUCCESS]${NC} PostgreSQL is running"

# Check if consent management tables exist
echo -e "${YELLOW}[INFO]${NC} Checking for consent management tables in identity_db..."
TABLE_COUNT=$(docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T postgres \
    psql -U wso2carbon -d identity_db -t -c \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name LIKE 'cm_%';" \
    | tr -d '[:space:]')

if [ "$TABLE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}[SUCCESS]${NC} Consent management tables already exist ($TABLE_COUNT tables found)"
    echo -e "${YELLOW}[INFO]${NC} Tables found:"
    docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T postgres \
        psql -U wso2carbon -d identity_db -c "\dt cm_*"
    exit 0
fi

echo -e "${YELLOW}[WARNING]${NC} Consent management tables are missing"
echo -e "${YELLOW}[INFO]${NC} This will cause errors when deleting OAuth apps via DCR"

# Check if schema file exists
if [ ! -f "$CONSENT_SCHEMA" ]; then
    echo -e "${RED}[ERROR]${NC} Schema file not found: $CONSENT_SCHEMA"
    exit 1
fi

echo -e "${YELLOW}[INFO]${NC} Applying consent management schema..."
echo -e "${YELLOW}[INFO]${NC} Schema file: $CONSENT_SCHEMA"

# Apply the schema
if docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T postgres \
    psql -U wso2carbon -d identity_db < "$CONSENT_SCHEMA"; then
    echo -e "${GREEN}[SUCCESS]${NC} Consent management schema applied successfully"
else
    echo -e "${RED}[ERROR]${NC} Failed to apply consent management schema"
    exit 1
fi

# Verify tables were created
echo -e "${YELLOW}[INFO]${NC} Verifying tables were created..."
TABLE_COUNT=$(docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T postgres \
    psql -U wso2carbon -d identity_db -t -c \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name LIKE 'cm_%';" \
    | tr -d '[:space:]')

if [ "$TABLE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}[SUCCESS]${NC} $TABLE_COUNT consent management tables created"
    echo -e "${YELLOW}[INFO]${NC} Tables created:"
    docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T postgres \
        psql -U wso2carbon -d identity_db -c "\dt cm_*"
else
    echo -e "${RED}[ERROR]${NC} Tables were not created successfully"
    exit 1
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}[SUCCESS]${NC} Consent management tables are now ready"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}[INFO]${NC} You can now safely delete OAuth apps without errors"
echo -e "${YELLOW}[INFO]${NC} The 'cm_receipt' error should no longer occur"
