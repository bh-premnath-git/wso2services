# WSO2 API Manager & Identity Server with PostgreSQL

A complete Docker-based setup for **WSO2 API Manager 4.5.0** and **WSO2 Identity Server 7.1.0** fully integrated with **PostgreSQL 18.0**.

## 🎯 Overview

- **WSO2 API Manager 4.5.0**: Full-featured API management
- **WSO2 Identity Server 7.1.0**: Enterprise identity and access management  
- **PostgreSQL 18.0**: 4 databases with 470 tables total
- **Automated Setup**: Complete initialization on first startup
- **Production Ready**: Health checks, connection pooling, clean configuration

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

- Docker 20.10+
- Docker Compose 2.0+
- 8GB RAM minimum (16GB recommended)
- 30GB disk space
- Ports: 5432, 8243, 8280, 9443, 9444, 9764, 9999, 11111

## �� Quick Start

```bash
# Start all services
docker compose up -d

# Check status (wait for "healthy")
docker compose ps

# Watch logs (takes ~176 seconds to start)
docker logs wso2am -f
docker logs wso2is -f
```

### Access URLs

**WSO2 API Manager:**
- Management Console: https://localhost:9443/carbon
- API Publisher: https://localhost:9443/publisher
- Developer Portal: https://localhost:9443/devportal

**WSO2 Identity Server:**
- Management Console: https://localhost:9444/carbon
- My Account: https://localhost:9444/myaccount
- Console: https://localhost:9444/console

**Credentials:** `admin` / `admin`

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

## 🗄️ Database Setup

| Database | Tables | Purpose |
|----------|--------|---------|
| **apim_db** | 232 | API Manager data |
| **shared_db** | 51 | API Manager shared (users, registry) |
| **identity_db** | 127 | Identity Server data |
| **shared_db_is** | 60 | Identity Server shared (users, registry) |

**Why separate shared databases?**  
WSO2 AM and IS have different user management schemas. Separate databases prevent schema conflicts.

**Database user:** `wso2carbon` / `wso2carbon`

### Verify Setup

```bash
# List databases
docker exec postgres-wso2 psql -U postgres -c "\l"

# Count tables
docker exec postgres-wso2 psql -U wso2carbon -d apim_db -c \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';"
```

## 📖 Usage

```bash
# Start services
docker compose up -d

# Stop services (keeps data)
docker compose down

# Clean restart (deletes data)
docker compose down -v && docker compose up -d --build

# View logs
docker logs wso2am -f
docker logs wso2is -f
docker logs postgres-wso2 -f

# Restart specific service
docker compose restart wso2am
docker compose restart wso2is
```

## ⚙️ Configuration

### WSO2 API Manager Database Config

File: `wso2am/conf/deployment.toml`

```toml
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
```

### WSO2 Identity Server Database Config

File: `wso2is/conf/deployment.toml`

```toml
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
```

## 🎨 Customization

### Change Database Password

1. Update `conf/postgres/scripts/01-init-databases.sql`:
```sql
CREATE USER wso2carbon WITH PASSWORD 'newpassword';
```

2. Update both `wso2am/conf/deployment.toml` and `wso2is/conf/deployment.toml`

3. Rebuild:
```bash
docker compose down -v && docker compose up -d --build
```

### Adjust JVM Memory

Edit `docker-compose.yml`:

```yaml
wso2am:
  environment:
    - JAVA_OPTS=-Xms1024m -Xmx4096m

wso2is:
  environment:
    - JAVA_OPTS=-Xms1024m -Xmx4096m
```

### Add Custom Web Apps

1. Place WAR files in `wso2am/deployment/server/webapps/` or `wso2is/deployment/server/webapps/`
2. Uncomment COPY line in respective Dockerfile
3. Rebuild: `docker compose up -d --build [service]`

## 🔧 Troubleshooting

### Check Health

```bash
docker compose ps  # All should show "healthy"
```

### Common Issues

**Port conflicts:**
```bash
sudo netstat -tlnp | grep -E '9443|9444|5432'
```

**Check errors:**
```bash
docker logs wso2am 2>&1 | grep ERROR
docker logs wso2is 2>&1 | grep ERROR
```

**Database connectivity:**
```bash
docker exec wso2am nc -zv postgres 5432
docker exec wso2is nc -zv postgres 5432
```

**Clean reset:**
```bash
docker compose down -v
docker system prune -f
docker compose up -d --build
```

## 🔄 Maintenance

### Backup

```bash
# Backup all databases
docker exec postgres-wso2 pg_dumpall -U postgres > backup_$(date +%Y%m%d).sql

# Backup specific database
docker exec postgres-wso2 pg_dump -U wso2carbon apim_db > apim_db_backup.sql
docker exec postgres-wso2 pg_dump -U wso2carbon identity_db > identity_db_backup.sql
```

### Restore

```bash
docker exec -i postgres-wso2 psql -U postgres < backup_20251014.sql
```

### Monitoring

```bash
# Resource usage
docker stats

# PostgreSQL connections
docker exec postgres-wso2 psql -U postgres -c \
  "SELECT count(*) FROM pg_stat_activity;"

# Database sizes
docker exec postgres-wso2 psql -U postgres -c \
  "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database;"
```

## 🔐 Security (Production)

- [ ] Change admin passwords (both products)
- [ ] Update database passwords  
- [ ] Replace default SSL certificates
- [ ] Use secrets management
- [ ] Enable firewall rules
- [ ] Use reverse proxy for SSL termination
- [ ] Enable audit logging
- [ ] Disable sample applications

## 📊 Performance Tuning

### Connection Pool (both products)

Edit `deployment.toml`:

```toml
[database.*.pool_options]
maxActive = 150
maxWait = 60000
minIdle = 10
testOnBorrow = true
validationInterval = 30000
```

### PostgreSQL

Edit `docker-compose.yml`:

```yaml
postgres:
  command: >
    postgres 
    -c max_connections=500 
    -c shared_buffers=512MB 
    -c effective_cache_size=2GB
```

### JVM

```yaml
environment:
  - JAVA_OPTS=-Xms2048m -Xmx4096m -XX:+UseG1GC -XX:MaxGCPauseMillis=200
```

## 📚 Resources

- [WSO2 API Manager Docs](https://apim.docs.wso2.com/)
- [WSO2 Identity Server Docs](https://is.docs.wso2.com/)
- [PostgreSQL Docs](https://www.postgresql.org/docs/)
- [Docker Compose Docs](https://docs.docker.com/compose/)

## 📝 Technical Details

**Startup Time:** ~176 seconds for both products  
**Total Tables:** 470 (232 + 51 + 127 + 60)  
**JDBC Driver:** PostgreSQL 42.7.4  
**Base Images:** wso2/wso2am:4.5.0, wso2/wso2is:7.1.0, postgres:18.0  
**Network:** Bridge network (wso2-network)  
**Storage:** Named volume (postgres-data)

---

**Last Updated:** October 14, 2025  
**Version:** WSO2 APIM 4.5.0 + WSO2 IS 7.1.0 + PostgreSQL 18.0
