# WSO2 Startup Error Fix - Character Encoding Issues

## Problem

WSO2 services were failing to start with the following errors:

### WSO2 Identity Server (wso2is)
```
[2025-11-13 07:17:51,811] [] ERROR {org.wso2.identity.apps.common.internal.AppsCommonServiceComponent}
- Failed to activate identity apps common service component.
org.wso2.carbon.identity.application.common.IdentityApplicationManagementException: Failed to share system application.
```

### WSO2 API Manager (wso2am)
```
[2025-11-13 07:17:18,041] ERROR - DefaultRealm nullType class java.lang.reflect.InvocationTargetException
[2025-11-13 07:17:18,041] ERROR - Activator Cannot start User Manager Core bundle
```

## Root Cause

The MySQL databases were configured with the **latin1** character set, which is incompatible with modern WSO2 versions (WSO2 Identity Server 7.x and WSO2 API Manager 4.x).

### Why This Caused Failures

1. **WSO2 Identity Server Error**:
   - During startup, WSO2 IS creates system applications (Console, My Account, etc.)
   - These applications contain Unicode characters in their configurations
   - The `latin1` character set cannot properly handle these Unicode characters
   - This causes database operations to fail, resulting in "Failed to share system application" error

2. **WSO2 API Manager Error**:
   - The User Manager Core bundle initializes user management tables and operations
   - User management data (usernames, roles, permissions) often contain Unicode characters
   - Character encoding mismatches cause database read/write operations to fail
   - This prevents the User Manager Core bundle from starting properly

### Technical Details

- **latin1** (ISO-8859-1): Single-byte character set supporting only Western European characters (256 characters total)
- **utf8mb4**: Multi-byte character set supporting full Unicode including emojis and international characters
- WSO2 products generate internal data with Unicode characters that require proper UTF-8 encoding

## Solution

The fix involves three components:

### 1. Database Character Set Configuration

Changed all database creation statements from `latin1` to `utf8mb4`:

**Modified Files:**
- `conf/mysql/scripts/mysql_shared.sql`
- `conf/mysql/scripts/mysql_identity.sql`
- `conf/mysql/scripts/mysql_apim.sql`

**Changes:**
```sql
# Before
CREATE DATABASE WSO2_SHARED_DB CHARACTER SET latin1;
CREATE DATABASE WSO2_IDENTITY_DB CHARACTER SET latin1;
CREATE DATABASE WSO2AM_DB CHARACTER SET latin1;

# After
CREATE DATABASE WSO2_SHARED_DB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE WSO2_IDENTITY_DB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE WSO2AM_DB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

### 2. JDBC Connection String Configuration

Added character encoding parameters to all JDBC URLs:

**Modified Files:**
- `wso2is/repository/conf/deployment.toml`
- `wso2am/repository/conf/deployment.toml`

**Changes:**
```toml
# Before
url = "jdbc:mysql://mysql-wso2:3306/WSO2_IDENTITY_DB?useSSL=false&amp;allowPublicKeyRetrieval=true"

# After
url = "jdbc:mysql://mysql-wso2:3306/WSO2_IDENTITY_DB?useSSL=false&amp;allowPublicKeyRetrieval=true&amp;characterEncoding=UTF-8&amp;connectionCollation=utf8mb4_unicode_ci"
```

**Parameters Added:**
- `characterEncoding=UTF-8` - Forces JDBC driver to use UTF-8 encoding for string data
- `connectionCollation=utf8mb4_unicode_ci` - Sets the connection collation to match database collation

### 3. MySQL Server Configuration

Updated MySQL server configuration to set UTF-8 as default:

**Modified File:** `conf/mysql/conf/my.cnf`

**Changes:**
```ini
[mysqld]
max_connections=1000
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci

[client]
default-character-set=utf8mb4

[mysql]
default-character-set=utf8mb4
```

## How to Apply the Fix

### For New Deployments

The fix is already applied in the configuration files. Simply start the services:

```bash
docker-compose up -d postgres  # Start MySQL first
docker-compose up -d wso2is wso2am
```

### For Existing Deployments

If you have existing databases with data, you need to:

1. **Backup your data first**:
   ```bash
   docker exec mysql-wso2 mysqldump -u root -proot --all-databases > backup.sql
   ```

2. **Stop all WSO2 services**:
   ```bash
   docker-compose stop wso2is wso2am
   ```

3. **Drop and recreate databases** (This will DELETE all data):
   ```bash
   docker-compose down postgres
   docker volume rm wso2services_postgres-data  # If using named volume
   docker-compose up -d postgres
   ```

4. **Wait for MySQL to initialize** (check logs):
   ```bash
   docker logs -f mysql-wso2
   # Wait for: "Initialization complete" or similar message
   ```

5. **Start WSO2 services**:
   ```bash
   docker-compose up -d wso2is wso2am
   ```

## Verification

After applying the fix, verify that the services start correctly:

### Check WSO2 Identity Server

```bash
# Wait for startup (60-120 seconds)
sleep 90

