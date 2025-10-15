# App Scripts Guide

## 📋 Script Overview

All scripts in `app_scripts/` directory with their purpose and usage status.

---

## ✅ **ESSENTIAL SCRIPTS** (Must Use)

### 1. **setup_is_users_roles.sh** ⭐
**Purpose:** Create users and roles in WSO2 Identity Server  
**When:** Run ONCE after WSO2 IS starts  
**Creates:**
- Users: ops_user, finance, auditor, user, app_admin
- Roles: ops_users, finance, auditor, user, app_admin
- Role assignments

**Usage:**
```bash
./app_scripts/setup_is_users_roles.sh
```

**Status:** ✅ REQUIRED - Users are in WSO2 IS, not API Manager

---

### 2. **register_apis.sh** ⭐
**Purpose:** Register all 6 microservices as APIs in WSO2 API Manager  
**When:** Run ONCE after WSO2 AM starts  
**Creates:**
- 6 APIs (forex, profile, wallet, payment, ledger, rules)
- Application: AllServicesApp
- Subscriptions to all APIs

**Usage:**
```bash
./app_scripts/register_apis.sh
```

**Status:** ✅ REQUIRED - Creates APIs and application

---

### 3. **deploy_apis_to_gateway.sh** ⭐⭐⭐
**Purpose:** Deploy APIs to Gateway (creates revisions)  
**When:** Run AFTER register_apis.sh  
**Critical:** WSO2 AM 4.x REQUIRES revisions for APIs to work

**Usage:**
```bash
./app_scripts/deploy_apis_to_gateway.sh
```

**Status:** ✅ CRITICAL - Without this, APIs return 404

---

### 4. **register_wso2is_keymanager.sh** ⭐
**Purpose:** Register WSO2 IS as external Key Manager  
**When:** Run ONCE after both WSO2 IS and WSO2 AM are ready  
**Note:** Currently registered, but key generation via API has issues

**Usage:**
```bash
./app_scripts/register_wso2is_keymanager.sh
```

**Status:** ⚠️ PARTIALLY WORKING - Key Manager registered, but application key generation needs UI

---

## ⚠️ **HELPER SCRIPTS** (Optional/Troubleshooting)

### 5. **check_keymanager.sh**
**Purpose:** Wait for and verify Key Manager is ready  
**When:** Used as health check before running other scripts

**Usage:**
```bash
./app_scripts/check_keymanager.sh
```

**Status:** 🔧 HELPER - Useful for automation

---

### 6. **configure_keymanager.sh**
**Purpose:** Original Key Manager configuration script  
**Note:** Superseded by register_wso2is_keymanager.sh

**Usage:**
```bash
./app_scripts/configure_keymanager.sh
```

**Status:** 🗑️ DEPRECATED - Use register_wso2is_keymanager.sh instead

---

### 7. **test_api_gateway.sh**
**Purpose:** Test APIs through gateway with OAuth token  
**When:** After all setup is complete

**Usage:**
```bash
./app_scripts/test_api_gateway.sh ops_user OpsUser123!
```

**Status:** 🧪 TESTING - Useful for validation

---

## ❌ **NOT WORKING / INCOMPLETE**

### 8. **setup_application_keys_with_is.sh**
**Purpose:** Automate OAuth key generation with WSO2 IS Key Manager  
**Issue:** Key mapping API has persistent conflicts

**Status:** ❌ NOT WORKING - Manual UI setup required instead

---

### 9. **fix_keymanager_integration.sh**
**Purpose:** Fix Key Manager integration issues  
**Issue:** Created OAuth client but failed at mapping step

**Status:** ❌ ABANDONED - Superseded by manual UI approach

---

### 10. **fix_wso2is_keymanager.sh**
**Purpose:** Alternative approach to fix Key Manager  
**Issue:** Configuration format mismatch with API

**Status:** ❌ NOT WORKING - API expects different schema

---

### 11. **generate_grpc.sh**
**Purpose:** Placeholder for gRPC code generation  
**Status:** 🚫 EMPTY FILE - Not implemented

---

### 12. **main.sh**
**Purpose:** Placeholder for main orchestration script  
**Status:** 🚫 EMPTY FILE - Not implemented

---

## 🎯 **Complete Setup Workflow**

