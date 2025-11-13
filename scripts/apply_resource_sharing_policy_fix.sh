#!/bin/bash

# ------------------------------------------------------------------------
#
# Copyright 2025 WSO2, LLC. (http://wso2.com)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License
#
# ------------------------------------------------------------------------

# Script to apply the resource sharing policy fix to an existing database
# This fixes the "Failed to delete resource sharing policy by type and ID" error

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MIGRATION_SCRIPT="$PROJECT_ROOT/conf/mysql/scripts/zz_migration_fix_resource_sharing_policy.sql"
MYSQL_CONTAINER="mysql-wso2"
MYSQL_USER="root"
MYSQL_PASSWORD="root"
MYSQL_DB="WSO2_IDENTITY_DB"

echo "=========================================="
echo "Resource Sharing Policy Fix"
echo "=========================================="
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running or not accessible"
    exit 1
fi

# Check if MySQL container is running
if ! docker ps | grep -q "$MYSQL_CONTAINER"; then
    echo "Error: MySQL container '$MYSQL_CONTAINER' is not running"
    echo "Start the services with: docker-compose up -d mysql"
    exit 1
fi

# Check if migration script exists
if [ ! -f "$MIGRATION_SCRIPT" ]; then
    echo "Error: Migration script not found at: $MIGRATION_SCRIPT"
    exit 1
fi

echo "✓ Docker is running"
echo "✓ MySQL container is running"
echo "✓ Migration script found"
echo ""

# Show current table structure
echo "Checking current table structure..."
docker exec -i "$MYSQL_CONTAINER" mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DB" <<EOF 2>/dev/null | grep -A 5 "UM_RESOURCE_SHARING_POLICY" || true
SHOW CREATE TABLE UM_RESOURCE_SHARING_POLICY\G
EOF
echo ""

# Ask for confirmation
read -p "Apply the migration fix? This will remove duplicate entries and add a UNIQUE constraint. (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Migration cancelled."
    exit 0
fi

echo ""
echo "Applying migration..."

# Execute the migration
if docker exec -i "$MYSQL_CONTAINER" mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" < "$MIGRATION_SCRIPT" 2>&1; then
    echo ""
    echo "✓ Migration applied successfully!"
    echo ""

    # Show updated table structure
    echo "Updated table structure:"
    docker exec -i "$MYSQL_CONTAINER" mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DB" <<EOF 2>/dev/null | grep -A 5 "UM_RESOURCE_SHARING_POLICY" || true
SHOW CREATE TABLE UM_RESOURCE_SHARING_POLICY\G
EOF

    echo ""
    echo "Next steps:"
    echo "1. Restart WSO2 IS: docker-compose restart wso2is"
    echo "2. Check logs: docker logs wso2is 2>&1 | grep -E 'ERROR|Exception|SEVERE|FATAL'"
    echo ""
else
    echo ""
    echo "✗ Migration failed. Check the error messages above."
    exit 1
fi