# Check for errors
docker logs wso2is 2>&1 | grep -E "ERROR.*Failed to share system application"

# If no output, the issue is fixed. You should see:
docker logs wso2is 2>&1 | grep "Mgt Console URL"
# Output: WSO2 Carbon started in XX sec
```

### Check WSO2 API Manager

```bash
# Check for User Manager errors
docker logs wso2am 2>&1 | grep -E "ERROR.*User Manager Core bundle"

# If no output, the issue is fixed. You should see:
docker logs wso2am 2>&1 | grep "Mgt Console URL"
# Output: WSO2 Carbon started in XX sec
```

### Verify Database Character Set

```bash
docker exec mysql-wso2 mysql -u root -proot -e "
SELECT
    SCHEMA_NAME,
    DEFAULT_CHARACTER_SET_NAME,
    DEFAULT_COLLATION_NAME
FROM information_schema.SCHEMATA
WHERE SCHEMA_NAME IN ('WSO2_SHARED_DB', 'WSO2_IDENTITY_DB', 'WSO2AM_DB');"
```

**Expected Output:**
```
+-------------------+----------------------------+--------------------+
| SCHEMA_NAME       | DEFAULT_CHARACTER_SET_NAME | DEFAULT_COLLATION_NAME |
+-------------------+----------------------------+--------------------+
| WSO2_SHARED_DB    | utf8mb4                    | utf8mb4_unicode_ci |
| WSO2_IDENTITY_DB  | utf8mb4                    | utf8mb4_unicode_ci |
| WSO2AM_DB         | utf8mb4                    | utf8mb4_unicode_ci |
+-------------------+----------------------------+--------------------+
```

### Access Management Consoles

Once started, access the consoles to verify full functionality:

**WSO2 Identity Server:**
- URL: https://localhost:9444/carbon
- Username: admin
- Password: admin

**WSO2 API Manager:**
- URL: https://localhost:9443/carbon
- Username: admin
- Password: admin

## Prevention

To prevent character encoding issues in future deployments:

1. **Always use UTF-8 encoding** for WSO2 databases:
   - Use `utf8mb4` character set for MySQL 5.5+
   - Use `utf8` for older MySQL versions (note: limited emoji support)

2. **Include character encoding in JDBC URLs**:
   - Always add `characterEncoding=UTF-8` parameter
   - Add `connectionCollation` parameter matching database collation

3. **Set MySQL server defaults**:
   - Configure `character-set-server=utf8mb4` in my.cnf
   - Set client default to `utf8mb4`

4. **Test with international characters**:
   - Create users with Unicode names (e.g., José, 김철수, محمد)
   - Verify data is stored and retrieved correctly

## Related Issues

This fix resolves:
- System application sharing failures in WSO2 IS
- User Manager Core bundle initialization failures in WSO2 AM
- Character encoding errors in user management operations
- Unicode data corruption in application metadata
- Database string handling issues with international characters

## Technical References

- [MySQL Character Sets and Collations](https://dev.mysql.com/doc/refman/8.0/en/charset-mysql.html)
- [MySQL utf8mb4 Character Set](https://dev.mysql.com/doc/refman/8.0/en/charset-unicode-utf8mb4.html)
- [WSO2 IS Database Configuration](https://is.docs.wso2.com/en/latest/setup/working-with-databases/)
- [WSO2 AM Database Configuration](https://apim.docs.wso2.com/en/latest/install-and-setup/setup/setting-up-databases/overview/)
- [MySQL Connector/J Character Encoding](https://dev.mysql.com/doc/connector-j/8.0/en/connector-j-reference-charsets.html)

## Files Modified

| File | Changes |
|------|---------|
| `conf/mysql/scripts/mysql_shared.sql` | Changed database character set to utf8mb4 |
| `conf/mysql/scripts/mysql_identity.sql` | Changed database character set to utf8mb4 |
| `conf/mysql/scripts/mysql_apim.sql` | Changed database character set to utf8mb4 |
| `wso2is/repository/conf/deployment.toml` | Added character encoding to JDBC URLs |
| `wso2am/repository/conf/deployment.toml` | Added character encoding to JDBC URLs |
| `conf/mysql/conf/my.cnf` | Added UTF-8 defaults for server and clients |

## Commit Information

- **Branch**: `claude/fix-wso2-startup-errors-011CV5WSejeQp4EYdeMjXsS2`
- **Fix Date**: 2025-11-13
- **Tested On**:
  - WSO2 Identity Server 7.2.0
  - WSO2 API Manager 4.6.0
  - MySQL 8.0.44
