#!/usr/bin/env bash

################################################################################
# Script to apply REVISION_UUID column migration to WSO2 API Manager database
#
# This script fixes the error:
# "Unknown column 'REVISION_UUID' in 'where clause'"
#
# Usage:
#   ./scripts/apply_revision_uuid_fix.sh
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MIGRATION_FILE="${PROJECT_ROOT}/conf/mysql/scripts/zz_migration_add_revision_uuid_to_url_mapping.sql"
MYSQL_CONTAINER="mysql-wso2"

# Load environment variables
if [ -f "${PROJECT_ROOT}/.env" ]; then
    source "${PROJECT_ROOT}/.env"
fi

# Default MySQL credentials
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-root}"

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Check if migration file exists
check_migration_file() {
    if [ ! -f "${MIGRATION_FILE}" ]; then
        log_error "Migration file not found: ${MIGRATION_FILE}"
        return 1
    fi
    log_success "Migration file found"
}

# Check if MySQL container is running
check_mysql_container() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${MYSQL_CONTAINER}$"; then
        log_error "MySQL container '${MYSQL_CONTAINER}' is not running"
        log_info "Please start your services first: docker compose up -d mysql"
        return 1
    fi
    log_success "MySQL container is running"
}

# Check current database schema
check_current_schema() {
    log_info "Checking current database schema..."

    local column_exists=$(docker exec "${MYSQL_CONTAINER}" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -sN -e \
        "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'WSO2AM_DB' AND TABLE_NAME = 'AM_API_URL_MAPPING' AND COLUMN_NAME = 'REVISION_UUID';" 2>/dev/null || echo "0")

    if [ "${column_exists}" = "1" ]; then
        log_success "REVISION_UUID column already exists in AM_API_URL_MAPPING table"
        return 1
    else
        log_warn "REVISION_UUID column is missing from AM_API_URL_MAPPING table"
        return 0
    fi
}

# Apply the migration
apply_migration() {
    log_info "Applying migration to add REVISION_UUID column..."

    if docker exec -i "${MYSQL_CONTAINER}" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" < "${MIGRATION_FILE}"; then
        log_success "Migration applied successfully"
        return 0
    else
        log_error "Failed to apply migration"
        return 1
    fi
}

# Verify the fix
verify_fix() {
    log_info "Verifying the fix..."

    local column_exists=$(docker exec "${MYSQL_CONTAINER}" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -sN -e \
        "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'WSO2AM_DB' AND TABLE_NAME = 'AM_API_URL_MAPPING' AND COLUMN_NAME = 'REVISION_UUID';" 2>/dev/null || echo "0")

    if [ "${column_exists}" = "1" ]; then
        log_success "REVISION_UUID column verified in AM_API_URL_MAPPING table"

        # Show the table structure
        log_info "Current table structure:"
        docker exec "${MYSQL_CONTAINER}" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e \
            "DESCRIBE WSO2AM_DB.AM_API_URL_MAPPING;" 2>/dev/null | grep -E "Field|REVISION_UUID"

        return 0
    else
        log_error "Verification failed - REVISION_UUID column not found"
        return 1
    fi
}

# Main execution
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  WSO2 API Manager - REVISION_UUID Migration Script          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    log_info "Starting migration process..."
    echo ""

    # Perform checks
    check_migration_file || exit 1
    check_mysql_container || exit 1

    # Check if migration is needed
    if ! check_current_schema; then
        log_info "Migration not needed - column already exists"
        exit 0
    fi

    echo ""
    log_warn "This script will modify the WSO2AM_DB database"
    read -p "Do you want to continue? (yes/no): " -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        log_info "Migration cancelled by user"
        exit 0
    fi

    # Apply migration
    apply_migration || exit 1

    # Verify
    verify_fix || exit 1

    echo ""
    log_success "Migration completed successfully!"
    echo ""
    log_info "Next steps:"
    echo "  1. Restart WSO2 API Manager: docker compose restart wso2am"
    echo "  2. Try your API deployment again"
    echo ""
}

# Run main function
main "$@"
