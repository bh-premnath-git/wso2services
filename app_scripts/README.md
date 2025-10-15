# WSO2 Key Manager Setup Scripts

Portable scripts for configuring and validating WSO2 Identity Server as an external Key Manager for API Manager.

## 📋 **Scripts Overview**

### 1. **setup_is_users_roles.sh** ⭐
Creates roles and users in WSO2 Identity Server via SCIM2 API with OAuth token generation.

**Usage:**
```bash
./app_scripts/setup_is_users_roles.sh
```

**What it does:**
- ✅ Creates application roles (ops_users, finance, auditor, user, app_admin)
- ✅ Creates corresponding users
- ✅ Assigns roles to users
- ✅ Registers OAuth client (password grant)
- ✅ Generates access tokens for all users

**Default Users:**
| Username | Role | Password | Email |
|----------|------|----------|-------|
| ops_user | ops_users | OpsUser123! | ops_user@innover.local |
| finance | finance | Finance123! | finance@innover.local |
| auditor | auditor | Auditor123! | auditor@innover.local |
| user | user | User1234! | user@innover.local |
| app_admin | app_admin | AppAdmin123! | app_admin@innover.local |

**Environment Variables:**
```bash
IS_HOST=localhost           # Identity Server host (default: localhost)
IS_PORT=9444               # Identity Server port (default: 9444)
IS_ADMIN_USER=admin        # Admin username (default: admin)
IS_ADMIN_PASS=admin        # Admin password (default: admin)
MINT_TOKENS=true           # Generate OAuth tokens (default: true)

# Override user passwords
OPS_USER_PASS=YourPass123!
FINANCE_PASS=YourPass123!
AUDITOR_PASS=YourPass123!
USER_PASS=YourPass123!
APP_ADMIN_PASS=YourPass123!
```

---

### 2. **configure_keymanager.sh**
Automatically configures WSO2 Identity Server as an external Key Manager in API Manager.

**Usage:**
```bash
./app_scripts/configure_keymanager.sh
```

**What it does:**
- ✅ Checks prerequisites (curl, jq)
- ✅ Verifies WSO2 AM is running
- ✅ Lists existing Key Managers
- ✅ Creates WSO2-IS-KeyManager configuration
- ✅ Supports update of existing Key Manager
- ✅ Verifies configuration after creation

**Environment Variables:**
```bash
WSO2_AM_HOST=localhost       # API Manager host (default: localhost)
WSO2_AM_PORT=9443           # API Manager port (default: 9443)
WSO2_IS_HOST=wso2is         # Identity Server host (default: wso2is)
WSO2_IS_PORT=9443           # Identity Server port (default: 9443)
ADMIN_USER=admin            # Admin username (default: admin)
ADMIN_PASS=admin            # Admin password (default: admin)
KEY_MANAGER_NAME=WSO2-IS-KeyManager  # Key Manager name
```

---

### 3. **check_keymanager.sh**
Comprehensive validation suite for WSO2 Identity Server and API Manager integration.

**Usage:**
```bash
./app_scripts/check_keymanager.sh
```

**Tests performed:**
1. ✅ WSO2 Identity Server health check
2. ✅ WSO2 API Manager health check
3. ✅ OAuth2 token generation via DCR
4. ✅ Token introspection validation
5. ✅ Key Manager configuration check
6. ✅ End-to-end API call test (manual)
7. ✅ Microservices health check

**Environment Variables:**
```bash
WSO2_IS_HOST=localhost      # Identity Server host (default: localhost)
WSO2_IS_PORT=9444          # Identity Server port (default: 9444 - host mapped)
WSO2_AM_HOST=localhost      # API Manager host (default: localhost)
WSO2_AM_GATEWAY_PORT=8243   # API Gateway port (default: 8243)
WSO2_AM_PUBLISHER_PORT=9443 # API Manager Publisher port (default: 9443)
ADMIN_USER=admin            # Admin username (default: admin)
ADMIN_PASS=admin            # Admin password (default: admin)
```

---

## 🚀 **Quick Start (Fresh Installation)**

For a new system or first-time setup:

```bash
# 1. Start all services
docker compose up -d

# 2. Wait for services to be healthy (2-3 minutes)
docker compose ps

# 3. Configure Key Manager
./app_scripts/configure_keymanager.sh

# 4. Create users and roles
./app_scripts/setup_is_users_roles.sh

# 5. Validate setup
./app_scripts/check_keymanager.sh
```

---

## 🔧 **Existing Installation Migration**

If migrating to a new system with existing data:

