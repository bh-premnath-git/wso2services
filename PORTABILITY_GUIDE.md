# 🚀 Portability Guide

## Overview

The `complete_startup.sh` and all setup scripts are designed to be **highly portable**. Here's what you need to know when moving to another system.

---

## ✅ What Works Out-of-the-Box

### 1. **Docker Compose Based**
- All services run in containers
- No host dependencies
- Works on any system with Docker

### 2. **Container Networking**
- Uses Docker internal DNS (`wso2is`, `wso2am`, `postgres`)
- No hardcoded IPs
- Works across different networks

### 3. **Localhost Access**
- External access via `localhost`
- Port mappings handle the rest
- Works on any host

### 4. **No Hardcoded Paths**
- Scripts use relative paths
- Works from any directory
- No absolute path dependencies

---

## 🔧 What to Configure (Optional)

### 1. **Environment Variables** (Already Configured)

All scripts support environment variables for customization:

```bash
# WSO2 IS Configuration
export WSO2_IS_HOST="${WSO2_IS_HOST:-wso2is}"          # Container name
export WSO2_IS_PORT="${WSO2_IS_PORT:-9443}"            # Internal port
export WSO2_IS_EXTERNAL="${WSO2_IS_EXTERNAL:-localhost:9444}"  # External access

# WSO2 AM Configuration  
export WSO2_AM_HOST="${WSO2_AM_HOST:-localhost}"       # For external calls
export WSO2_AM_PORT="${WSO2_AM_PORT:-9443}"
```

**Default values work for standard Docker setups!**

### 2. **Custom Hostnames** (If Needed)

If deploying to a server with a domain name:

```bash
# .env file or export before running
export WSO2_IS_EXTERNAL="is.yourdomain.com:9444"
export WSO2_AM_HOST="am.yourdomain.com"
```

### 3. **Different Ports** (If Needed)

Edit `docker-compose.yml` port mappings:

```yaml
wso2am:
  ports:
    - "9443:9443"  # Change left side for host port
    - "8243:8243"
```

---

## 📋 Steps to Port to Another System

### Option 1: Same Configuration (Easiest)

```bash
# 1. Copy entire directory
scp -r wso2services/ user@newserver:~/

# 2. On new server
cd ~/wso2services
./complete_startup.sh
```

**That's it!** Everything just works.

---

### Option 2: Custom Configuration

```bash
# 1. Copy directory
scp -r wso2services/ user@newserver:~/

# 2. On new server, create .env file
cat > .env << 'EOF'
WSO2_IS_EXTERNAL=is.mycompany.com:9444
WSO2_AM_HOST=am.mycompany.com
EOF

# 3. Run
./complete_startup.sh
```

---

## 🌐 Network Configurations

### Local Development (Current Setup)
```
✅ Works with: localhost
✅ Access: https://localhost:9443, https://localhost:9444
✅ No changes needed
```

### Remote Server
```
✅ Works with: server IPs or domains
✅ Access: https://your-server-ip:9443
✅ No changes needed (Docker handles it)
```

### Production with Load Balancer
```
✅ Set environment variables for external URLs
✅ Update docker-compose.yml for internal networking
✅ Scripts handle the rest
```

---

## 🔒 Security Considerations for Production

When porting to production:

### 1. **Change Default Credentials**

Edit scripts or environment:
```bash
export WSO2_ADMIN_USER="your_admin"
export WSO2_ADMIN_PASSWORD="strong_password"
```

### 2. **SSL Certificates**

Replace self-signed certificates:
```bash
# In docker-compose.yml, mount your certs
volumes:
  - ./certs/server.pem:/path/to/cert
```

### 3. **Database Passwords**

Update `docker-compose.yml`:
```yaml
environment:
  POSTGRES_PASSWORD: ${DB_PASSWORD}
```

### 4. **Network Isolation**

Use Docker networks:
```yaml
networks:
  wso2-network:
    driver: bridge
    internal: true  # For internal-only services
```

---

## ✅ Portability Checklist

Before porting to another system:

- [ ] Docker and Docker Compose installed on target
- [ ] Required ports available (9443, 9444, 8243, 5432, 6379, 8000-8006)
- [ ] Sufficient resources (8GB+ RAM recommended)
- [ ] Network connectivity between containers
- [ ] (Optional) Custom .env file for your environment

---

## 🚀 Why It's Portable

### Container-Native
- All services in containers
- No host OS dependencies
- Docker handles networking

### Configuration via Environment
- All customization via env vars
- Defaults work for 99% of cases
- Override only what you need

### Relative Paths
- No hardcoded paths
- Works from any directory
- No installation required

### Health Checks
- Scripts wait for actual readiness
- Not timing-based
- Works regardless of host speed

---

## 📝 Summary

**To port to another system:**

1. ✅ Copy directory
2. ✅ Run `./complete_startup.sh`
3. ✅ Done!

**No configuration changes needed for standard deployments!**

**Optional customization available via environment variables if needed.**

---

## 🆘 If Something Doesn't Work

Check these in order:

1. **Docker running?**
   ```bash
   docker compose ps
   ```

2. **Ports available?**
   ```bash
   netstat -tuln | grep -E '9443|9444|5432'
   ```

3. **Containers healthy?**
   ```bash
   docker compose ps
   # Look for "(healthy)" status
   ```

4. **Network connectivity?**
   ```bash
   docker compose exec wso2am ping -c 2 wso2is
   ```

5. **Logs for errors?**
   ```bash
   docker compose logs wso2am wso2is | tail -100
   ```

Most issues are resolved by simply running `./complete_startup.sh` which does a clean setup.
