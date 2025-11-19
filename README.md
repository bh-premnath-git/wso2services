# Global Transfer Backend

Containerized payment and FX platform combining WSO2 identity/API layer with Python microservices, data stores, and observability tooling. This README provides a complete reference for all files and directories.

## Quick Start
1. Copy `.env` and fill secrets for SMTP, Stripe, BRMS, etc.
2. Ensure Docker/Docker Compose are installed.
3. Run `docker-compose up -d` to start all 22 services.
4. Run `./scripts/end-to-end-test.sh` to verify setup.
5. View logs: `docker-compose logs -f <service>`

## Architecture Overview
```
┌─────────────────────────────────────────────────────────────┐
│                     External Clients                        │
└──────────────────────────┬──────────────────────────────────┘
                           ▼
                ┌──────────────────────┐
                │  WSO2 API Manager    │ :9443, :8280/:8243
                │   (Gateway/Portal)   │
                └──────────┬───────────┘
                           │
            ┌──────────────┼──────────────┐
            │              │              │
            ▼              ▼              ▼
  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐
  │  WSO2 IS    │  │Microservices │  │  Data Tier   │
  │ (Key Mgr)   │  │ (8 services) │  │ MySQL/Redis  │
  │   :9444     │  │ :8001-:8007  │  │ DynamoDB/PG  │
  └─────────────┘  └──────┬───────┘  └──────────────┘
                          │
                 ┌────────┴────────┐
                 │                 │
                 ▼                 ▼
         ┌──────────────┐  ┌──────────────┐
         │   BRMS       │  │Observability │
         │  GoRules     │  │ Jaeger/OTEL  │
         │   :8181      │  │   :16686     │
         └──────────────┘  └──────────────┘
```

**Total Services**: 22 containers (WSO2: 2, Infrastructure: 5, Microservices: 8, Workers: 2, BRMS: 1, Observability: 2, Init: 2)

---

## Repository Structure

### Root Files
- **`.env`** (885 bytes) - Centralized secrets and configuration ⚠️ **Never commit**
- **`.gitignore`** - Protects `.env` from version control
- **`README.md`** - This comprehensive project documentation
- **`wso2architecture.md`** (28KB) - Detailed WSO2 APIM + IS architecture, security, OAuth2 flows
- **`docker-compose.yml`** (19KB) - Orchestrates all 22 services with health checks, networks, volumes

### Scripts Directory (`scripts/`)
- **`end-to-end-test.sh`** (29KB) - Complete E2E test (user registration → OAuth → API subscription → gateway testing)
  - 10 test steps with colored logging
  - API status table display
  - Retry logic and error handling
  - Usage: `./scripts/end-to-end-test.sh`

- **`deploy-all-apis.sh`** (5.1KB) - Deploys all 7 APIs to gateway with revisions (idempotent)
  - Usage: `./scripts/deploy-all-apis.sh`

- **`subscribe-all-apis.sh`** (2.3KB) - Bulk API subscription for test application
  - Usage: `./scripts/subscribe-all-apis.sh`

- **`exchange-certs.sh`** (6.9KB) - Certificate exchange between WSO2 IS and APIM for mutual TLS
  - Usage: `./scripts/exchange-certs.sh`

- **`wso2-toolkit.sh`** (37KB) - Swiss-army knife CLI for WSO2 management
  ```bash
  ./scripts/wso2-toolkit.sh list-users
  ./scripts/wso2-toolkit.sh create-user <username> <password> <email>
  ./scripts/wso2-toolkit.sh list-apis
  ./scripts/wso2-toolkit.sh create-app <app-name>
  ./scripts/wso2-toolkit.sh health
  ```

### App Scripts (`app_scripts/`)
- **`init_dynamodb.sh`** (3.9KB) - Seeds DynamoDB tables: `forex_rates`, `transactions`, `user_wallets`, `audit_logs`

---

## Application Services (`app_services/`)

All services are Python FastAPI-based, following pattern: `Dockerfile` + `requirements.txt` + `app/main.py`

### 1. Banking Service (Port 8007)
**Purpose**: Bank account management, Mastercard integration

**Files**:
- `app/main.py` - FastAPI application
- `app/config.py` - Environment configuration
- `app/schemas.py` - Pydantic models
- `app/api/v1/bank_accounts.py` - Account CRUD
- `app/services/mastercard_client.py` - Mastercard API client

**Endpoints**: `/health`, `/banking/v1/accounts`, `/banking/v1/accounts/{id}/balance`