```bash
# 1. Ensure database has consent management tables
./conf/postgres/apply-consent-schema.sh

# 2. Restart WSO2 services
docker compose restart wso2is wso2am

# 3. Configure Key Manager
./app_scripts/configure_keymanager.sh

# 4. Verify
./app_scripts/check_keymanager.sh
```

---

## 📁 **File Structure**

```
app_scripts/
├── setup_is_users_roles.sh      # Create users and roles in WSO2 IS
├── configure_keymanager.sh      # Configure WSO2 IS as Key Manager
├── check_keymanager.sh          # Validation test suite
├── generate_grpc.sh             # gRPC code generation
└── README.md                    # This file

conf/postgres/
├── scripts/
│   ├── 01-init-databases.sql           # Database initialization
│   ├── 02-shared-db-schema.sql         # APIM shared schema
│   ├── 03-apim-db-schema.sql           # APIM database schema
│   ├── 04-identity-db-schema.sql       # Identity Server schema
│   ├── 05-shared-db-is-schema.sql      # IS shared schema
│   └── 06-identity-consent-mgmt-schema.sql  # Consent tables (REQUIRED)
├── apply-consent-schema.sh      # Apply consent schema to existing DB
└── README.md                    # Database documentation
```

---

## ✅ **Expected Key Managers**

After running `configure_keymanager.sh`, you should see:

```json
{
  "count": 2,
  "list": [
    {
      "name": "WSO2-IS-KeyManager",
      "type": "WSO2-IS",
      "enabled": true,
      "tokenType": "DIRECT"
    },
    {
      "name": "Resident Key Manager",
      "type": "default",
      "enabled": true,
      "tokenType": "DIRECT"
    }
  ]
}
```

**View Key Managers:**
```bash
curl -k -u "admin:admin" "https://localhost:9443/api/am/admin/v4/key-managers" | jq .
```

---

## 🔍 **Troubleshooting**

### Issue: "WSO2 API Manager is not accessible"

**Solution:**
```bash
# Check if APIM is running
docker compose ps wso2am

# Check logs
docker compose logs wso2am

# Restart if needed
docker compose restart wso2am
```

### Issue: "relation cm_receipt does not exist"

**Solution:**
```bash
# Apply consent management schema
./conf/postgres/apply-consent-schema.sh

# Restart WSO2 IS
docker compose restart wso2is
```

### Issue: "Token generation failed with HTTP 400"

**Cause:** curl Authorization header encoding issue

**Solution:** The script uses `-u` flag instead of manual Basic auth encoding (already fixed in check_keymanager.sh)

### Issue: "Key Manager already exists"

**Solution:**
```bash
# The script will prompt to update
# Or manually delete and recreate:

# Get Key Manager ID
KM_ID=$(curl -k -s -u "admin:admin" \
  "https://localhost:9443/api/am/admin/v4/key-managers" | \
  jq -r '.list[] | select(.name=="WSO2-IS-KeyManager") | .id')

# Delete Key Manager
curl -k -u "admin:admin" -X DELETE \
  "https://localhost:9443/api/am/admin/v4/key-managers/${KM_ID}"

# Re-run configuration
./app_scripts/configure_keymanager.sh
```

---

## 🔐 **Port Mappings**

| Service | Container Port | Host Port | URL |
|---------|---------------|-----------|-----|
| WSO2 IS | 9443 | 9444 | https://localhost:9444 |
| WSO2 AM | 9443 | 9443 | https://localhost:9443 |
| API Gateway | 8243 | 8243 | https://localhost:8243 |
| PostgreSQL | 5432 | 5432 | localhost:5432 |

**Important:** 
- External access uses host port (e.g., 9444 for IS)
- Internal Docker network uses container port (e.g., 9443)
- Scripts handle this automatically

---

## 📚 **API Endpoints Reference**

### WSO2 Identity Server (Port 9444)
```bash
# Health check
curl -k https://localhost:9444/carbon/

# DCR - Create OAuth App
curl -k -u "admin:admin" -X POST \
  https://localhost:9444/api/identity/oauth2/dcr/v1.1/register \
  -H "Content-Type: application/json" \
  -d '{"client_name": "MyApp", "grant_types": ["client_credentials"]}'

# Generate Token
curl -k -u "CLIENT_ID:CLIENT_SECRET" -X POST \
  https://localhost:9444/oauth2/token \
  -d "grant_type=client_credentials"

# Introspect Token
curl -k -u "admin:admin" -X POST \
  https://localhost:9444/oauth2/introspect \
  -d "token=ACCESS_TOKEN"
```

### WSO2 API Manager (Port 9443)
```bash
# Health check
curl -k https://localhost:9443/carbon/

# List Key Managers
curl -k -u "admin:admin" \
  https://localhost:9443/api/am/admin/v4/key-managers | jq .

# Get specific Key Manager
curl -k -u "admin:admin" \
  https://localhost:9443/api/am/admin/v4/key-managers/{id} | jq .
```

