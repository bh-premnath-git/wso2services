# WSO2 IS Key Manager Integration - Current Status

**Date:** October 15, 2025  
**Goal:** Use WSO2 IS users to authenticate and access APIs through WSO2 AM Gateway

---

## ✅ What's Working

### 1. Infrastructure
- ✅ WSO2 IS 7.1.0 running (port 9444)
- ✅ WSO2 AM 4.3.0 running (port 9443)
- ✅ All 6 microservices deployed
- ✅ All APIs registered and published
- ✅ APIs deployed to Gateway with revisions

### 2. WSO2 IS Users Created
```
ops_user  / OpsUser123!   (role: ops_users)
finance   / Finance123!   (role: finance)
auditor   / Auditor123!   (role: auditor)
user      / User1234!     (role: user)
app_admin / AppAdmin123!  (role: app_admin)
```

### 3. Key Managers Registered
- ✅ WSO2-IS-KeyManager (external)
- ✅ Resident Key Manager (built-in)

---

## ❌ What's NOT Working

### Issue: WSO2-IS-KeyManager Integration
**Status:** PARTIALLY CONFIGURED

**Problem:**
- Key Manager is registered but application key generation via API fails
- Cannot generate OAuth keys through WSO2 AM DevPortal API for WSO2-IS-KeyManager
- Manual DCR registration in WSO2 IS + mapping to APIM application has issues

**Error:**
```json
{
  "keyManager": null,
  "consumerKey": null,
  "consumerSecret": null
}
```

---

## 🔧 Current Workaround

### Using Resident Key Manager with WSO2 AM's User Store

**Limitation:** Users must exist in WSO2 AM's user store (not WSO2 IS)

```bash
# This works but uses AM's user store, not IS
CLIENT_ID="lLVetTl5sIRnuG7Luw80RBwG_tEa"
CLIENT_SECRET="oRJH0Xkt3mnjQ7HJmYOzIAHaJZYa"

# Get token (only works with admin user from AM)
TOKEN=$(curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \
  -d "grant_type=password&username=admin&password=admin" \
  https://localhost:9443/oauth2/token | jq -r '.access_token')

# Call API
curl -k -H "Authorization: Bearer $TOKEN" \
  https://localhost:8243/forex/v1/health
```

---

## 🎯 Desired Flow (Not Yet Working)

```
┌──────────┐         ┌──────────┐         ┌──────────┐         ┌────────────┐
│   User   │────────▶│ WSO2 IS  │────────▶│ WSO2 AM  │────────▶│Microservice│
│          │  login  │  (9444)  │  token  │ Gateway  │   API   │  (8001+)   │
│ops_user  │         │          │         │  (8243)  │  call   │            │
└──────────┘         └──────────┘         └──────────┘         └────────────┘
     │                     │                     │                    │
     │  1. Login           │                     │                    │
     │────────────────────▶│                     │                    │
     │                     │                     │                    │
     │  2. OAuth Token     │                     │                    │
     │◀────────────────────│                     │                    │
     │                     │                     │                    │
     │  3. API Call with Token                   │                    │
     │──────────────────────────────────────────▶│                    │
     │                     │                     │                    │
     │                     │  4. Validate Token  │                    │
     │                     │◀────────────────────│                    │
     │                     │                     │                    │
     │                     │  5. Token Valid     │                    │
     │                     │─────────────────────▶│                    │
     │                     │                     │                    │
     │                     │                     │  6. Forward Request│
     │                     │                     │───────────────────▶│
     │                     │                     │                    │
     │  7. Response        │                     │  7. Response        │
     │◀──────────────────────────────────────────◀────────────────────│
```

### Steps:
1. **User authenticates with WSO2 IS** → Gets OAuth token
2. **User calls API through Gateway** → Sends token in Authorization header
3. **Gateway validates token with WSO2 IS** → Via introspection endpoint
4. **Gateway forwards request** → To backend microservice
5. **Response returned** → Through gateway to user

---

## 🚧 Blockers

### 1. Key Generation via WSO2-IS-KeyManager
**Endpoint:** `POST /api/am/devportal/v3/applications/{appId}/generate-keys`  
**Issue:** Returns null for consumerKey/consumerSecret when keyManager="WSO2-IS-KeyManager"

**Attempted Solutions:**
- ✅ Key Manager registered correctly
- ❌ Key generation via DevPortal API fails
- ⚠️  Manual DCR + mapping has key conflict errors