### 2. Common Module
**Purpose**: Shared auth, middleware, utilities for all services

**Files**:
- `auth/wso2_client.py` - WSO2 IS client (token introspection)
- `auth/models.py` - User, Token models
- `middleware.py` - Logging, CORS, authentication
- `utils.py` - JWT validation helpers
- `exceptions.py` - Custom exceptions
- `config.py` - Common configuration

### 3. Forex Service (Port 8001)
**Purpose**: FX rates with Celery background tasks

**Files**:
- `app/main.py` - FastAPI endpoints
- `app/celery_app.py` - Celery configuration
- `app/tasks.py` - OANDA API rate fetching (periodic)

**Endpoints**: `/health`, `/rates/{from}/{to}`, `/rates/{pair}`
**Storage**: DynamoDB

### 4. Ledger Service (Port 8002)
**Purpose**: Transaction ledger, double-entry bookkeeping

**Files**: `app/main.py`

**Endpoints**: `/health`, `/ledger/v1/entries`, `/ledger/v1/balance/{account_id}`
**Storage**: DynamoDB (`transactions`)

### 5. Payment Service (Port 8003)
**Purpose**: Payment processing with pluggable adapters

**Files**:
- `app/main.py` - Payment endpoints
- `adapters/base.py` - Abstract adapter
- `adapters/manager.py` - Adapter factory
- `adapters/stripe/__init__.py` - Stripe integration
- `adapters/custom/__init__.py` - Custom payment logic

**Endpoints**: `/health`, `/payment/v1/charge`, `/payment/v1/refund`, `/payment/v1/status/{id}`

### 6. Profile Service (Port 8004)
**Purpose**: User profiles, email verification, KYC tracking

**Files**:
- `app/main.py` - Profile/auth endpoints
- `app/email_service.py` - SMTP email sending
- `app/models/kyc.py` - KYC status enum
- `app/config.py` - SMTP configuration

**Endpoints**: 
- Registration: `/register`, `/verify-email`, `/resend-verification-email`
- Auth: `/auth/login`, `/auth/userinfo`, `/auth/refresh`, `/auth/reset-password`
- Profile: `/auth/profile/{username}` (GET/PATCH)

**Storage**: DynamoDB (`user_profiles`)

### 7. Rule Engine Service (Port 8005)
**Purpose**: Business rules evaluation via GoRules BRMS

**Files**:
- `app/main.py` - Rule endpoints
- `rules/risk_assessment.json` - Risk scoring rules
- `rules/transaction_rules.json` - Transaction business logic
- `rules/trans.json` - Validation rules
- `test_rules.py` - Unit tests

**Endpoints**: `/health`, `/rules/v1/evaluate`, `/rules/v1/transaction`, `/rules/v1/risk`

### 8. Wallet Service (Port 8006)
**Purpose**: Digital wallet management

**Files**: `app/main.py`

**Endpoints**: `/health`, `/wallet/v1/create`, `/wallet/v1/balance/{user_id}`, `/wallet/v1/deposit`, `/wallet/v1/withdraw`, `/wallet/v1/transfer`
**Storage**: DynamoDB (`user_wallets`)

---

## Configuration (`conf/`)

### APIM Configuration (`conf/apim/`)
```
repository/
├── conf/
│   └── deployment.toml          # Main APIM config (DB, gateway, Key Manager)
└── resources/security/
    ├── wso2carbon.jks           # APIM keystore
    └── client-truststore.jks    # APIM truststore
```

### IS Configuration (`conf/is-as-km/`)
```
repository/
├── conf/
│   └── deployment.toml          # Main IS config (DB, SCIM2, OAuth2)
└── resources/security/
    ├── wso2carbon.p12           # IS keystore
    └── client-truststore.p12    # IS truststore
```

### MySQL Configuration (`conf/mysql/`)
```
conf/
└── my.cnf                       # MySQL server settings
scripts/
├── 01_create_databases.sql      # Creates WSO2_SHARED_DB, WSO2AM_DB, WSO2_IS_DB
├── 02_wso2_is_shared_db.sql     # IS shared schema
├── 03_wso2_is_db.sql            # IS schema
├── 04_wso2am_shared_db.sql      # APIM shared schema
├── 05_wso2am_db.sql             # APIM schema
├── 06_fix_claim_mappings_apim.sql
├── 07_fix_claim_mappings_is.sql
└── z_health_check.sh            # DB health verification
```

