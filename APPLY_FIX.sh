#!/bin/bash
# Script to apply the WSO2 character encoding fix
# This will recreate databases with utf8mb4 character set

set -e

echo "=========================================="
echo "WSO2 Character Encoding Fix - Apply Script"
echo "=========================================="
echo ""
echo "WARNING: This will DELETE all existing data in MySQL databases!"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

echo ""
echo "Step 1: Stopping WSO2 services..."
docker-compose stop wso2is wso2am || true

echo ""
echo "Step 2: Stopping MySQL..."
docker-compose stop postgres || true

echo ""
echo "Step 3: Removing MySQL container..."
docker-compose rm -f postgres || true

echo ""
echo "Step 4: Checking for MySQL data volume..."
if docker volume ls | grep -q "mysql-wso2-data"; then
    echo "Found named volume 'mysql-wso2-data', removing..."
    docker volume rm mysql-wso2-data || echo "Volume removal failed or doesn't exist"
fi

echo ""
echo "Step 5: Removing any anonymous volumes..."
docker volume ls -q -f dangling=true | xargs -r docker volume rm || true

echo ""
echo "Step 6: Starting MySQL with new utf8mb4 configuration..."
docker-compose up -d postgres

echo ""
echo "Step 7: Waiting for MySQL to initialize..."
echo "This may take 30-60 seconds..."
sleep 5

# Wait for MySQL to be ready
echo -n "Checking MySQL health"
for i in {1..30}; do
    if docker-compose ps postgres | grep -q "healthy"; then
        echo " ✓ MySQL is healthy!"
        break
    fi
    echo -n "."
    sleep 2
done

echo ""
echo "Step 8: Verifying database character sets..."
sleep 5  # Give MySQL a moment after health check

echo ""
echo "Checking database character sets:"
docker exec mysql-wso2 mysql -u root -proot -e "
SELECT
    SCHEMA_NAME,
    DEFAULT_CHARACTER_SET_NAME,
    DEFAULT_COLLATION_NAME
FROM information_schema.SCHEMATA
WHERE SCHEMA_NAME IN ('WSO2_SHARED_DB', 'WSO2_IDENTITY_DB', 'WSO2AM_DB');" 2>&1 || echo "Database query failed - databases may still be initializing"

echo ""
echo "Step 9: Starting WSO2 Identity Server..."
docker-compose up -d wso2is

echo ""
echo "Step 10: Waiting for WSO2 IS to initialize (60 seconds)..."
sleep 60

echo ""
echo "Step 11: Checking WSO2 IS status..."
if docker logs wso2is 2>&1 | tail -50 | grep -q "Mgt Console URL"; then
    echo "✓ WSO2 Identity Server started successfully!"
else
    echo "⚠ WSO2 IS may still be starting. Check logs with: docker logs -f wso2is"
fi

echo ""
echo "Step 12: Starting WSO2 API Manager..."
docker-compose up -d wso2am

echo ""
echo "Step 13: Waiting for WSO2 AM to initialize (60 seconds)..."
sleep 60

echo ""
echo "Step 14: Checking WSO2 AM status..."
if docker logs wso2am 2>&1 | tail -50 | grep -q "Mgt Console URL"; then
    echo "✓ WSO2 API Manager started successfully!"
else
    echo "⚠ WSO2 AM may still be starting. Check logs with: docker logs -f wso2am"
fi

echo ""
echo "=========================================="
echo "Fix Application Complete!"
echo "=========================================="
echo ""
echo "Verification Commands:"
echo ""
echo "Check WSO2 IS for errors:"
echo "  docker logs wso2is 2>&1 | grep -E 'ERROR.*Failed to share system application'"
echo ""
echo "Check WSO2 AM for errors:"
echo "  docker logs wso2am 2>&1 | grep -E 'ERROR.*User Manager Core bundle'"
echo ""
echo "View live logs:"
echo "  docker logs -f wso2is"
echo "  docker logs -f wso2am"
echo ""
echo "Access Management Consoles:"
echo "  WSO2 Identity Server: https://localhost:9444/carbon (admin/admin)"
echo "  WSO2 API Manager: https://localhost:9443/carbon (admin/admin)"
echo ""
