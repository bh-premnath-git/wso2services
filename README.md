# WSO2 API Manager & Identity Server with PostgreSQL

A complete Docker-based setup for **WSO2 API Manager 4.5.0** and **WSO2 Identity Server 7.1.0**, fully integrated with **PostgreSQL 18.0**.

> **Status:** Local development / evaluation. Harden before Internet exposure.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Ports & Endpoints](#ports--endpoints)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Database Layout](#database-layout)
- [Health Checks & Verification](#health-checks--verification)
- [Troubleshooting](#troubleshooting)
- [Container Shell Access](#container-shell-access)
- [Configuration](#configuration)
- [Customization](#customization)
- [Security Notes](#security-notes)
- [Resources](#resources)
- [Version & Metadata](#version--metadata)

## 🎯 Overview

- **WSO2 API Manager 4.5.0** — Full-featured API lifecycle & gateway
- **WSO2 Identity Server 7.1.0** — Enterprise IAM (OAuth2/OIDC/SAML)
- **PostgreSQL 18.0** — Four databases (total 470 tables)
- **Automated setup** — First-run DB bootstrap + drivers
- **Operational hygiene** — Health checks, pooling, clean config

## 🏗️ Architecture

```
WSO2 API Manager 4.5.0                    WSO2 Identity Server 7.1.0
  ├── Publisher                             ├── My Account
  ├── Developer Portal                      ├── Console
  ├── API Gateway                           ├── OAuth2/SAML
  └── Management Console                    └── Management Console
         ▼                                           ▼
    apim_db (232 tables)                      identity_db (127 tables)
    shared_db (51 tables)                     shared_db_is (60 tables)
         └────────────────┬─────────────────────────┘
                          ▼
                PostgreSQL 18.0
            (4 databases, 470 tables total)
```

## ✅ Prerequisites

- **Docker** 20.10+
- **Docker Compose** 2.0+
- **RAM:** 8 GB minimum (16 GB recommended)
- **Disk:** 30 GB free
- **Ports:** Must be available (see below)

## 🌐 Ports & Endpoints

### Exposed Ports

`5432`, `8243`, `8280`, `9443`, `9444`, `9764`, `9999`, `11111`, `5005`

### WSO2 API Manager

| Interface | URL |
|-----------|-----|
| Management Console | https://localhost:9443/carbon |
| Publisher | https://localhost:9443/publisher |
| Developer Portal | https://localhost:9443/devportal |

### WSO2 Identity Server

| Interface | URL |
|-----------|-----|
| Management Console | https://localhost:9444/carbon |
| My Account | https://localhost:9444/myaccount |
| Console | https://localhost:9444/console |

### Default Credentials

- **Username:** `admin`
- **Password:** `admin`

### Container Names

- `postgres-wso2`
- `wso2am`
- `wso2is`

## 🚀 Quick Start

```bash
# 1) Start everything (foreground)
docker compose up --build

# or detached
docker compose up -d --build

# 2) Wait ~2–4 minutes for health checks to pass, then open the URLs above.

# 3) Stop
docker compose down

# (Optional) Full reset (removes volumes)
docker compose down -v
```

## 📁 Project Structure

```
wso2services/
├── docker-compose.yml
├── conf/postgres/scripts/
│   ├── 01-init-databases.sql          # 4 databases + user
│   ├── 02-shared-db-schema.sql        # APIM shared (51 tables)
│   ├── 03-apim-db-schema.sql          # APIM data (232 tables)
│   ├── 04-identity-db-schema.sql      # IS identity (127 tables)
│   └── 05-shared-db-is-schema.sql     # IS shared (60 tables)
├── wso2am/
│   ├── Dockerfile
│   ├── conf/deployment.toml           # PostgreSQL config
│   └── lib/postgresql-42.7.4.jar
└── wso2is/
    ├── Dockerfile
    ├── conf/deployment.toml           # PostgreSQL config
    └── lib/postgresql-42.7.4.jar
```

## 🗄️ Database Layout

| Database | Tables | Purpose |
|----------|--------|---------||
| **apim_db** | 232 | API Manager data |
| **shared_db** | 51 | API Manager shared (users, registry) |
| **identity_db** | 127 | Identity Server data |
| **shared_db_is** | 60 | Identity Server shared (users, registry) |

**Why separate shared DBs?**  
AM and IS have different user/registry schemas—separating avoids conflicts.

**DB user (default):** `wso2carbon` / `wso2carbon`

### Verify Databases

```bash
# List databases
docker exec postgres-wso2 psql -U postgres -c "\l"

# Count tables (example: apim_db should be 232)
docker exec postgres-wso2 psql -U wso2carbon -d apim_db -c \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';"
```

## ✅ Health Checks & Verification

### 1) Container Status

```bash
docker compose ps
# Expect: postgres-wso2=healthy, wso2am=healthy (~3m), wso2is=healthy (~3m)

2) Error-free logs
docker logs wso2am 2>&1 | grep -i ERROR | tail -20
docker logs wso2is 2>&1 | grep -i ERROR | tail -20
docker logs postgres-wso2 2>&1 | grep -i ERROR | tail -20

3) DB connectivity from app containers
docker exec wso2am nc -zv postgres 5432
docker exec wso2is nc -zv postgres 5432

4) Expected table counts
docker exec postgres-wso2 psql -U wso2carbon -d apim_db -c \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';"    # expect 232
docker exec postgres-wso2 psql -U wso2carbon -d identity_db -c \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';"    # expect 127

5) Port availability
sudo netstat -tlnp | grep -E '9443|9444|5432'

6) Web consoles reachable
curl -k https://localhost:9443/carbon/admin/login.jsp
curl -k https://localhost:9444/carbon/admin/login.jsp

7) Quick status snapshot
echo "=== Container Status ==="
docker compose ps
echo -e "\n=== Resource Usage ==="
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
echo -e "\n=== DB Connections ==="
docker exec postgres-wso2 psql -U postgres -c \
  "SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname;"

Troubleshooting

Containers not healthy

Increase JVM heap (see Adjust JVM Memory
)

Fix DB connection issues (hostnames, credentials)

Resolve port conflicts (see Ports & Endpoints
)

Wrong table counts

Init scripts may have been skipped; reset volumes:

docker compose down -v && docker compose up -d --build


Connection errors

PostgreSQL max_connections hit (default here often set ≈300)

App pool exhausted; raise pool limits (see Connection Pool
)

Container Shell Access
# WSO2 API Manager
docker exec -it wso2am bash
docker exec -it wso2am tail -f /home/wso2carbon/wso2am-4.5.0/repository/logs/wso2carbon.log

# WSO2 Identity Server
docker exec -it wso2is bash
docker exec -it wso2is tail -f /home/wso2carbon/wso2is-7.1.0/repository/logs/wso2carbon.log

# PostgreSQL (psql)
docker exec -it postgres-wso2 psql -U wso2carbon -d identity_db

Configuration
WSO2 API Manager deployment.toml
[database.apim_db]
type = "postgre"
url = "jdbc:postgresql://postgres:5432/apim_db"
username = "wso2carbon"
password = "wso2carbon"

[database.shared_db]
type = "postgre"
url = "jdbc:postgresql://postgres:5432/shared_db"
username = "wso2carbon"
password = "wso2carbon"

WSO2 Identity Server deployment.toml
[database.identity_db]
type = "postgre"
url = "jdbc:postgresql://postgres:5432/identity_db"
username = "wso2carbon"
password = "wso2carbon"

[database.shared_db]
type = "postgre"
url = "jdbc:postgresql://postgres:5432/shared_db_is"
username = "wso2carbon"
password = "wso2carbon"


JDBC driver: lib/postgresql-42.7.4.jar is copied into both products’ libs.

Customization
Change Database Password

Edit conf/postgres/scripts/01-init-databases.sql:

CREATE USER wso2carbon WITH PASSWORD 'newpassword';


Update both:

wso2am/conf/deployment.toml

wso2is/conf/deployment.toml

Rebuild/restart:

docker compose down -v && docker compose up -d --build

Adjust JVM Memory
# docker-compose.yml
wso2am:
  environment:
    - JAVA_OPTS=-Xms1024m -Xmx4096m

wso2is:
  environment:
    - JAVA_OPTS=-Xms1024m -Xmx4096m


Or with GC tuning:

environment:
  - JAVA_OPTS=-Xms2048m -Xmx4096m -XX:+UseG1GC -XX:MaxGCPauseMillis=200

Add Custom Web Apps

Place WAR under:

wso2am/deployment/server/webapps/

wso2is/deployment/server/webapps/

Uncomment COPY in the respective Dockerfile.

Rebuild:

docker compose up -d --build wso2am   # or wso2is

Connection Pool (both products)
[database.*.pool_options]
maxActive = 150
maxWait = 60000
minIdle = 10
testOnBorrow = true
validationInterval = 30000

PostgreSQL tuning
# docker-compose.yml
postgres:
  command: >
    postgres
    -c max_connections=500
    -c shared_buffers=512MB
    -c effective_cache_size=2GB

Security Notes

Change default passwords (admin/admin, DB user) before any shared environment.

TLS/Truststores: Use proper certificates and configure product truststores/keystores.

Network exposure: Keep services bound to localhost during development; restrict ports with firewall rules.

Backups: Persist DB volumes and schedule regular backups if keeping state.

Resources

WSO2 API Manager Docs — https://apim.docs.wso2.com/

WSO2 Identity Server Docs — https://is.docs.wso2.com/

PostgreSQL Docs — https://www.postgresql.org/docs/

Docker Compose — https://docs.docker.com/compose/

Version & Metadata

WSO2 APIM: 4.5.0

WSO2 IS: 7.1.0

PostgreSQL: 18.0

Last Updated: October 14, 2025