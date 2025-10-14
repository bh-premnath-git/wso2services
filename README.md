# WSO2 API Manager with PostgreSQL

A complete Docker-based setup for WSO2 API Manager 4.5.0 integrated with PostgreSQL 18.0 database.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Configuration](#configuration)
- [Database Setup](#database-setup)
- [Usage](#usage)
- [Endpoints](#endpoints)
- [Customization](#customization)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)
- [Security Considerations](#security-considerations)

## 🎯 Overview

This project provides a production-ready setup of WSO2 API Manager with PostgreSQL as the database backend. It uses Docker Compose for orchestration and includes:

- **WSO2 API Manager 4.5.0**: Full-featured API management platform
- **PostgreSQL 18.0**: High-performance relational database
- **Automated Database Initialization**: Database schemas automatically created on startup
- **Health Checks**: Container health monitoring for reliable deployments
- **Custom Configuration**: Easy-to-modify deployment configuration

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     WSO2 API Manager                        │
│  ┌─────────────┬──────────────┬────────────────────────┐   │
│  │  Publisher  │  Dev Portal  │  Management Console    │   │
│  └─────────────┴──────────────┴────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              API Gateway (HTTP/HTTPS)                │   │
│  └──────────────────────────────────────────────────────┘   │
│                         ▼                                    │
│  ┌──────────────────────────────────────────────────────┐   │
│  │        PostgreSQL JDBC Connection                    │   │
│  └──────────────────────────────────────────────────────┘   │
└──────────────────────────┬──────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    PostgreSQL 18.0                          │
│  ┌─────────────────────┬────────────────────────────────┐   │
│  │    shared_db        │        apim_db                 │   │
│  │  (User Management   │   (API Management Data)        │   │
│  │   & Registry)       │                                │   │
│  │   51 tables         │      232 tables                │   │
│  └─────────────────────┴────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## ✅ Prerequisites

- **Docker**: Version 20.10 or higher
- **Docker Compose**: Version 2.0 or higher
- **System Requirements**:
  - Minimum 4GB RAM (8GB recommended)
  - 20GB free disk space
  - Ports available: 5432, 8243, 8280, 9443, 9999, 11111

## 🚀 Quick Start

### 1. Start Services

```bash
docker compose up -d
```

This will:
- Pull required Docker images
- Build custom WSO2 API Manager image with PostgreSQL integration
- Create and initialize PostgreSQL databases (51 + 232 tables)
- Start both services with health checks

### 2. Wait for Services to Start

```bash
# Check container status
docker compose ps

# Watch WSO2 startup logs (wait for "WSO2 Carbon started in XX sec")
docker logs wso2am -f
```

### 3. Access the Portals

- **Management Console**: https://localhost:9443/carbon
- **API Publisher**: https://localhost:9443/publisher
- **Developer Portal**: https://localhost:9443/devportal

**Default Credentials**:
- Username: `admin`
- Password: `admin`

## 📁 Project Structure

```
wso2services/
├── docker-compose.yml              # Service orchestration
├── README.md                       # This file
│
├── conf/                           # Configuration files
│   └── postgres/
│       └── scripts/                # Database initialization scripts
│           ├── 01-init-databases.sql      # Creates databases and users
│           ├── 02-shared-db-schema.sql    # User management & registry (51 tables)
│           └── 03-apim-db-schema.sql      # API management (232 tables)
│
└── wso2am/                         # WSO2 API Manager customization
    ├── Dockerfile                  # Custom Docker build
    ├── conf/
    │   └── deployment.toml         # PostgreSQL database configuration
    ├── lib/
    │   └── postgresql-42.7.4.jar  # PostgreSQL JDBC driver
    └── deployment/
        └── server/
            └── webapps/            # Place custom WAR files here
                └── .gitkeep
```

## ⚙️ Configuration

### Docker Compose Services

#### PostgreSQL Service

- **Image**: postgres:18.0
- **Databases**: `apim_db`, `shared_db`
- **User**: `wso2carbon` / `wso2carbon`
- **Port**: 5432
- **Max Connections**: 300
- **Auto-initialization**: SQL scripts in `conf/postgres/scripts/`

#### WSO2 API Manager Service

- **Base Image**: wso2/wso2am:4.5.0
- **Custom Build**: Includes PostgreSQL JDBC driver and configuration
- **JVM Memory**: 512MB min, 2GB max
- **Depends On**: PostgreSQL (waits for healthy status)

### Key Configuration File: deployment.toml

Location: `wso2am/conf/deployment.toml`

```toml
[database.apim_db]
type = "postgre"
url = "jdbc:postgresql://postgres:5432/apim_db"
username = "wso2carbon"
password = "wso2carbon"
driver = "org.postgresql.Driver"

[database.shared_db]
type = "postgre"
url = "jdbc:postgresql://postgres:5432/shared_db"
username = "wso2carbon"
password = "wso2carbon"
driver = "org.postgresql.Driver"
```

## 🗄️ Database Setup

### Databases Created

1. **shared_db**: User management, registry, and governance
   - 51 tables including user stores, permissions, registry metadata
   
2. **apim_db**: API management runtime data
   - 232 tables for APIs, applications, subscriptions, throttling, analytics

### Initialization Process

Scripts execute automatically in alphabetical order during first PostgreSQL startup:

1. `01-init-databases.sql`: Creates databases, user `wso2carbon`, and grants permissions
2. `02-shared-db-schema.sql`: Creates shared database schema (51 tables)
3. `03-apim-db-schema.sql`: Creates API Manager schema (232 tables)

### Verify Database Tables

```bash
# Check shared_db tables
docker exec postgres-wso2 psql -U wso2carbon -d shared_db -c "\dt"

# Check apim_db tables  
docker exec postgres-wso2 psql -U wso2carbon -d apim_db -c "\dt"

# Count tables
docker exec postgres-wso2 psql -U wso2carbon -d apim_db -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';"
```

## 📖 Usage

### Starting Services

```bash
# Start in detached mode
docker compose up -d

# Start with build (after config changes)
docker compose up -d --build

# Start with logs in foreground
docker compose up
```

### Stopping Services

```bash
# Stop services (keeps data)
docker compose stop

# Stop and remove containers (keeps data)
docker compose down

# Stop and remove everything including volumes (DELETES DATA)
docker compose down -v
```

### Viewing Logs

```bash
# View WSO2 logs
docker logs wso2am -f

# View PostgreSQL logs
docker logs postgres-wso2 -f

# View last 100 lines
docker logs wso2am --tail 100

# Check for errors
docker logs wso2am 2>&1 | grep ERROR
```

### Restarting Services

```bash
# Restart all services
docker compose restart

# Restart specific service
docker compose restart wso2am
```

## 🌐 Endpoints

### Management Interfaces

| Interface | URL | Description |
|-----------|-----|-------------|
| Management Console | https://localhost:9443/carbon | Admin console for system configuration |
| API Publisher | https://localhost:9443/publisher | Create, publish, and manage APIs |
| Developer Portal | https://localhost:9443/devportal | Discover and subscribe to APIs |

### API Gateway

| Type | URL | Description |
|------|-----|-------------|
| HTTP | http://localhost:8280 | Non-SSL API traffic |
| HTTPS | https://localhost:8243 | SSL-secured API traffic |

### Monitoring

| Interface | Port | Description |
|-----------|------|-------------|
| JMX RMI Registry | 9999 | Java Management Extensions |
| JMX RMI Server | 11111 | JMX remote monitoring |
| PostgreSQL | 5432 | Database connection |

## 🎨 Customization

### Modifying WSO2 Configuration

1. Edit `wso2am/conf/deployment.toml`
2. Rebuild and restart:
   ```bash
   docker compose up -d --build
   ```

### Adding Custom Web Applications

1. Place your WAR files in `wso2am/deployment/server/webapps/`
2. Uncomment line 10 in `wso2am/Dockerfile`:
   ```dockerfile
   COPY --chown=wso2carbon:wso2 deployment/server/webapps/*.war /home/wso2carbon/wso2am-4.5.0/repository/deployment/server/webapps/
   ```
3. Rebuild:
   ```bash
   docker compose up -d --build
   ```

### Changing Database Passwords

**Important**: Update in both locations:

1. `conf/postgres/scripts/01-init-databases.sql`:
   ```sql
   CREATE USER wso2carbon WITH PASSWORD 'your_new_password';
   ```

2. `wso2am/conf/deployment.toml`:
   ```toml
   [database.apim_db]
   password = "your_new_password"
   
   [database.shared_db]
   password = "your_new_password"
   ```

3. Clean rebuild:
   ```bash
   docker compose down -v
   docker compose up -d --build
   ```

### Adjusting JVM Memory

Edit `docker-compose.yml`:

```yaml
environment:
  - JAVA_OPTS=-Xms1024m -Xmx4096m  # 1GB min, 4GB max
```

## 🔧 Troubleshooting

### Check Container Health

```bash
docker compose ps
```

Both containers should show: `Up X minutes (healthy)`

### Common Issues

#### Port Conflicts

If ports are already in use:

```bash
# Check what's using the ports
sudo netstat -tlnp | grep -E '5432|9443|8280|8243'

# Or modify ports in docker-compose.yml
ports:
  - "9444:9443"  # Use 9444 instead of 9443
```

#### WSO2 Won't Start

```bash
# Check logs for errors
docker logs wso2am 2>&1 | grep ERROR

# Verify PostgreSQL is healthy
docker inspect postgres-wso2 --format='{{.State.Health.Status}}'

# Check database connectivity
docker exec wso2am nc -zv postgres 5432
```

#### Database Connection Errors

```bash
# Verify databases exist
docker exec postgres-wso2 psql -U postgres -c "\l"

# Check user permissions
docker exec postgres-wso2 psql -U wso2carbon -d apim_db -c "SELECT 1"

# Verify tables were created
docker exec postgres-wso2 psql -U wso2carbon -d apim_db -c "\dt" | head -20
```

#### Out of Memory

Reduce JVM memory in `docker-compose.yml`:

```yaml
environment:
  - JAVA_OPTS=-Xms256m -Xmx1024m  # For low-memory systems
```

### Clean Reset

If you need to start completely fresh:

```bash
# Stop and remove everything
docker compose down -v

# Remove build cache
docker system prune -f

# Remove old image
docker rmi wso2services-wso2am

# Rebuild from scratch
docker compose up -d --build
```

## 🔄 Maintenance

### Backing Up PostgreSQL Data

```bash
# Backup all databases
docker exec postgres-wso2 pg_dumpall -U postgres > backup_$(date +%Y%m%d).sql

# Backup specific database
docker exec postgres-wso2 pg_dump -U wso2carbon apim_db > apim_db_backup.sql
```

### Restoring Database

```bash
# Restore all databases
docker exec -i postgres-wso2 psql -U postgres < backup_20251014.sql

# Restore specific database
docker exec -i postgres-wso2 psql -U wso2carbon apim_db < apim_db_backup.sql
```

### Monitoring

```bash
# View resource usage
docker stats

# Check PostgreSQL connections
docker exec postgres-wso2 psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"

# Monitor container health
watch -n 5 'docker compose ps'
```

### Updating WSO2 Version

1. Update `wso2am/Dockerfile`:
   ```dockerfile
   FROM wso2/wso2am:4.6.0  # New version
   ```

2. Update paths if version directory changed:
   ```dockerfile
   COPY --chown=wso2carbon:wso2 lib/postgresql-42.7.4.jar /home/wso2carbon/wso2am-4.6.0/repository/components/lib/
   COPY --chown=wso2carbon:wso2 conf/deployment.toml /home/wso2carbon/wso2am-4.6.0/repository/conf/deployment.toml
   ```

3. Rebuild:
   ```bash
   docker compose up -d --build
   ```

## 🔐 Security Considerations

### Production Checklist

- [ ] Change default admin password via Management Console
- [ ] Update database passwords in `deployment.toml` and SQL scripts
- [ ] Change PostgreSQL admin password
- [ ] Replace default SSL certificates
- [ ] Use secrets management (Docker secrets, Vault, etc.)
- [ ] Enable firewall rules
- [ ] Use reverse proxy (nginx, traefik) for SSL termination
- [ ] Implement network isolation
- [ ] Enable audit logging
- [ ] Regular security updates

### Network Security

For production, isolate the network:

```yaml
networks:
  wso2-network:
    driver: bridge
    internal: true  # No external access
```

Expose only necessary ports via reverse proxy.

### SSL/TLS Certificates

Replace default keystores:

```yaml
volumes:
  - ./certs/wso2carbon.jks:/home/wso2carbon/wso2am-4.5.0/repository/resources/security/wso2carbon.jks
```

## 📊 Performance Tuning

### Database Connection Pool

Edit `wso2am/conf/deployment.toml`:

```toml
[database.apim_db.pool_options]
maxActive = 150        # Maximum connections
maxWait = 60000        # Wait time (ms)
minIdle = 10           # Minimum idle connections
testOnBorrow = true    # Validate before use
validationInterval = 30000
```

### PostgreSQL Tuning

Edit `docker-compose.yml`:

```yaml
command: postgres -c max_connections=500 -c shared_buffers=512MB -c effective_cache_size=2GB
```

### JVM Tuning

```yaml
environment:
  - JAVA_OPTS=-Xms2048m -Xmx4096m -XX:+UseG1GC -XX:MaxGCPauseMillis=200
```

## 📚 Additional Resources

- [WSO2 API Manager Documentation](https://apim.docs.wso2.com/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [WSO2 Community](https://wso2.com/community/)
- [WSO2 Docker GitHub](https://github.com/wso2/docker-apim)

## 📝 Notes

- **Startup Time**: First startup takes ~60-90 seconds as databases are initialized
- **Data Persistence**: PostgreSQL data persists in named volume `postgres-data`
- **Configuration**: Only `deployment.toml` is customized; all other configs from base image
- **Health Checks**: Containers marked healthy when services are responsive
- **Startup Order**: PostgreSQL starts first, WSO2 waits for healthy status

## 🐛 Known Issues

- Certificate expiration warning for Baltimore CyberTrust Root (non-critical)
- Template directory warnings (expected, no impact)
- Default credentials warnings (change in production)

---

**Version**: WSO2 API Manager 4.5.0 with PostgreSQL 18.0  
**Last Updated**: October 14, 2025  
**Startup Time**: ~71 seconds  
**Database Tables**: 283 (51 shared + 232 API management)
