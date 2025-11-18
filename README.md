# Global Transfer Backend

Containerized payment and FX platform that combines a WSO2 identity/API layer with Python microservices, data stores, and observability tooling. For deep WSO2 specifics see `wso2architecture.md`; this README provides the concise whole-project view.

## Quick Start
1. Copy `.env` (see variables below) and fill secrets for SMTP, Stripe, BRMS, etc.
2. Ensure Docker/Docker Compose are installed.
3. Run `docker-compose up -d` to start **all** services (WSO2 stack, data tier, observability, microservices).
4. Use `docker-compose logs -f <service>` for troubleshooting; health-check endpoints are defined per service.

## Repository Layout
| Path | Description |
| --- | --- |
| `.env` | Centralized credentials/API keys (ignored via `.gitignore`). |
| `.gitignore` | Ignores `.env` to protect secrets. |
| `README.md` | This high-level project summary. |
| `wso2architecture.md` | Detailed architecture doc for APIM + IS stack. |
| `docker-compose.yml` | Orchestrates every container (WSO2, infra, microservices, observability). |
| `conf/` | Mounted config for MySQL + WSO2 components. |
| `dockerfiles/` | Custom Dockerfiles for APIM and IS-as-KM. |
| `wso2/` | WSO2 dependency artifacts (e.g., MySQL connector). |
| `app_scripts/` | Utility scripts (e.g., DynamoDB initialization). |
| `app_services/` | Source for all Python services (forex, ledger, payment, profile, rule-engine, wallet, banking, Celery workers/beat). |
| `otel/` | OpenTelemetry Collector configuration. |
| `app_services/**/Dockerfile` | Service-specific build instructions referenced by compose. |

## Service Topology (docker-compose)
* **Core WSO2 Layer**
  * `mysql` – shared DB backend using `.env` credentials and `conf/mysql` init scripts.
  * `is-as-km` – WSO2 Identity Server 7.1.0 acting as Key Manager (see `dockerfiles/is-as-km` + `conf/is-as-km`).
  * `api-manager` – WSO2 APIM 4.6.0 gateway/publisher/devportal (see `dockerfiles/apim` + `conf/apim`).
* **Data & Messaging**
  * `redis` (auth-protected), `redpanda` (Kafka-compatible), `dynamodb-local` + `dynamodb-init`, `pg-database` + `brms` (GoRules BRMS), `jaeger`, `otel-collector`.
* **Application Services (`app_services`)**
  * Stateless APIs: `forex-service`, `ledger-service`, `payment-service`, `profile-service`, `rule-engine-service`, `wallet-service`, `banking-service`.
  * Background workers: `fx-worker`, `fx-beat` (Celery) plus shared BRMS/WSO2 integrations.
* **Observability & Networking**
  * All services join `payment-network` bridge with custom aliases (e.g., `am.local`, `km.local`).
  * OTEL exporter endpoints pre-configured in environment blocks.

Refer to `wso2architecture.md` for diagrams and exhaustive description of the APIM/IS segment, databases, and security.

## Environment Variables (`.env`)
The following keys must be defined before running Compose (values shown here are placeholders/defaults):

```
MYSQL_ROOT_PASSWORD
SMTP_HOST
SMTP_PORT
SENDER_EMAIL
SENDER_PASSWORD
OANDA_API_BASE
OANDA_API_KEY
STRIPE_SECRET_KEY
STRIPE_PUBLISHABLE_KEY
STRIPE_WEBHOOK_SECRET
BRMS_DB_USER
BRMS_DB_PASSWORD
BRMS_DB_NAME
BRMS_LICENSE_KEY
BRMS_TOKEN
SMTP_HOST / PORT / credentials
AWS + Redis overrides (optional)
COMPLYCUBE_*, MASTERCARD_* (profile/banking services)
BRMS_ENABLED, BRMS_URL, BRMS_PROJECT_ID (rule engine integration)
```

> **Tip:** keep `.env` out of version control (already covered in `.gitignore`).

## Additional Documentation & Scripts
* `wso2architecture.md` – authoritative source for WSO2 deployment details.
* `app_scripts/init_dynamodb.sh` – seeds DynamoDB tables for local testing.
* `otel/collector.yaml` – modifies telemetry pipeline (Jaeger exporter, metrics endpoints).
* `conf/mysql/scripts/*.sql` – schema and data fixes for IS/APIM databases (run automatically).

Keep the README synchronized with new services/configs whenever `docker-compose.yml`, `.env`, or `wso2architecture.md` change.