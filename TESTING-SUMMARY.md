# WSO2 Testing Scripts - Summary

## 📁 What We Have

### 1. `E2E-TEST-GUIDE.md`
- **Purpose:** Documentation for end-to-end testing
- **Content:** Manual testing steps, architecture overview, troubleshooting
- **Status:** ✅ Keep - Good reference documentation

### 2. `scripts/end-to-end-test.sh`
- **Purpose:** Automated complete E2E test
- **Current State:** Tests User → OAuth → APIM App → Subscribe → Test
- **Missing:** API Registration (registers backend services as APIs in APIM)
- **Action:** ✏️ UPDATE to add API registration steps

## 🎯 What `end-to-end-test.sh` SHOULD Do

### Complete Flow:

```
1. ✅ Wait for Services (WSO2 IS + APIM healthy)
2. ✅ Register Test User (SCIM2 in WSO2 IS)
3. ✅ Create OAuth App (DCR in WSO2 IS)
4. ✅ Get User Token (Password grant)

   ⬇️ ADD THESE STEPS ⬇️
5. ➕ Register Profile Service API in APIM
6. ➕ Publish Profile Service API  
7. ➕ Register Forex Service API in APIM
8. ➕ Publish Forex Service API
   ⬆️ NEW STEPS ⬆️

9. ✅ Create APIM Application (DevPortal)
10. ✅ Generate App Keys (Consumer Key/Secret)
11. ✅ Subscribe to Profile API
12. ✅ Subscribe to Forex API
13. ✅ Get Gateway Token
14. ✅ Test Profile API through Gateway
15. ✅ Test Forex API through Gateway
```

## 🔧 What Needs to Be Updated

### `scripts/end-to-end-test.sh`

**Add after STEP 4 (get_oauth_token):**

```bash
# STEP 5: Register Profile API
register_profile_api() {
    # POST to /api/am/publisher/v4/apis
    # Define: name, version, context, backend URL
}

# STEP 6: Publish Profile API
publish_profile_api() {
    # POST to /api/am/publisher/v4/apis/change-lifecycle
}

# STEP 7: Register Forex API
register_forex_api() {
    # Similar to profile
}

# STEP 8: Publish Forex API  
publish_forex_api() {
    # Similar to profile
}
```

**Update step numbers:**
- Current STEP 5 (create_apim_application) → STEP 9
- Current STEP 6 (generate_app_keys) → STEP 10
- Current STEP 7 (list_available_apis) → Can remove (redundant)
- Current STEP 8 (subscribe_to_api) → STEP 11 & 12 (one per API)
- Current STEP 9 (test_api_call) → STEP 13 (get token) + 14-15 (test APIs)

## 📝 Key Points

### Backend Service URLs (Docker Internal Network)
```bash
PROFILE_SERVICE_URL="http://profile-service:8001"
FOREX_SERVICE_URL="http://forex-service:8002"
BANKING_SERVICE_URL="http://banking-service:8003"
```

### Gateway URLs (External Access)
```bash
# Profile API
https://localhost:8243/profile/v1/health

# Forex API
https://localhost:8243/forex/v1/health
```

### API Registration Format
```json
{
  "name": "ProfileServiceAPI",
  "version": "1.0.0",
  "context": "/profile/v1",
  "transport": ["http", "https"],
  "endpointConfig": {
    "endpoint_type": "http",
    "production_endpoints": {
      "url": "http://profile-service:8001"
    }
  },
  "operations": [
    {
      "target": "/health",
      "verb": "GET"
    }
  ]
}
```

## ✅ Action Plan

1. ✏️ **Update** `scripts/end-to-end-test.sh`:
   - Add API registration functions (Steps 5-8)
   - Renumber existing steps (9-15)
   - Update main() to call new functions
   - Add backend service URLs configuration

2. 📝 **Update** `E2E-TEST-GUIDE.md`:
   - Add section about API registration
   - Update step numbers to match script
   - Add backend service URL examples

3. 🗑️ **Delete** any duplicate files:
   - ~~scripts/full-e2e-test.sh~~ ✅ Already removed

## 🎓 Why This Matters

**Before:** Script assumes APIs already exist in APIM (manual setup required)  
**After:** Script registers backend services as APIs automatically (fully automated)

This enables:
- ✅ True end-to-end automation
- ✅ Testing from scratch (fresh APIM instance)
- ✅ CI/CD integration
- ✅ Repeatable testing

## 🚀 Usage (After Update)

```bash
# One command does everything
./scripts/end-to-end-test.sh

# What it tests:
# ✓ User registration
# ✓ OAuth authentication  
# ✓ API registration in APIM
# ✓ API publishing
# ✓ Application creation
# ✓ API subscriptions
# ✓ Token generation
# ✓ API calls through gateway
```

## 📊 Success Criteria

Test passes when ALL steps succeed:
- [x] Services healthy
- [x] User registered in IS
- [x] OAuth app created
- [x] User token obtained
- [x] **Profile API registered** ← NEW
- [x] **Profile API published** ← NEW
- [x] **Forex API registered** ← NEW
- [x] **Forex API published** ← NEW
- [x] APIM app created
- [x] App keys generated
- [x] Subscribed to both APIs
- [x] Gateway token obtained
- [x] Profile API responds (200 OK)
- [x] Forex API responds (200 OK)

---

**Next Step:** Update `scripts/end-to-end-test.sh` to add API registration (Steps 5-8)