### 2. Persistent Key Mapping Issues
**Issue:** `901409 - Key Mappings already exists` even after deletion attempts

**Attempted:** 
- DELETE `/applications/{appId}/keys/PRODUCTION`
- DELETE `/applications/{appId}/oauth-keys/{keyMappingId}`
- Restart WSO2 AM container

**Result:** Key mappings persist in database

---

## 📋 Scripts Created

### 1. `register_wso2is_keymanager.sh`
Registers WSO2 IS as external Key Manager in APIM

**Status:** ✅ Key Manager registered  
**Config File:** `conf/wso2am/is7-key-manager.json`

### 2. `setup_application_keys_with_is.sh`
Sets up application OAuth keys with WSO2 IS

**Status:** ❌ Fails at key mapping step

### 3. `deploy_apis_to_gateway.sh`
Deploys APIs to Gateway (working perfectly)

**Status:** ✅ All 6 APIs deployed

---

## 🔍 Diagnostic Commands

```bash
# Check Key Managers
curl -sk -u "admin:admin" \
  "https://localhost:9443/api/am/admin/v4/key-managers" | \
  jq '.list[] | {name, enabled}'

# Check Application Keys
curl -sk -u "admin:admin" \
  "https://localhost:9443/api/am/devportal/v3/applications/d5701bf3-8569-4c05-beff-9f8d4a9fd5b9/oauth-keys" | \
  jq '.'

# Test WSO2 IS Token Introspection
curl -sk -u "admin:admin" \
  -d "token=YOUR_TOKEN_HERE" \
  https://localhost:9444/oauth2/introspect | jq '.'

# Check WSO2 IS DCR Endpoint
curl -sk -u "admin:admin" \
  https://localhost:9444/api/identity/oauth2/dcr/v1.1/applications | jq '.'

# View APIM logs
docker compose logs wso2am | grep -i "error\|keymanager" | tail -50
```

---

## 💡 Recommended Next Steps

### Option 1: Manual UI Configuration (Quick Win)
1. Access WSO2 AM DevPortal: https://localhost:9443/devportal
2. Go to Applications → AllServicesApp
3. Click Production Keys
4. Select Key Manager: WSO2-IS-KeyManager
5. Click Generate Keys
6. Copy credentials and test

### Option 2: Fix Key Manager API Integration (Proper Solution)
1. Review WSO2 AM logs for Key Manager communication errors
2. Verify network connectivity between containers (wso2am ↔ wso2is)
3. Check if WSO2 IS DCR endpoint is accessible from WSO2 AM container:
   ```bash
   docker exec wso2am curl -k https://wso2is:9444/oauth2/token/.well-known/openid-configuration
   ```
4. Update Key Manager configuration if endpoint URLs are incorrect

### Option 3: Direct Token Flow (Alternative)
1. Create OAuth client directly in WSO2 IS (works ✅)
2. Users get tokens from WSO2 IS directly
3. Configure API Gateway to validate IS tokens via introspection
4. Skip the APIM DevPortal key generation entirely

---

## 📊 Test Matrix

| Component | Status | Notes |
|-----------|--------|-------|
| WSO2 IS Running | ✅ | Port 9444 |
| WSO2 AM Running | ✅ | Port 9443 |
| APIs Deployed | ✅ | 6/6 with revisions |
| IS Users Created | ✅ | 5 test users |
| Key Manager Registered | ✅ | WSO2-IS-KeyManager |
| Key Generation (Resident) | ✅ | Works |
| Key Generation (IS) | ❌ | Returns null |
| Token from IS | ⚠️  | DCR works, mapping fails |
| Gateway Validation | ❌ | Not tested (no keys) |

---

## 🎯 Success Criteria

- [ ] Users authenticate with WSO2 IS (ops_user, finance, etc.)
- [ ] OAuth tokens issued by WSO2 IS
- [ ] Tokens validated by API Gateway via WSO2 IS introspection
- [ ] All 6 APIs accessible with IS tokens
- [ ] No Resident Key Manager dependency

---

## 📝 Configuration Files

- **Key Manager Config:** `conf/wso2am/is7-key-manager.json`
- **Registration Script:** `app_scripts/register_wso2is_keymanager.sh`
- **Setup Script:** `app_scripts/setup_application_keys_with_is.sh`
- **Deploy Script:** `app_scripts/deploy_apis_to_gateway.sh` ✅

---

**Last Updated:** October 15, 2025 10:25 UTC  
**Status:** WSO2 IS registered as Key Manager, but application key generation not working via API