### First Time Setup (Run in Order):

```bash
# 1. Start services
docker compose up -d

# 2. Wait for services (2-3 minutes)
docker compose ps

# 3. Create users in WSO2 IS
./app_scripts/setup_is_users_roles.sh

# 4. Register APIs in WSO2 AM
./app_scripts/register_apis.sh

# 5. Deploy APIs to Gateway (CRITICAL!)
./app_scripts/deploy_apis_to_gateway.sh

# 6. Register WSO2 IS as Key Manager
./app_scripts/register_wso2is_keymanager.sh

# 7. Generate Application Keys via UI
# Open: https://localhost:9443/devportal
# Login: admin/admin
# Applications → AllServicesApp → Production Keys
# Select "WSO2-IS-KeyManager" → Generate Keys

# 8. Test APIs
./app_scripts/test_api_gateway.sh ops_user OpsUser123!
```

---

## 📊 **Script Status Summary**

| Script | Status | Priority | Notes |
|--------|--------|----------|-------|
| setup_is_users_roles.sh | ✅ Working | HIGH | Creates users in WSO2 IS |
| register_apis.sh | ✅ Working | HIGH | Creates APIs & application |
| deploy_apis_to_gateway.sh | ✅ Working | CRITICAL | Required for APIs to work |
| register_wso2is_keymanager.sh | ⚠️ Partial | MEDIUM | Key Manager registered |
| check_keymanager.sh | ✅ Working | LOW | Health check helper |
| test_api_gateway.sh | ✅ Working | LOW | Testing utility |
| configure_keymanager.sh | 🗑️ Old | - | Deprecated |
| setup_application_keys_with_is.sh | ❌ Broken | - | Use UI instead |
| fix_keymanager_integration.sh | ❌ Broken | - | Abandoned |
| fix_wso2is_keymanager.sh | ❌ Broken | - | API schema issue |
| generate_grpc.sh | 🚫 Empty | - | Not implemented |
| main.sh | 🚫 Empty | - | Not implemented |

---

## 🧹 **Scripts to Keep vs Remove**

### ✅ Keep These (6 scripts):
1. `setup_is_users_roles.sh` - Creates users
2. `register_apis.sh` - Creates APIs
3. `deploy_apis_to_gateway.sh` - Deploys APIs (critical!)
4. `register_wso2is_keymanager.sh` - Registers Key Manager
5. `check_keymanager.sh` - Health check
6. `test_api_gateway.sh` - Testing

### 🗑️ Can Remove (6 scripts):
1. `configure_keymanager.sh` - Deprecated
2. `setup_application_keys_with_is.sh` - Doesn't work
3. `fix_keymanager_integration.sh` - Abandoned
4. `fix_wso2is_keymanager.sh` - Doesn't work
5. `generate_grpc.sh` - Empty
6. `main.sh` - Empty

---

## 💡 **Recommended Cleanup**

```bash
# Move broken/unused scripts to archive
mkdir -p app_scripts/archive

mv app_scripts/configure_keymanager.sh app_scripts/archive/
mv app_scripts/setup_application_keys_with_is.sh app_scripts/archive/
mv app_scripts/fix_keymanager_integration.sh app_scripts/archive/
mv app_scripts/fix_wso2is_keymanager.sh app_scripts/archive/
mv app_scripts/generate_grpc.sh app_scripts/archive/
mv app_scripts/main.sh app_scripts/archive/

# Keep only the 6 working scripts in app_scripts/
```

After cleanup, you'll have:
- **6 essential scripts** that actually work
- **6 archived scripts** for reference (if needed later)

---

## 🚀 **Quick Commands**

```bash
# Complete fresh setup
./app_scripts/setup_is_users_roles.sh && \
./app_scripts/register_apis.sh && \
./app_scripts/deploy_apis_to_gateway.sh && \
./app_scripts/register_wso2is_keymanager.sh

# Re-deploy APIs after changes
./app_scripts/deploy_apis_to_gateway.sh

# Test everything
./app_scripts/test_api_gateway.sh ops_user OpsUser123!
```

---

**Last Updated:** October 15, 2025  
**Essential Scripts:** 6/12  
**Working Scripts:** 6/12  
**Broken/Empty:** 6/12
