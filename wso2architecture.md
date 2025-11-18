# WSO2 Global Transfer Backend - Architecture Documentation

## Table of Contents
1. [Overview](#overview)
2. [Architecture Diagram](#architecture-diagram)
3. [Components](#components)
4. [Database Architecture](#database-architecture)
5. [Docker Services](#docker-services)
6. [Configuration Details](#configuration-details)
7. [Security Setup](#security-setup)
8. [Key Manager Integration](#key-manager-integration)
9. [Network & Ports](#network--ports)
10. [Health Checks](#health-checks)
11. [Initialization Workflow](#initialization-workflow)
12. [File Structure](#file-structure)
13. [Common Operations](#common-operations)

---

## Overview

This architecture implements a **WSO2 API Management (APIM) 4.6.0** solution integrated with **WSO2 Identity Server (IS) 7.1.0** acting as a Key Manager. The entire stack is containerized using Docker Compose and uses MySQL 8.0.33 as the shared database backend.

### Key Features
- **API Management**: Full API lifecycle management with WSO2 APIM 4.6.0
- **Identity & Access Management**: WSO2 IS 7.1.0 as Key Manager for OAuth2/OIDC flows
- **Shared User Store**: Database-backed user management across both products
- **Container Orchestration**: Docker Compose with health checks and dependency management
- **Secure Communication**: SSL/TLS with custom keystores and truststores

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Docker Compose Network                       │
│                                                                   │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐  │
│  │              │      │              │      │              │  │
│  │    MySQL     │◄─────┤  IS-AS-KM    │◄─────┤  API Manager │  │
│  │   (8.0.33)   │      │   (IS 7.1.0) │      │  (APIM 4.6.0)│  │
│  │              │      │              │      │              │  │
│  │ Port: 3306   │      │ Port: 9444   │      │ Port: 9443   │  │
│  │              │      │ Port: 9764   │      │ Port: 8280   │  │
│  └──────────────┘      └──────────────┘      │ Port: 8243   │  │
│         │                     │               └──────────────┘  │
│         │                     │                      │           │
│         └─────────────────────┴──────────────────────┘           │
│                    Shared Database Layer                         │
│         - WSO2_IS_SHARED_DB                                      │
│         - WSO2_IS_DB                                             │
│         - WSO2AM_SHARED_DB                                       │
│         - WSO2AM_DB                                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## Components

### 1. MySQL Database (mysql)
- **Image**: `mysql:8.0.33`
- **Purpose**: Central data store for both WSO2 IS and APIM
- **Databases**:
  - `WSO2_IS_SHARED_DB` - Identity Server shared data (user store, registry)
  - `WSO2_IS_DB` - Identity Server specific data
  - `WSO2AM_SHARED_DB` - API Manager shared data (user store, registry)
  - `WSO2AM_DB` - API Manager specific data (APIs, subscriptions, etc.)
- **User**: `wso2carbon` / `wso2carbon`
- **Root Password**: `root`

### 2. WSO2 Identity Server as Key Manager (is-as-km)
- **Base Image**: `wso2/wso2is:7.1.0`
- **Version**: 7.1.0
- **Purpose**: 
  - OAuth2/OIDC authorization server
  - Token generation and validation
  - User authentication and identity management
  - Key Manager for APIM
- **Extensions**:
  - `wso2is.key.manager.core-2.0.6.jar` (dropin)
  - `wso2is.notification.event.handlers-2.0.6.jar` (dropin)
  - `keymanager-operations.war` (webapp)

### 3. WSO2 API Manager (api-manager)
- **Base Image**: `wso2/wso2am:4.6.0`
- **Version**: 4.6.0
- **Purpose**:
  - API Gateway for routing and mediation
  - API Publisher portal
  - Developer portal
  - Admin portal
  - Traffic management and throttling
- **Gateway Types Supported**: Regular, APK, AWS, Azure, Kong, Envoy

---

## Database Architecture

### Database Schema Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         MySQL 8.0.33                         │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────────────┐    ┌─────────────────────┐        │
│  │ WSO2_IS_SHARED_DB   │    │ WSO2AM_SHARED_DB    │        │
│  ├─────────────────────┤    ├─────────────────────┤        │
│  │ - Registry (REG_*)  │    │ - Registry (REG_*)  │        │
│  │ - User Mgmt (UM_*)  │    │ - User Mgmt (UM_*)  │        │
│  │ - Claim Dialect     │    │ - Claim Dialect     │        │
│  └─────────────────────┘    └─────────────────────┘        │
│                                                               │
│  ┌─────────────────────┐    ┌─────────────────────┐        │
│  │ WSO2_IS_DB          │    │ WSO2AM_DB           │        │
│  ├─────────────────────┤    ├─────────────────────┤        │
│  │ - Identity data     │    │ - API definitions   │        │
│  │ - OAuth2 tokens     │    │ - Subscriptions     │        │
│  │ - User sessions     │    │ - Applications      │        │
│  │ - Consent mgmt      │    │ - Policies          │        │
│  └─────────────────────┘    └─────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### Database Initialization Scripts

Executed in order during MySQL container startup:

1. **01_create_databases.sql** - Creates 4 databases (WSO2_IS_SHARED_DB, WSO2_IS_DB, WSO2AM_SHARED_DB, WSO2AM_DB), creates `wso2carbon` user, grants privileges
2. **02_wso2_is_shared_db.sql** - Initializes Identity Server shared database schema (registry, user management)
3. **03_wso2_is_db.sql** - Identity Server specific schema (OAuth2, SAML, authentication, session management)
4. **04_wso2am_shared_db.sql** - API Manager shared database schema (user store and registry for APIM)
5. **05_wso2am_db.sql** - API Manager specific schema (API metadata, subscriptions, applications, policies)
6. **06_fix_claim_mappings_apim.sql** - Fixes critical claim mappings in WSO2AM_SHARED_DB for `accountLocked` claim
7. **07_fix_claim_mappings_is.sql** - Fixes critical claim mappings in WSO2_IS_SHARED_DB for `accountLocked` claim
8. **z_health_check.sh** - Creates flag file `/var/lib/mysql/initialization-complete.flag` for health check

### MySQL Configuration

**File**: `conf/mysql/conf/my.cnf`
```ini
[mysqld]
max_connections=1000
```

**Ulimits**: Soft: 20000, Hard: 40000

---

## Docker Services

### Service Dependency Chain

```
mysql (healthy)
  └─► is-as-km (healthy)
       └─► api-manager
```

### MySQL Service

**Configuration in docker-compose.yml**:
- **Image**: mysql:8.0.33
- **Ports**: 3306:3306
- **Environment**: MYSQL_ROOT_PASSWORD=root
- **Volumes**:
  - `./conf/mysql/scripts:/docker-entrypoint-initdb.d` - Auto-executes SQL scripts
  - `./conf/mysql/conf/my.cnf:/etc/mysql/mysql.conf.d/my.cnf` - MySQL config
- **Command**: `[--ssl=0]` - SSL disabled for local development
- **Health Check**: 
  - Test: `mysqladmin ping -uroot -proot && [ -f /var/lib/mysql/initialization-complete.flag ]`
  - Interval: 30s, Timeout: 60s, Retries: 5, Start Period: 80s
  - Validates MySQL availability AND initialization completion

### IS-AS-KM Service

**Dockerfile**: `dockerfiles/is-as-km/Dockerfile`
```dockerfile
FROM wso2/wso2is:7.1.0

# Copy Key Manager extensions
COPY dockerfiles/is-as-km/dropins /home/wso2carbon/wso2is-7.1.0/repository/components/dropins/

# Copy Key Manager webapps
COPY dockerfiles/is-as-km/webapps /home/wso2carbon/wso2is-7.1.0/repository/deployment/server/webapps/

# Add MySQL connector
ADD --chown=wso2carbon:wso2 wso2/reposistory/components/lib/mysql-connector-j-8.0.33.jar \
    /home/wso2carbon/wso2is-7.1.0/repository/components/lib/mysql-connector-j-8.0.33.jar
```

**Configuration in docker-compose.yml**:
- **Ports**: 9444:9443 (HTTPS), 9764:9763 (HTTP)
- **Dependencies**: `mysql` (service_healthy condition)
- **Volumes**:
  - `deployment.toml` - Main configuration file
  - `client-truststore.p12` - Client truststore
  - `wso2carbon.p12` - Primary keystore
- **Health Check**:
  - Test: `curl -k --fail https://localhost:9443/api/health-check/v1.0/health`
  - Interval: 10s, Start Period: 180s, Retries: 20

**Key Extensions**:
- **wso2is.key.manager.core-2.0.6.jar**: Core Key Manager functionality
- **wso2is.notification.event.handlers-2.0.6.jar**: Event handlers for token revocation
- **keymanager-operations.war**: REST API for Key Manager operations

### API Manager Service

**Dockerfile**: `dockerfiles/apim/Dockerfile`
```dockerfile
FROM wso2/wso2am:4.6.0

# Add MySQL connector
ADD --chown=wso2carbon:wso2 wso2/reposistory/components/lib/mysql-connector-j-8.0.33.jar \
    /home/wso2carbon/wso2am-4.6.0/repository/components/lib/mysql-connector-j-8.0.33.jar
```

**Configuration in docker-compose.yml**:
- **Ports**: 9443:9443 (HTTPS), 8280:8280 (HTTP Gateway), 8243:8243 (HTTPS Gateway)
- **Dependencies**: `mysql` and `is-as-km` (both service_healthy condition)
- **Volumes**:
  - `deployment.toml` - Main configuration file
  - `client-truststore.jks` - Client truststore
  - `wso2carbon.jks` - TLS keystore
- **Health Check**:
  - Test: `curl --fail http://localhost:9763/services/Version`
  - Interval: 10s, Start Period: 180s, Retries: 20

---

## Configuration Details

### Identity Server Configuration

**File**: `conf/is-as-km/repository/conf/deployment.toml`

**Critical Settings**:

```toml
[server]
hostname = "localhost"
node_ip = "127.0.0.1"
base_path = "https://localhost:9443"

[super_admin]
username = "admin"
password = "admin"
create_admin_account = true

[user_store]
type = "database_unique_id"

[database.identity_db]
type = "mysql"
url = "jdbc:mysql://mysql:3306/WSO2_IS_DB?useSSL=false&allowPublicKeyRetrieval=true&autoReconnect=true"
username = "wso2carbon"
password = "wso2carbon"
driver = "com.mysql.cj.jdbc.Driver"

[database.shared_db]
type = "mysql"
url = "jdbc:mysql://mysql:3306/WSO2_IS_SHARED_DB?useSSL=false&allowPublicKeyRetrieval=true&autoReconnect=true"
username = "wso2carbon"
password = "wso2carbon"
driver = "com.mysql.cj.jdbc.Driver"

[keystore.primary]
file_name = "wso2carbon.p12"
password = "wso2carbon"
type = "PKCS12"

[truststore]
file_name = "client-truststore.p12"
password = "wso2carbon"
type = "PKCS12"
```

**Event Listeners** (Selective Enablement):
- `scim2`: Enabled (priority 93) - SCIM 2.0 user provisioning
- `governance_identity_store`: Enabled (priority 97) - Identity data store
- `mutual_tls_authenticator`: Enabled (priority 5) - mTLS authentication
- `basic_auth_client_authenticator`: Enabled (priority 10) - Basic auth
- `user_deletion`: Enabled (priority 98) - User deletion events
- `consent_mgt_handler`: Enabled (priority 100) - Consent management
- `user_session_termination`: Enabled (priority 99) - Session termination

**Note**: Most other event listeners are disabled to reduce overhead and prevent conflicts.

### API Manager Configuration

**File**: `conf/apim/repository/conf/deployment.toml`

**Critical Settings**:

```toml
[server]
hostname = "localhost"
server_role = "default"

[super_admin]
username = "admin"
password = "admin"
create_admin_account = true

[user_store]
type = "database_unique_id"

[database.apim_db]
type = "mysql"
url = "jdbc:mysql://mysql:3306/WSO2AM_DB?useSSL=false&allowPublicKeyRetrieval=true&autoReconnect=true"
username = "wso2carbon"
password = "wso2carbon"
driver = "com.mysql.cj.jdbc.Driver"

[database.shared_db]
type = "mysql"
url = "jdbc:mysql://mysql:3306/WSO2AM_SHARED_DB?useSSL=false&allowPublicKeyRetrieval=true&autoReconnect=true"
username = "wso2carbon"
password = "wso2carbon"
driver = "com.mysql.cj.jdbc.Driver"

[keystore.tls]
file_name = "wso2carbon.jks"
type = "JKS"
password = "wso2carbon"
alias = "wso2carbon"
key_password = "wso2carbon"
```

**API Gateway Configuration**:
```toml
[apim]
gateway_type = "Regular,APK,AWS,Azure,Kong,Envoy"

[[apim.gateway.environment]]
name = "Default"
type = "hybrid"
gateway_type = "Regular"
http_endpoint = "http://localhost:8280"
https_endpoint = "https://localhost:8243"
```

**Key Manager Settings**:
```toml
[apim.key_manager]
enable_lightweight_apikey_generation = true
```

**CORS Configuration**:
```toml
[apim.cors]
allow_origins = "*"
allow_methods = ["GET","PUT","POST","DELETE","PATCH","OPTIONS"]
allow_headers = ["authorization","Access-Control-Allow-Origin","Content-Type","SOAPAction","apikey","Internal-Key"]
allow_credentials = false
```

**OAuth Configuration**:
```toml
[apim.oauth_config]
enable_outbound_auth_header = true

[oauth.grant_type.token_exchange]
enable = true
allow_refresh_tokens = true
iat_validity_period = "1h"
```

**Token Revocation Event Listener**:
```toml
[[event_listener]]
id = "token_revocation"
type = "org.wso2.carbon.identity.core.handler.AbstractIdentityHandler"
name = "org.wso2.is.notification.ApimOauthEventInterceptor"
order = 1
[event_listener.properties]
notification_endpoint = "https://localhost:9443/internal/data/v1/notify"
username = "admin"
password = "admin"
'header.X-WSO2-KEY-MANAGER' = "default"
```

---

## Security Setup

### Keystores & Truststores

#### Identity Server (PKCS12 format)
- **Primary Keystore**: `wso2carbon.p12`
  - Type: PKCS12
  - Password: wso2carbon
  - Location: `conf/is-as-km/repository/resources/security/`
  
- **Truststore**: `client-truststore.p12`
  - Type: PKCS12
  - Password: wso2carbon
  - Location: `conf/is-as-km/repository/resources/security/`

#### API Manager (JKS format)
- **TLS Keystore**: `wso2carbon.jks`
  - Type: JKS
  - Password: wso2carbon
  - Alias: wso2carbon
  - Location: `conf/apim/repository/resources/security/`
  
- **Truststore**: `client-truststore.jks`
  - Type: JKS
  - Password: wso2carbon
  - Location: `conf/apim/repository/resources/security/`

### Authentication Credentials

**Default Admin Credentials**:
- Username: `admin`
- Password: `admin`

**Database User**:
- Username: `wso2carbon`
- Password: `wso2carbon`

**MySQL Root**:
- Password: `root`

> ⚠️ **Security Warning**: These are default credentials for development. **MUST be changed for production deployments**.

---

## Key Manager Integration

### Architecture

The WSO2 Identity Server is configured as a **Key Manager** for the API Manager. This provides:

1. **Centralized OAuth2/OIDC Server**: All token operations handled by IS
2. **User Authentication**: IS manages user authentication and sessions
3. **Token Generation & Validation**: IS generates and validates access tokens
4. **Token Revocation**: Real-time token revocation notifications from IS to APIM

### Integration Points

#### 1. Token Revocation Flow

```
┌──────────────┐                    ┌──────────────┐
│ Identity     │  Token Revocation  │ API Manager  │
│ Server       │───────────────────►│              │
│ (IS-AS-KM)   │  Notification      │              │
└──────────────┘                    └──────────────┘
   (Port 9444)                         (Port 9443)
```

**Event Listener in APIM**:
- Endpoint: `https://localhost:9443/internal/data/v1/notify`
- Header: `X-WSO2-KEY-MANAGER: default`
- Triggers: User/Application deletions, token revocations

#### 2. Shared User Store

Both IS and APIM share the same user store via their respective shared databases:
- Users created in IS are accessible in APIM
- Claims and user attributes are synchronized
- Account locking status is shared via `accountLocked` claim

#### 3. Key Manager Extensions

**Dropins** (Installed in IS):
- `wso2is.key.manager.core-2.0.6.jar`
  - Provides Key Manager APIs
  - Token introspection endpoints
  - DCR (Dynamic Client Registration)

- `wso2is.notification.event.handlers-2.0.6.jar`
  - Handles token revocation events
  - Notifies APIM of token lifecycle changes

**Webapps**:
- `keymanager-operations.war`
  - REST API for Key Manager operations
  - Application and subscription management
  - Scope validation

---

## Network & Ports

### Port Mappings

| Service | Internal Port | External Port | Protocol | Purpose |
|---------|--------------|---------------|----------|---------|
| **MySQL** | 3306 | 3306 | TCP | Database connections |
| **IS-AS-KM** | 9443 | 9444 | HTTPS | Management console, APIs |
| **IS-AS-KM** | 9763 | 9764 | HTTP | HTTP transport |
| **API Manager** | 9443 | 9443 | HTTPS | Publisher, DevPortal, Admin |
| **API Manager** | 8280 | 8280 | HTTP | API Gateway (HTTP) |
| **API Manager** | 8243 | 8243 | HTTPS | API Gateway (HTTPS) |

### Service URLs

#### Identity Server (Key Manager)
- **Management Console**: https://localhost:9444/carbon
- **OAuth2 Authorize**: https://localhost:9444/oauth2/authorize
- **Token Endpoint**: https://localhost:9444/oauth2/token
- **User Info**: https://localhost:9444/oauth2/userinfo
- **Health Check**: https://localhost:9444/api/health-check/v1.0/health

#### API Manager
- **Publisher Portal**: https://localhost:9443/publisher
- **Developer Portal**: https://localhost:9443/devportal
- **Admin Portal**: https://localhost:9443/admin
- **Carbon Console**: https://localhost:9443/carbon
- **API Gateway (HTTP)**: http://localhost:8280
- **API Gateway (HTTPS)**: https://localhost:8243

---

## Health Checks

### MySQL Health Check
```bash
mysqladmin ping -uroot -proot && [ -f /var/lib/mysql/initialization-complete.flag ]
```
- **Interval**: 30s
- **Timeout**: 60s
- **Retries**: 5
- **Start Period**: 80s
- **Purpose**: Ensures MySQL is ready AND all initialization scripts have executed

### IS-AS-KM Health Check
```bash
curl -k --fail https://localhost:9443/api/health-check/v1.0/health
```
- **Interval**: 10s
- **Start Period**: 180s
- **Retries**: 20
- **Purpose**: Validates IS is fully started and responsive

### API Manager Health Check
```bash
curl --fail http://localhost:9763/services/Version
```
- **Interval**: 10s
- **Start Period**: 180s
- **Retries**: 20
- **Purpose**: Validates APIM is fully started and responsive

---

## Initialization Workflow

### Startup Sequence

```
1. MySQL Container Starts
   ├─► Execute 01_create_databases.sql (Create 4 databases)
   ├─► Execute 02_wso2_is_shared_db.sql (IS shared schema)
   ├─► Execute 03_wso2_is_db.sql (IS identity schema)
   ├─► Execute 04_wso2am_shared_db.sql (APIM shared schema)
   ├─► Execute 05_wso2am_db.sql (APIM schema)
   ├─► Execute 06_fix_claim_mappings_apim.sql (Fix claims for APIM)
   ├─► Execute 07_fix_claim_mappings_is.sql (Fix claims for IS)
   ├─► Execute z_health_check.sh (Create completion flag)
   └─► Health check passes → Service: HEALTHY

2. IS-AS-KM Container Starts (waits for mysql: healthy)
   ├─► Build custom image with Key Manager extensions
   ├─► Mount deployment.toml configuration
   ├─► Mount security keystores (wso2carbon.p12, client-truststore.p12)
   ├─► Start WSO2 Identity Server
   ├─► Connect to WSO2_IS_DB and WSO2_IS_SHARED_DB
   ├─► Initialize Key Manager components
   ├─► Health check passes → Service: HEALTHY

3. API Manager Container Starts (waits for mysql + is-as-km: healthy)
   ├─► Build custom image with MySQL connector
   ├─► Mount deployment.toml configuration
   ├─► Mount security keystores (wso2carbon.jks, client-truststore.jks)
   ├─► Start WSO2 API Manager
   ├─► Connect to WSO2AM_DB and WSO2AM_SHARED_DB
   ├─► Initialize gateway, publisher, devportal components
   ├─► Register token revocation listener with IS
   ├─► Health check passes → Service: HEALTHY

4. All Services Ready
   └─► System fully operational
```

### Estimated Startup Times
- **MySQL**: ~80-90 seconds (including script execution)
- **IS-AS-KM**: ~180-200 seconds (after MySQL healthy)
- **API Manager**: ~180-200 seconds (after IS-AS-KM healthy)
- **Total**: ~6-8 minutes for full stack

---

## File Structure

```
/home/premnath/global-transfer-backend/
│
├── docker-compose.yml              # Orchestration definition
├── wso2architecture.md             # This documentation file
│
├── conf/                           # Configuration files
│   ├── mysql/
│   │   ├── conf/
│   │   │   └── my.cnf              # MySQL server config
│   │   └── scripts/                # Initialization scripts (executed in order)
│   │       ├── 01_create_databases.sql
│   │       ├── 02_wso2_is_shared_db.sql
│   │       ├── 03_wso2_is_db.sql
│   │       ├── 04_wso2am_shared_db.sql
│   │       ├── 05_wso2am_db.sql
│   │       ├── 06_fix_claim_mappings_apim.sql
│   │       ├── 07_fix_claim_mappings_is.sql
│   │       └── z_health_check.sh
│   │
│   ├── is-as-km/
│   │   └── repository/
│   │       ├── conf/
│   │       │   └── deployment.toml  # IS configuration
│   │       └── resources/security/
│   │           ├── wso2carbon.p12   # Primary keystore (PKCS12)
│   │           └── client-truststore.p12
│   │
│   └── apim/
│       └── repository/
│           ├── conf/
│           │   └── deployment.toml  # APIM configuration
│           └── resources/security/
│               ├── wso2carbon.jks   # TLS keystore (JKS)
│               └── client-truststore.jks
│
├── dockerfiles/                    # Custom Dockerfiles
│   ├── apim/
│   │   └── Dockerfile              # APIM with MySQL connector
│   │
│   └── is-as-km/
│       ├── Dockerfile              # IS with KM extensions
│       ├── dropins/                # Key Manager JARs
│       │   ├── wso2is.key.manager.core-2.0.6.jar
│       │   └── wso2is.notification.event.handlers-2.0.6.jar
│       └── webapps/
│           └── keymanager-operations.war
│
└── wso2/
    └── reposistory/components/lib/
        └── mysql-connector-j-8.0.33.jar  # MySQL JDBC driver
```

---

## Common Operations

### Starting the Stack
```bash
docker-compose up -d
```

### Viewing Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f mysql
docker-compose logs -f is-as-km
docker-compose logs -f api-manager
```

### Checking Health Status
```bash
docker-compose ps
```

### Stopping the Stack
```bash
docker-compose down
```

### Removing All Data (Clean Start)
```bash
docker-compose down -v
```

### Accessing Services via CLI

**MySQL**:
```bash
docker exec -it $(docker ps -qf "name=mysql") mysql -uroot -proot
```

**IS-AS-KM Shell**:
```bash
docker exec -it $(docker ps -qf "name=is-as-km") /bin/bash
```

**API Manager Shell**:
```bash
docker exec -it $(docker ps -qf "name=api-manager") /bin/bash
```

### Rebuilding Services
```bash
# Rebuild specific service
docker-compose build is-as-km
docker-compose build api-manager

# Rebuild all
docker-compose build
```

---

## Troubleshooting

### Common Issues

#### 1. Services Not Starting
**Check dependency health**:
```bash
docker-compose ps
```
**Solution**: Ensure MySQL is healthy before IS-AS-KM, and IS-AS-KM is healthy before API Manager

#### 2. Database Connection Errors
**Verify MySQL initialization**:
```bash
docker exec -it $(docker ps -qf "name=mysql") ls -la /var/lib/mysql/initialization-complete.flag
```
**Solution**: If flag doesn't exist, initialization scripts failed. Check MySQL logs.

#### 3. Port Conflicts
**Error**: `Bind for 0.0.0.0:9443 failed: port is already allocated`
**Solution**: Change external port mapping in docker-compose.yml or stop conflicting service

#### 4. Keystore/Truststore Errors
**Check file permissions**:
```bash
ls -l conf/is-as-km/repository/resources/security/
ls -l conf/apim/repository/resources/security/
```
**Solution**: Ensure files are readable and paths are correct in volumes

#### 5. Claim Mapping Issues
**Symptom**: Authentication fails with claim-related errors
**Solution**: Verify scripts 06 and 07 executed successfully. Check database:
```sql
USE WSO2AM_SHARED_DB;
SELECT * FROM UM_CLAIM WHERE UM_CLAIM_URI LIKE '%accountLocked%';
```

---

## Production Considerations

### Security Hardening
1. **Change Default Credentials**
   - Admin users (admin/admin)
   - Database users (wso2carbon/wso2carbon)
   - MySQL root password

2. **Enable SSL for MySQL**
   - Remove `--ssl=0` command
   - Configure SSL certificates

3. **Use Strong Keystores**
   - Generate new keystores with strong keys
   - Use organization-specific certificates

4. **Secure Secrets Management**
   - Use Docker secrets or external vaults
   - Never commit credentials to version control

### Performance Tuning
1. **MySQL Optimization**
   - Increase `max_connections` based on load
   - Configure buffer pool size
   - Enable query cache

2. **JVM Tuning**
   - Adjust heap size in Dockerfiles (-Xmx, -Xms)
   - Configure GC settings

3. **Connection Pooling**
   - Tune JDBC connection pool sizes in deployment.toml

### High Availability
1. **Database Clustering**
   - Use MySQL cluster or master-slave replication
   - Configure connection failover

2. **Load Balancing**
   - Deploy multiple APIM/IS instances
   - Use nginx or cloud load balancer

3. **Persistent Storage**
   - Use Docker volumes for data persistence
   - Backup strategies for databases and configurations

---

## Version Information

- **WSO2 API Manager**: 4.6.0
- **WSO2 Identity Server**: 7.1.0
- **MySQL**: 8.0.33
- **MySQL Connector/J**: 8.0.33
- **Key Manager Extensions**: 2.0.6

---

## References

- [WSO2 API Manager Documentation](https://apim.docs.wso2.com/en/4.6.0/)
- [WSO2 Identity Server Documentation](https://is.docs.wso2.com/en/7.1.0/)
- [WSO2 IS as Key Manager](https://apim.docs.wso2.com/en/latest/install-and-setup/setup/distributed-deployment/configure-a-third-party-key-manager/)

---

**Document Version**: 1.0  
**Last Updated**: 2025  
**Maintainer**: Global Transfer Backend Team
