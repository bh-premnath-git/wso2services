# WSO2 API Manager - Complete Working Solution

**Date:** October 15, 2025  
**Status:** ✅ **FULLY FUNCTIONAL**

---

## ✅ What Works

### 1. **API Registration & Deployment**
- ✅ All 6 microservice APIs registered in WSO2 AM
- ✅ All APIs deployed to Gateway with revisions
- ✅ Application (AllServicesApp) created
- ✅ All APIs subscribed to application

### 2. **Authentication & API Gateway**
- ✅ OAuth2 tokens generated successfully
- ✅ All APIs accessible through Gateway (port 8243)
- ✅ Token validation working
- ✅ Subscription enforcement working

### 3. **Test Results**
```bash
Testing all APIs with authentication:
forex:   ✅ HTTP 200
profile: ✅ HTTP 200
wallet:  ✅ HTTP 200
payment: ✅ HTTP 200
ledger:  ✅ HTTP 200
rules:   ✅ HTTP 200
```

---

## 🔧 Working Configuration

### Key Manager
**Active:** Resident Key Manager (WSO2 AM's built-in)

### Application Credentials
```
Application ID: d5701bf3-8569-4c05-beff-9f8d4a9fd5b9
Application Name: AllServicesApp
Consumer Key: 0rm27ljUnlKa7Gwsz_1f7GATpT0a
Consumer Secret: RJFtTFRlpEnZ830tnZwQS6LIoH8a
Key Manager: Resident Key Manager
```

### Gateway Configuration
```
Gateway URL: https://localhost:8243
API Contexts:
  - /forex/v1/*
  - /profile/v1/*
  - /wallet/v1/*
  - /payment/v1/*
  - /ledger/v1/*
  - /rules/v1/*
```

---

## 📝 Complete Working Flow

### Step 1: Get Access Token

```bash
# Get token for application user
TOKEN=$(curl -sk -u "0rm27ljUnlKa7Gwsz_1f7GATpT0a:RJFtTFRlpEnZ830tnZwQS6LIoH8a" \
  -d "grant_type=password&username=ops_user&password=OpsUser123!" \
  https://localhost:9443/oauth2/token | jq -r '.access_token')

echo "Token: $TOKEN"
```

### Step 2: Call APIs Through Gateway

```bash
# Test Forex API
curl -k -H "Authorization: Bearer $TOKEN" \
  https://localhost:8243/forex/v1/health

# Test Profile API  
curl -k -H "Authorization: Bearer $TOKEN" \
  https://localhost:8243/profile/v1/health

# Test all APIs
for API in forex profile wallet payment ledger rules; do
  echo -n "Testing $API: "
  curl -sk -H "Authorization: Bearer $TOKEN" \
    "https://localhost:8243/${API}/v1/health" | jq -r '.status'
done
```

---

## 🐛 What Was Fixed

### Issue 1: APIs Not Deployed to Gateway ❌ → ✅
**Problem:** APIs were published but had no revisions
**Solution:** Created `deploy_apis_to_gateway.sh` script
- Creates revisions for each API
- Deploys revisions to Default gateway environment
- Handles already-deployed APIs gracefully

**Bug Found:** `((COUNT++))` fails with `set -eo pipefail` when COUNT=0
**Fix:** Changed to `COUNT=$((COUNT + 1))`

### Issue 2: Invalid URL / 404 Errors ❌ → ✅
**Problem:** Gateway returned "Invalid URL" for /forex/v1/health
**Root Cause:** APIs needed revisions to be accessible
**Solution:** Running deploy script created revisions and fixed routing

### Issue 3: Backend Port Mismatches ❌ → ✅
**Problem:** API definitions had wrong backend ports (8000 instead of actual ports)
**Correct Ports:**
```
forex-service:     8001 ✅
ledger-service:    8002 ✅
payment-service:   8003 ✅
profile-service:   8004 ✅
rule-engine:       8005 ✅
wallet-service:    8006 ✅
```

### Issue 4: WSO2-IS-KeyManager Integration ⚠️ PENDING
**Problem:** Tokens from WSO2 IS (external) return "900901 Invalid Credentials"
**Current Status:** Using Resident Key Manager (working perfectly)
**Next Steps:** See "WSO2-IS Integration" section below

---

## 📜 Scripts Created

### 1. **register_apis.sh**
Registers all 6 microservice APIs in WSO2 AM
```bash
./app_scripts/register_apis.sh
```

**What it does:**
- Creates APIs with correct backend URLs
- Publishes APIs to Developer Portal
- Creates AllServicesApp application
- Subscribes all APIs to application

### 2. **deploy_apis_to_gateway.sh** ⭐
Deploys APIs to gateway runtime (CRITICAL for WSO2 AM 4.x)
```bash
./app_scripts/deploy_apis_to_gateway.sh
```

**What it does:**
- Creates revisions for all APIs
- Deploys revisions to gateway
- Skips already-deployed APIs
- Shows gateway URLs for each API

**Output:**
```
Total APIs: 6
✅ Deployed: 6
❌ Failed: 0
```

### 3. **test_api_gateway.sh**
Tests API calls through gateway with user authentication
```bash
./app_scripts/test_api_gateway.sh ops_user OpsUser123!
```

### 4. **fix_keymanager_integration.sh**
Attempts to fix WSO2-IS-KeyManager integration (in progress)

---

## 🚀 Quick Start Guide

### Complete Setup from Scratch

```bash
# 1. Start all services
docker compose up -d

# 2. Wait for services to be healthy
./app_scripts/check_keymanager.sh

# 3. Configure Key Manager
./app_scripts/configure_keymanager.sh

# 4. Create users and roles
./app_scripts/setup_is_users_roles.sh

# 5. Register APIs in API Manager
./app_scripts/register_apis.sh

# 6. Deploy APIs to Gateway (REQUIRED!)
./app_scripts/deploy_apis_to_gateway.sh

# 7. Test the APIs
./app_scripts/test_api_gateway.sh ops_user OpsUser123!
```

### Test Individual API

```bash
# Get application credentials
APP_ID="d5701bf3-8569-4c05-beff-9f8d4a9fd5b9"
KEYS=$(curl -sk -u "admin:admin" \
  "https://localhost:9443/api/am/devportal/v3/applications/$APP_ID/keys/PRODUCTION")

CLIENT_ID=$(echo "$KEYS" | jq -r '.consumerKey')
CLIENT_SECRET=$(echo "$KEYS" | jq -r '.consumerSecret')

# Get token
TOKEN=$(curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \
  -d "grant_type=password&username=ops_user&password=OpsUser123!" \
  https://localhost:9443/oauth2/token | jq -r '.access_token')

# Call API
curl -k -H "Authorization: Bearer $TOKEN" \
  https://localhost:8243/forex/v1/health | jq '.'
```

---

## ⚠️ WSO2-IS External Key Manager Integration

### Current Status: PARTIALLY WORKING

**What Works:**
- ✅ Key Manager configuration exists
- ✅ OAuth clients can be created in WSO2 IS
- ✅ Tokens can be generated from WSO2 IS

**What Doesn't Work:**
- ❌ Tokens from WSO2 IS not validated by API Gateway
- ❌ Gateway returns "900901 Invalid Credentials"

### Root Cause Analysis

The issue is token issuer mismatch:

**WSO2 IS Token Issuer:**
```json
{
  "iss": "https://localhost:9444/oauth2/token"
}
```

**WSO2 AM Expects:**
```json
{
  "iss": "https://localhost:9443/oauth2/token"  // From Resident Key Manager
}
```

### Workaround: Use Resident Key Manager (Current Solution)

Instead of using WSO2 IS as external Key Manager, use WSO2 AM's built-in Resident Key Manager:

**Advantages:**
- ✅ Works out of the box
- ✅ JWT tokens validated correctly
- ✅ No issuer mismatch issues
- ✅ User authentication still goes through WSO2 IS (via password grant)

**Users still authenticate with WSO2 IS:**
```bash
# User credentials come from WSO2 IS
# But OAuth client is in WSO2 AM
TOKEN=$(curl -sk -u "$CLIENT:$SECRET" \
  -d "grant_type=password&username=ops_user&password=OpsUser123!" \
  https://localhost:9443/oauth2/token | jq -r '.access_token')
```

### Future: Full WSO2-IS-KeyManager Integration

To make WSO2-IS-KeyManager work, we need to:

1. **Configure JWT Issuer Mapping**
   ```bash
   # Update Key Manager to accept WSO2 IS issuer
   # Configure in WSO2 AM: Admin Portal → Key Managers
   ```

2. **Enable JWT Validation**
   ```json
   {
     "issuer": "https://localhost:9444/oauth2/token",
     "certificate": {
       "type": "JWKS",
       "value": "https://localhost:9444/oauth2/jwks"
     },
     "self_validate_jwt": true
   }
   ```

3. **Map Application Keys**
   ```bash
   # Create OAuth client in WSO2 IS
   # Map to WSO2 AM application
   ```

---

## 📊 Service Port Reference

| Service | Container | Internal Port | External Port | Backend URL |
|---------|-----------|---------------|---------------|-------------|
| Forex | forex-service | 8001 | 8001 | http://forex-service:8001 |
| Ledger | ledger-service | 8002 | 8002 | http://ledger-service:8002 |
| Payment | payment-service | 8003 | 8003 | http://payment-service:8003 |
| Profile | profile-service | 8004 | 8004 | http://profile-service:8004 |
| Rules | rule-engine-service | 8005 | 8005 | http://rule-engine-service:8005 |
| Wallet | wallet-service | 8006 | 8006 | http://wallet-service:8006 |
| WSO2 IS | wso2is | 9443 | 9444 | https://localhost:9444 |
| WSO2 AM | wso2am | 9443 | 9443 | https://localhost:9443 |
| Gateway | wso2am | 8243 | 8243 | https://localhost:8243 |

---

## 🎯 Key Learnings

1. **WSO2 AM 4.x requires API revisions** - APIs must have revisions to be accessible
2. **Bash arithmetic with set -eo pipefail** - `((i++))` exits when i=0, use `i=$((i+1))`
3. **Container DNS names** - Use container names, not service names in docker-compose
4. **Key Manager complexity** - Resident Key Manager simpler than external integration
5. **Token issuer validation** - Gateway validates JWT issuer claim strictly

---

## ✅ Success Criteria Met

- [x] All 6 microservices registered as APIs
- [x] APIs deployed to gateway
- [x] Application created with subscriptions
- [x] OAuth tokens generated successfully
- [x] All APIs accessible through gateway (HTTP 200)
- [x] Token validation working
- [x] User authentication working (ops_user)
- [x] Correct backend ports configured
- [x] Scripts are portable and reusable

---

## 📞 Support Commands

```bash
# Check API deployment status
curl -sk -u "admin:admin" \
  "https://localhost:9443/api/am/publisher/v4/apis" | \
  jq '.list[] | {name, context, version, lifeCycleStatus}'

# Check application keys
curl -sk -u "admin:admin" \
  "https://localhost:9443/api/am/devportal/v3/applications/d5701bf3-8569-4c05-beff-9f8d4a9fd5b9/keys/PRODUCTION" | \
  jq '{consumerKey, consumerSecret, keyManager}'

# Check subscriptions
curl -sk -u "admin:admin" \
  "https://localhost:9443/api/am/devportal/v3/subscriptions?applicationId=d5701bf3-8569-4c05-beff-9f8d4a9fd5b9" | \
  jq '.list[] | .apiInfo.name'

# Check API revisions
curl -sk -u "admin:admin" \
  "https://localhost:9443/api/am/publisher/v4/apis/{API_ID}/revisions" | \
  jq '.list[] | {id, deploymentInfo}'

# View logs
docker compose logs -f wso2am | grep -E "ERROR|Authentication"
```

---

**Last Updated:** October 15, 2025 09:55 UTC  
**Working Configuration:** Resident Key Manager + Password Grant  
**All APIs:** ✅ OPERATIONAL
