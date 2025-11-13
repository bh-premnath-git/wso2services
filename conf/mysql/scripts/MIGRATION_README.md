# Database Migration Guide

## Resource Sharing Policy Fix

### Problem
WSO2 Identity Server fails to start with the following error:
```
Failed to delete resource sharing policy by type and ID
ResourceSharingPolicyMgtServerException
```

This error occurs when the `UM_RESOURCE_SHARING_POLICY` table has duplicate entries or is missing a UNIQUE constraint.

### Solution
The migration script `zz_migration_fix_resource_sharing_policy.sql` fixes this issue by:
1. Removing duplicate entries (keeping the most recent)
2. Adding a UNIQUE constraint to prevent future duplicates

### For New Installations
The migration script runs automatically during database initialization (it's in `/docker-entrypoint-initdb.d/`).

### For Existing Databases
If your database is already initialized and you're experiencing this error, you need to manually apply the migration:

#### Option 1: Reset the database (DESTRUCTIVE - all data will be lost)
```bash
# Stop all services
docker-compose down

# Remove the MySQL volume to force re-initialization
docker volume rm wso2services_mysql-data

# Start services again (database will be re-initialized with the fix)
docker-compose up -d
```

#### Option 2: Apply migration manually (SAFE - preserves data)
```bash
# Copy the migration script into the running MySQL container
docker cp conf/mysql/scripts/zz_migration_fix_resource_sharing_policy.sql mysql-wso2:/tmp/

# Execute the migration script
docker exec -it mysql-wso2 mysql -uroot -proot < /tmp/zz_migration_fix_resource_sharing_policy.sql

# Verify the constraint was added
docker exec -it mysql-wso2 mysql -uroot -proot -e "
USE WSO2_IDENTITY_DB;
SHOW CREATE TABLE UM_RESOURCE_SHARING_POLICY;
"

# Restart WSO2 IS to apply changes
docker-compose restart wso2is
```

#### Option 3: Direct SQL execution
```bash
# Execute the migration directly
docker exec -i mysql-wso2 mysql -uroot -proot WSO2_IDENTITY_DB < conf/mysql/scripts/zz_migration_fix_resource_sharing_policy.sql

# Restart WSO2 IS
docker-compose restart wso2is
```

### Verification
After applying the fix, check that WSO2 IS starts without errors:
```bash
docker logs wso2is 2>&1 | grep -E "ERROR|Exception|SEVERE|FATAL"
```

If the output is clean (no resource sharing policy errors), the fix was successful.

### Technical Details
The migration script adds the following UNIQUE constraint:
```sql
ALTER TABLE UM_RESOURCE_SHARING_POLICY
ADD CONSTRAINT UQ_RESOURCE_POLICY UNIQUE (
    UM_RESOURCE_TYPE,
    UM_RESOURCE_ID,
    UM_POLICY_HOLDING_ORG_ID
);
```

This prevents duplicate policies for the same resource type, resource ID, and policy holding organization combination.
