# WSO2 API Manager - REVISION_UUID Column Migration Fix

## Issue Description

When deploying APIs in WSO2 API Manager 4.6.0, you may encounter the following SQL error:

```
ERROR - ApiMgtDAO Error while getting primary endpoint mappings for API : 8fc26b23-cfe8-48a1-9b4b-20e5f3bbffc8
java.sql.SQLSyntaxErrorException: Unknown column 'REVISION_UUID' in 'where clause'
```

## Root Cause

The `AM_API_URL_MAPPING` table in the WSO2AM_DB database is missing the `REVISION_UUID` column. This happens when:

1. The database was created with an older schema version
2. The database wasn't recreated after schema updates
3. Migration scripts weren't run during upgrades

The current schema file (`conf/mysql/scripts/mysql_apim.sql:1610`) includes the `REVISION_UUID` column, but existing databases may not have it.

## Solution

We provide two ways to fix this issue:

### Option 1: Automated Migration Script (Recommended)

Run the provided migration script that will add the missing column to your existing database:

```bash
./scripts/apply_revision_uuid_fix.sh
```

This script will:
1. Check if the column already exists (idempotent)
2. Add the `REVISION_UUID VARCHAR(255)` column if missing
3. Verify the fix was applied successfully

After running the script, restart WSO2 API Manager:

```bash
docker compose restart wso2am
```

### Option 2: Manual Database Migration

If you prefer to apply the migration manually:

1. Copy the migration SQL to the MySQL container:
   ```bash
   docker exec -i mysql-wso2 mysql -uroot -proot < conf/mysql/scripts/zz_migration_add_revision_uuid_to_url_mapping.sql
   ```

2. Verify the column was added:
   ```bash
   docker exec mysql-wso2 mysql -uroot -proot -e "DESCRIBE WSO2AM_DB.AM_API_URL_MAPPING;" | grep REVISION_UUID
   ```

3. Restart WSO2 API Manager:
   ```bash
   docker compose restart wso2am
   ```

### Option 3: Complete Database Recreation

If you don't have important data and want a fresh start:

```bash
# Stop all services
docker compose down

# Remove the MySQL data volume
docker volume rm wso2services_mysql-data 2>/dev/null || true

# Start services (database will be recreated with latest schema)
docker compose up -d
```

**Warning:** This will delete all existing data in the WSO2 databases.

## Verification

After applying the fix, verify the column exists:

```bash
docker exec mysql-wso2 mysql -uroot -proot -e "SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'WSO2AM_DB' AND TABLE_NAME = 'AM_API_URL_MAPPING' AND COLUMN_NAME = 'REVISION_UUID';"
```

Expected output:
```
+---------------+-----------+--------------------------+
| COLUMN_NAME   | DATA_TYPE | CHARACTER_MAXIMUM_LENGTH |
+---------------+-----------+--------------------------+
| REVISION_UUID | varchar   |                      255 |
+---------------+-----------+--------------------------+
```

## Testing the Fix

After applying the migration and restarting WSO2 AM, test API deployment:

```bash
# Run the complete workflow test
./scripts/complete-workflow-test.sh
```

The API deployment step should now complete without the `REVISION_UUID` error.

## Prevention

To prevent this issue in the future:

1. **Always recreate databases after schema updates**: If you pull new schema files, recreate the database or run migration scripts.

2. **Use the provided migration scripts**: The `conf/mysql/scripts/zz_migration_*.sql` files are designed to run during database initialization.

3. **Check logs during startup**: Monitor MySQL initialization logs to ensure all scripts execute successfully.

## Related Files

- Migration script: `conf/mysql/scripts/zz_migration_add_revision_uuid_to_url_mapping.sql`
- Automation script: `scripts/apply_revision_uuid_fix.sh`
- Schema definition: `conf/mysql/scripts/mysql_apim.sql:1610`

## Additional Notes

### About REVISION_UUID

The `REVISION_UUID` column is part of WSO2 API Manager's API revision feature introduced in version 4.x. It allows:

- Creating multiple revisions of an API
- Deploying specific revisions to different gateways
- Rolling back to previous API versions
- Managing API lifecycle more granularly

Without this column, the API Manager cannot properly track and manage API revisions, leading to deployment failures.

### Schema Version

This fix is applicable to:
- WSO2 API Manager: 4.6.0
- MySQL: 8.0.44
- Schema: As defined in `mysql_apim.sql`

## Troubleshooting

### Issue: Script says "column already exists" but error persists

**Solution:** Restart WSO2 API Manager to pick up the schema changes:
```bash
docker compose restart wso2am
```

### Issue: "MySQL container is not running"

**Solution:** Start the MySQL service first:
```bash
docker compose up -d mysql
# Wait for it to be healthy
docker compose ps mysql
```

### Issue: Migration fails with permission denied

**Solution:** Check MySQL root password in `.env` file matches the one used in the container:
```bash
grep MYSQL_ROOT_PASSWORD .env
```

### Issue: Still getting errors after migration

**Solution:** Check WSO2 AM logs for other potential issues:
```bash
docker compose logs wso2am --tail=100 | grep -E "ERROR|Exception"
```

## Support

If you continue experiencing issues after applying this fix:

1. Check the WSO2 AM logs: `docker compose logs wso2am`
2. Verify database connectivity: `docker compose exec wso2am ping -c 3 mysql-wso2`
3. Review the complete workflow: `./scripts/complete-workflow-test.sh`

For more information about WSO2 API Manager revisions, see:
- [WSO2 API Manager Documentation](https://apim.docs.wso2.com/en/latest/)
- [API Revisions and Deployments](https://apim.docs.wso2.com/en/latest/design/create-api/create-api-revisions/)
