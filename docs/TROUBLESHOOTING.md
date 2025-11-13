# WSO2 Services - Troubleshooting Guide

This guide helps you resolve common issues with the WSO2 API Manager and Identity Server setup.

## Table of Contents

1. [Database Schema Issues](#database-schema-issues)
2. [Authentication Errors](#authentication-errors)
3. [API Deployment Issues](#api-deployment-issues)
4. [Common Solutions](#common-solutions)

---

## Database Schema Issues

### Error: "Unknown column 'REVISION_UUID' in 'where clause'"

**Symptom:**
```
ERROR - ApiMgtDAO Error while getting primary endpoint mappings for API
java.sql.SQLSyntaxErrorException: Unknown column 'REVISION_UUID' in 'where clause'
```

**Cause:** The database was created with an older schema that's missing the `REVISION_UUID` column.

**Solution:**
1. Run the automated migration script:
   ```bash
   ./scripts/apply_revision_uuid_fix.sh
   ```

2. Restart WSO2 API Manager:
   ```bash
   docker compose restart wso2am
   ```

**See:** [WSO2AM_REVISION_UUID_FIX.md](./WSO2AM_REVISION_UUID_FIX.md) for detailed information.

---

## Authentication Errors

### Error: "Authentication failed: Bearer/Basic authentication header is missing"

**Symptom:**
```
ERROR - PostAuthenticationInterceptor Authentication failed: Bearer/Basic authentication header is missing
```

**Possible Causes:**

1. **Internal API calls during deployment**: This error can occur during API revision deployment when WSO2 AM makes internal calls to the gateway.

2. **Missing or invalid tokens**: API calls without proper authorization headers.

3. **Service-to-service communication issues**: WSO2 AM and WSO2 IS not communicating properly.

**Solutions:**

#### For internal deployment errors:
This error during API deployment is usually benign if the deployment succeeds. However, if it causes failures:

1. Check WSO2 AM can reach the gateway:
   ```bash
   docker compose exec wso2am curl -k https://localhost:8243/ -I
   ```

2. Verify gateway deployment configuration in `wso2am/repository/conf/deployment.toml`:
   ```toml
   [[apim.gateway.environment]]
   name = "Default"
   type = "hybrid"
   provider = "wso2"
   display_in_api_console = true
   description = "This is a hybrid gateway"
   show_as_token_endpoint_url = true
   service_url = "https://localhost:9443/services/"
   ws_endpoint = "ws://localhost:9099"
   wss_endpoint = "wss://localhost:8099"
   http_endpoint = "http://localhost:8280"
   https_endpoint = "https://localhost:8243"
   ```

#### For API call errors:
1. Ensure you're including the Authorization header:
   ```bash
   curl -k -H "Authorization: Bearer YOUR_TOKEN" https://localhost:8243/api/endpoint
   ```

2. Get a valid token first:
   ```bash
   ./scripts/wso2is-user.sh login username password client_id client_secret
   ```

3. Verify token validity:
   ```bash
   # The token should not be expired
   # Check token introspection
   ./scripts/wso2-toolkit.sh introspect-token YOUR_TOKEN
   ```

#### For service communication issues:
1. Check both services are running:
   ```bash
   docker compose ps wso2am wso2is
   ```

2. Check network connectivity:
   ```bash
   docker compose exec wso2am ping -c 3 wso2is
   docker compose exec wso2is ping -c 3 wso2am
   ```

3. Verify certificates are trusted (see next section)

---

## API Deployment Issues

### APIs fail to deploy or revision creation fails

**Symptoms:**
- API deployment hangs
- Revision creation fails
- Gateway deployment errors

**Common Causes & Solutions:**

#### 1. Database Schema Mismatch
- See [Database Schema Issues](#database-schema-issues) above

#### 2. Gateway Not Ready
```bash
# Check gateway health
curl -k https://localhost:8243/
```

If the gateway isn't responding:
```bash
docker compose restart wso2am
```

#### 3. Insufficient Resources
```bash
# Check container resource usage
docker stats wso2am --no-stream
```

If memory/CPU is maxed out:
- Increase Docker resource limits
- Adjust `JAVA_OPTS` in docker-compose.yml

#### 4. Previous Failed Deployments
```bash
# Clean up and retry
docker compose restart wso2am
# Wait 30 seconds for startup
sleep 30
# Try deployment again
./scripts/complete-workflow-test.sh
```

---

## Common Solutions

### Complete Service Restart

If you're experiencing multiple issues:

```bash
# Stop all services
docker compose down

# Start fresh (keeps data)
docker compose up -d

# Wait for services to be healthy
docker compose ps
```

### Fresh Database Reset

**WARNING: This deletes all data!**

```bash
# Stop services
docker compose down

# Remove MySQL volume
docker volume rm wso2services_mysql-data 2>/dev/null || true

# Restart services
docker compose up -d

# Wait for initialization
docker compose logs -f mysql | grep "initialization-complete"
```

### Check Service Health

```bash
# All-in-one health check
./scripts/wso2-toolkit.sh health

# Individual service checks
curl -k https://localhost:9443/carbon/admin/login.jsp    # WSO2 AM
curl -k https://localhost:9444/carbon/admin/login.jsp    # WSO2 IS
docker compose exec mysql mysql -uroot -proot -e "SELECT 1"  # MySQL
```

### Enable Debug Logging

For WSO2 API Manager, edit `wso2am/repository/conf/deployment.toml`:

```toml
[system.log]
level = "DEBUG"

[[loggers]]
name = "org.wso2.carbon.apimgt"
level = "DEBUG"
```

Then restart:
```bash
docker compose restart wso2am
```

View logs:
```bash
docker compose logs -f wso2am
```

### Certificate Trust Issues

If you see SSL/certificate errors:

```bash
# Check MTLS setup
./scripts/wso2-toolkit.sh check-mtls

# Fix MTLS if needed
./scripts/wso2-toolkit.sh fix-mtls

# Check SSA JWKS
./scripts/wso2-toolkit.sh check-ssa-jwks
```

### Database Connection Issues

```bash
# Test MySQL connectivity
docker compose exec wso2am ping -c 3 mysql-wso2

# Check MySQL is ready
docker compose exec mysql mysqladmin ping -uroot -proot

# View MySQL logs
docker compose logs mysql --tail=100
```

---

## Getting Help

### Collect Diagnostic Information

When reporting issues, collect this information:

```bash
# Service status
docker compose ps > diagnostic-services.txt

# Recent logs
docker compose logs --tail=500 wso2am > diagnostic-wso2am.log
docker compose logs --tail=500 wso2is > diagnostic-wso2is.log
docker compose logs --tail=200 mysql > diagnostic-mysql.log

# Configuration
docker compose config > diagnostic-compose-config.yml

# Database schema version
docker compose exec mysql mysql -uroot -proot -e \
  "SELECT TABLE_NAME, CREATE_TIME FROM INFORMATION_SCHEMA.TABLES \
   WHERE TABLE_SCHEMA = 'WSO2AM_DB' ORDER BY CREATE_TIME LIMIT 10;" \
  > diagnostic-db-schema.txt
```

### Useful Log Commands

```bash
# Follow logs in real-time
docker compose logs -f wso2am

# Filter for errors only
docker compose logs wso2am 2>&1 | grep -E "ERROR|Exception"

# Last 2 minutes of errors
docker compose logs wso2am --since 2m 2>&1 | grep -E "ERROR|Exception"

# Save logs to file
docker compose logs --no-color wso2am > wso2am-full.log
```

### Environment Verification

```bash
# Check Docker version
docker --version
docker compose version

# Check available resources
docker info | grep -E "CPUs|Total Memory"

# List volumes
docker volume ls | grep wso2services

# Check network
docker network ls | grep payment-network
docker network inspect wso2services_payment-network
```

---

## Quick Reference

### Essential Commands

| Task | Command |
|------|---------|
| Start all services | `docker compose up -d` |
| Stop all services | `docker compose down` |
| View service status | `docker compose ps` |
| View logs | `docker compose logs -f <service>` |
| Restart a service | `docker compose restart <service>` |
| Health check | `./scripts/wso2-toolkit.sh health` |
| Complete workflow test | `./scripts/complete-workflow-test.sh` |
| Apply DB migration | `./scripts/apply_revision_uuid_fix.sh` |

### Important Ports

| Service | Port | URL |
|---------|------|-----|
| WSO2 AM (HTTPS) | 9443 | https://localhost:9443/carbon |
| WSO2 AM Gateway (HTTPS) | 8243 | https://localhost:8243 |
| WSO2 AM Gateway (HTTP) | 8280 | http://localhost:8280 |
| WSO2 IS (HTTPS) | 9444 | https://localhost:9444/carbon |
| MySQL | 3306 | localhost:3306 |
| Jaeger UI | 16686 | http://localhost:16686 |

### Default Credentials

| Service | Username | Password |
|---------|----------|----------|
| WSO2 AM/IS Admin | admin | admin |
| MySQL Root | root | root (or check .env) |
| MySQL WSO2 User | wso2carbon | wso2carbon |

---

## See Also

- [WSO2AM_REVISION_UUID_FIX.md](./WSO2AM_REVISION_UUID_FIX.md) - Database migration guide
- [WSO2_STARTUP_ERROR_FIX.md](./WSO2_STARTUP_ERROR_FIX.md) - Character encoding issues
- [README.md](../README.md) - Project overview and setup