---

## Dockerfiles (`dockerfiles/`)

### APIM Dockerfile (`dockerfiles/apim/`)
- Base: `wso2/wso2am:4.6.0`
- Adds: MySQL connector JAR
- Mounts: Custom `deployment.toml`, keystores

### IS Dockerfile (`dockerfiles/is-as-km/`)
- Base: `wso2/wso2is:7.1.0`
- Adds: 
  - `dropins/wso2is.key.manager.core-2.0.6.jar` - Key Manager core
  - `dropins/wso2is.notification.event.handlers-2.0.6.jar` - Event handlers
  - `webapps/keymanager-operations.war` - Key Manager web app
  - MySQL connector JAR
- Mounts: Custom `deployment.toml`, keystores

---

## WSO2 Dependencies (`wso2/`)
- **`repository/components/lib/mysql-connector-j-8.0.33.jar`** - MySQL JDBC driver for IS and APIM

---

## OpenTelemetry (`otel/`)
- **`Dockerfile`** - Custom OTEL Collector image
- **`collector.yaml`** - Collector configuration
  - Receivers: OTLP (gRPC :4317, HTTP :4318)
  - Exporters: Jaeger (:14250), Prometheus (:8889), Logging

---

## Environment Variables (`.env`)

| Category | Variables | Purpose |
|----------|-----------|---------|
| **Database** | `MYSQL_ROOT_PASSWORD` | MySQL root access |
| **Email** | `SMTP_HOST`, `SMTP_PORT`, `SENDER_EMAIL`, `SENDER_PASSWORD` | Email notifications |
| **Forex** | `OANDA_API_BASE`, `OANDA_API_KEY` | Exchange rate data |
| **Payments** | `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET` | Stripe integration |
| **BRMS** | `BRMS_DB_USER`, `BRMS_DB_PASSWORD`, `BRMS_LICENSE_KEY`, `BRMS_TOKEN`, `BRMS_ENABLED`, `BRMS_URL`, `BRMS_PROJECT_ID` | Business rules engine |
| **Redis** | `REDIS_PASSWORD` | Cache/broker auth |
| **KYC** | `COMPLYCUBE_API_KEY` | Identity verification |
| **Banking** | `MASTERCARD_API_KEY` | Banking integration |

---

## Service Ports

| Service | Internal | External | Protocol |
|---------|----------|----------|----------|
| WSO2 IS | 9443 | 9444 | HTTPS |
| WSO2 APIM | 9443 | 9443 | HTTPS |
| APIM Gateway | 8280/8243 | 8280/8243 | HTTP/HTTPS |
| MySQL | 3306 | 3306 | TCP |
| Redis | 6379 | 6379 | TCP |
| Redpanda | 9092/19092 | 9092/19092 | Kafka |
| DynamoDB | 8000 | 8000 | HTTP |
| PostgreSQL | 5432 | 5432 | TCP |
| BRMS | 8080 | 8181 | HTTP |
| Jaeger UI | 16686 | 16686 | HTTP |
| OTEL Collector | 4317/4318 | 4317/4318 | gRPC/HTTP |
| Forex Service | 8001 | 8001 | HTTP |
| Ledger Service | 8002 | 8002 | HTTP |
| Payment Service | 8003 | 8003 | HTTP |
| Profile Service | 8004 | 8004 | HTTP |
| Rule Engine | 8005 | 8005 | HTTP |
| Wallet Service | 8006 | 8006 | HTTP |
| Banking Service | 8007 | 8007 | HTTP |

---

## Common Commands

```bash
# Start all services
docker-compose up -d

# Check service health
./scripts/wso2-toolkit.sh health

# Run E2E test (full workflow)
./scripts/end-to-end-test.sh

# Deploy APIs to gateway
./scripts/deploy-all-apis.sh

# Subscribe to all APIs
./scripts/subscribe-all-apis.sh

# View service logs
docker-compose logs -f <service-name>

# Restart a service
docker-compose restart <service-name>

# Stop all services
docker-compose down

# Remove all data (DESTRUCTIVE)
docker-compose down -v
```

---

## Documentation References

- **`wso2architecture.md`** - Comprehensive WSO2 architecture, security, troubleshooting
- **`scripts/end-to-end-test.sh`** - Comments explain each test step
- **Service READMEs** - `app_services/rule_engine_service/README.md`

---

**Maintained by**: Development Team  
**Last Updated**: November 2025