---

## 🧪 **Testing OAuth Flow**

### Complete OAuth Test:
```bash
# 1. Create OAuth application
RESPONSE=$(curl -k -s -u "admin:admin" -X POST \
  https://localhost:9444/api/identity/oauth2/dcr/v1.1/register \
  -H "Content-Type: application/json" \
  -d '{"client_name": "TestApp", "grant_types": ["client_credentials"]}')

CLIENT_ID=$(echo $RESPONSE | jq -r '.client_id')
CLIENT_SECRET=$(echo $RESPONSE | jq -r '.client_secret')

echo "Client ID: $CLIENT_ID"
echo "Client Secret: $CLIENT_SECRET"

# 2. Generate access token
TOKEN_RESPONSE=$(curl -k -s -u "${CLIENT_ID}:${CLIENT_SECRET}" \
  -X POST https://localhost:9444/oauth2/token \
  -d "grant_type=client_credentials")

ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | jq -r '.access_token')
echo "Access Token: $ACCESS_TOKEN"

# 3. Introspect token
curl -k -u "admin:admin" -X POST \
  https://localhost:9444/oauth2/introspect \
  -d "token=${ACCESS_TOKEN}" | jq .

# 4. Cleanup
curl -k -u "admin:admin" -X DELETE \
  "https://localhost:9444/api/identity/oauth2/dcr/v1.1/register/${CLIENT_ID}"
```

---

## 📦 **Portability Checklist**

When moving to a new system, ensure you have:

- [x] `docker-compose.yml`
- [x] `conf/postgres/scripts/*.sql` (all 6 files)
- [x] `conf/postgres/apply-consent-schema.sh`
- [x] `app_scripts/configure_keymanager.sh`
- [x] `app_scripts/check_keymanager.sh`
- [x] `wso2is/conf/deployment.toml` (with DCR config)
- [x] `wso2am/conf/deployment.toml`

**Run on new system:**
```bash
docker compose up -d
./app_scripts/configure_keymanager.sh
./app_scripts/check_keymanager.sh
```

---

## 🎯 **Success Criteria**

Your setup is complete when:

✅ All Docker containers are healthy
✅ `check_keymanager.sh` passes all tests
✅ 2 Key Managers visible in APIM (Resident + WSO2-IS)
✅ Can create OAuth apps via DCR
✅ Can generate tokens using client credentials
✅ Can introspect tokens successfully

---

## 📖 **Additional Resources**

- [WSO2 IS Documentation](https://is.docs.wso2.com/en/latest/)
- [WSO2 APIM Documentation](https://apim.docs.wso2.com/en/latest/)
- [OAuth 2.0 RFC](https://oauth.net/2/)
- [Dynamic Client Registration](https://tools.ietf.org/html/rfc7591)

---

## 🆘 **Support**

If you encounter issues:

1. Check Docker logs: `docker compose logs [service-name]`
2. Verify database schema: `./conf/postgres/apply-consent-schema.sh`
3. Run validation: `./app_scripts/check_keymanager.sh`
4. Check port mappings: `docker compose ps`
5. Review configuration files in `conf/` directories

---

## 👥 **User Management**

### List Users
```bash
curl -sk -u "admin:admin" "https://localhost:9444/scim2/Users" | jq -r '.Resources[] | .userName'
```

### List Roles
```bash
curl -sk -u "admin:admin" "https://localhost:9444/scim2/Roles" | jq -r '.Resources[] | .displayName'
```

### Get User Details
```bash
curl -sk -u "admin:admin" "https://localhost:9444/scim2/Users?filter=userName%20eq%20%22ops_user%22" | jq .
```

### Generate Token for User (Password Grant)
```bash
# First, get OAuth client credentials from setup script output
# Then use password grant:
curl -sk -u "CLIENT_ID:CLIENT_SECRET" \
  -d "grant_type=password&username=ops_user&password=OpsUser123!&scope=openid" \
  https://localhost:9444/oauth2/token | jq .
```

### Delete User
```bash
# Get user ID
USER_ID=$(curl -sk -u "admin:admin" \
  "https://localhost:9444/scim2/Users?filter=userName%20eq%20%22user%22" | \
  jq -r '.Resources[0].id')

# Delete user
curl -sk -u "admin:admin" -X DELETE \
  "https://localhost:9444/scim2/Users/${USER_ID}"
```

---

**Last Updated:** October 2025  
**WSO2 IS Version:** 7.1.0  
**WSO2 APIM Version:** 4.5.0
