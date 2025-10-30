# WSO2 Scripts Command Reference

Quick reference guide for all available commands in the WSO2 toolkit scripts.

## 📜 Scripts Overview

| Script | Purpose | Line Count |
|--------|---------|------------|
| `wso2-toolkit.sh` | Complete WSO2 operations (Key Manager, Apps, Roles, Tokens) | 1,986 lines |
| `api-manager.sh` | API lifecycle management (Create, Deploy, Subscribe) | 1,040 lines |
| `wso2is-user.sh` | User management (Register, Login, Activate) | 767 lines |
| `complete-workflow-test.sh` | Automated end-to-end workflow test | 350+ lines |

---

## ✅ Command Availability Matrix

### wso2-toolkit.sh

| Category | Command | Status | Description |
|----------|---------|--------|-------------|
| **Health** | `health` | ✅ Available | Check all WSO2 components |
| **Key Manager** | `setup-key-manager` | ✅ Available | Configure WSO2 IS as KM |
| **Key Manager** | `check-km` | ✅ Available | Verify KM configuration |
| **Key Manager** | `disable-resident-km` | ✅ Available | Disable default KM |
| **Certificates** | `check-mtls` | ✅ Available | Check MTLS trust |
| **Certificates** | `fix-mtls` | ✅ Available | Auto-fix MTLS issues |
| **Certificates** | `check-ssa-jwks` | ✅ Available | Check SSA JWKS endpoint |
| **Certificates** | `fix-ssl-trust` | ✅ Available | Fix SSL trust (legacy) |
| **Certificates** | `test` | ✅ Available | Test KM integration |
| **Applications** | `create-app` | ✅ Available | Create OAuth2 app |
| **Applications** | `list-apps` | ✅ Available | List all applications |
| **Applications** | `get-app` | ✅ Available | Get app details |
| **Applications** | `get-app-keys` | ✅ Available | Get OAuth2 credentials |
| **Applications** | `delete-app` | ✅ Available | Delete application |
| **Roles** | `create-role` | ✅ Available | Create single role |
| **Roles** | `create-roles` | ✅ Available | Create default roles |
| **Roles** | `list-roles` | ✅ Available | List all roles |
| **Roles** | `delete-role` | ✅ Available | Delete role by ID |
| **Tokens** | `token:client-credentials` | ✅ Available | Client credentials grant |
| **Tokens** | `token:password` | ✅ Available | Password grant |
| **Tokens** | `token:refresh` | ✅ Available | Refresh token |
| **Tokens** | `token:code` | ✅ Available | Authorization code grant |

### api-manager.sh

| Category | Command | Status | Description |
|----------|---------|--------|-------------|
| **API Lifecycle** | `create-api` | ✅ Available | Create REST API |
| **API Lifecycle** | `list-apis` | ✅ Available | List all APIs |
| **API Lifecycle** | `publish-api` | ✅ Available | Publish API |
| **API Lifecycle** | `create-revision` | ✅ Available | Create API revision |
| **API Lifecycle** | `deploy-revision` | ✅ Available | Deploy revision to gateway |
| **API Lifecycle** | `deploy-api` | ✅ Available | Complete deployment |
| **API Lifecycle** | `quick-deploy` | ✅ Available | Create + deploy in one |
| **Subscriptions** | `subscribe` | ✅ Available | Subscribe app to API |
| **Subscriptions** | `list-subscriptions` | ✅ Available | List all subscriptions |
| **Management** | `delete-api` | ✅ Available | Delete API |

### wso2is-user.sh

| Category | Command | Status | Description |
|----------|---------|--------|-------------|
| **User Mgmt** | `register` | ✅ Available | Register new user |
| **User Mgmt** | `login` | ✅ Available | Authenticate user |
| **User Mgmt** | `activate-user` | ✅ Available | Activate user account |
| **User Mgmt** | `deactivate-user` | ✅ Available | Deactivate user account |
| **User Mgmt** | `list-users` | ✅ Available | List all users |
| **User Mgmt** | `get-user` | ✅ Available | Get user details |
| **User Mgmt** | `delete-user` | ✅ Available | Delete user |
| **User Mgmt** | `reset-password` | ✅ Available | Reset user password |

---

## 🎯 Your Requested Workflow

### ✅ All Required Commands Available

```
┌─────────────────────────────────────────────────────────────────┐
│  ✅ Key Manager Setup                                           │
│  ✅ User Roles Creation                                         │
│  ✅ MTLS Check                                                  │
│  ✅ SSA JWKS Check                                              │
│  ✅ Create Application                                          │
│  ✅ API Deployment & Revision                                   │
│  ✅ Subscription Management                                     │
│  ✅ User Registration & Activation                              │
│  ✅ User Login (Token Generation)                               │
│  ✅ API Gateway Call with User Token                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Complete Workflow Commands

### Automated (Recommended)

```bash
# Run complete automated test
./scripts/complete-workflow-test.sh
```

This executes all 8 steps automatically:
1. ✅ Health check & Key Manager setup
2. ✅ Check MTLS & SSA JWKS
3. ✅ Create user roles
4. ✅ Create & deploy API
5. ✅ Create app & subscribe
6. ✅ Register & activate user
7. ✅ Login to get token
8. ✅ Call API through gateway

### Manual Step-by-Step

```bash
# Step 1: Setup & Verification
./scripts/wso2-toolkit.sh health
./scripts/wso2-toolkit.sh setup-key-manager
./scripts/wso2-toolkit.sh check-mtls
./scripts/wso2-toolkit.sh check-ssa-jwks

# Step 2: Create Roles
./scripts/wso2-toolkit.sh create-roles

# Step 3: Create & Deploy API
./scripts/api-manager.sh create-api PaymentAPI 1.0.0 /payment http://payment-service:8003
./scripts/api-manager.sh deploy-api <API_ID>

# Step 4: Create App & Subscribe
./scripts/wso2-toolkit.sh create-app TestApp http://localhost:8080/callback
./scripts/api-manager.sh subscribe <APP_ID> <API_ID> Unlimited

# Step 5: Register & Activate User
./scripts/wso2is-user.sh register testuser Test@123 test@example.com Test User
./scripts/wso2is-user.sh activate-user testuser activate

# Step 6: Login & Get Token
./scripts/wso2is-user.sh login testuser Test@123 <CLIENT_ID> <CLIENT_SECRET>

# Step 7: Call API
curl -k -H "Authorization: Bearer <TOKEN>" https://localhost:8243/payment/health
```

---

## 📋 Command Templates

### Create Application Template
```bash
./scripts/wso2-toolkit.sh create-app \
  <APP_NAME> \
  <CALLBACK_URL> \
  [KEY_MANAGER_NAME]

# Example:
./scripts/wso2-toolkit.sh create-app \
  MyPaymentApp \
  http://localhost:8080/callback \
  WSO2IS
```

### Create & Deploy API Template
```bash
./scripts/api-manager.sh create-api \
  <API_NAME> \
  <VERSION> \
  <CONTEXT> \
  <BACKEND_URL>

# Example:
./scripts/api-manager.sh create-api \
  ForexAPI \
  1.0.0 \
  /forex \
  http://forex-service:8001
```

### Register User Template
```bash
./scripts/wso2is-user.sh register \
  <USERNAME> \
  <PASSWORD> \
  <EMAIL> \
  [FIRST_NAME] \
  [LAST_NAME]

# Example:
./scripts/wso2is-user.sh register \
  johndoe \
  Pass@123456 \
  john@example.com \
  John \
  Doe
```

### Login & Get Token Template
```bash
./scripts/wso2is-user.sh login \
  <USERNAME> \
  <PASSWORD> \
  <CLIENT_ID> \
  <CLIENT_SECRET>

# Example:
./scripts/wso2is-user.sh login \
  johndoe \
  Pass@123456 \
  abc123_CLIENT \
  xyz789_SECRET
```

### Subscribe App to API Template
```bash
./scripts/api-manager.sh subscribe \
  <APPLICATION_ID> \
  <API_ID> \
  [TIER]

# Example:
./scripts/api-manager.sh subscribe \
  12345-67890-abcdef \
  98765-43210-fedcba \
  Unlimited
```

---

## 🔍 Verification Commands

### Check Application Keys
```bash
./scripts/wso2-toolkit.sh get-app-keys <APP_ID> PRODUCTION
```

### List All Applications
```bash
./scripts/wso2-toolkit.sh list-apps
```

### List All APIs
```bash
./scripts/api-manager.sh list-apis
```

### List All Users
```bash
./scripts/wso2is-user.sh list-users
```

### List All Roles
```bash
./scripts/wso2-toolkit.sh list-roles
```

### List Subscriptions
```bash
./scripts/api-manager.sh list-subscriptions
```

### Get User Details
```bash
./scripts/wso2is-user.sh get-user <USERNAME>
```

---

## 💡 Quick Tips

### 1. Token Generation Methods

**Client Credentials (App-to-App):**
```bash
./scripts/wso2-toolkit.sh token:client-credentials <APP_NAME>
```

**Password Grant (User Login):**
```bash
./scripts/wso2-toolkit.sh token:password <USERNAME> <PASSWORD>
```

**User Login with OAuth2:**
```bash
./scripts/wso2is-user.sh login <USERNAME> <PASSWORD> <CLIENT_ID> <SECRET>
```

### 2. API Deployment Options

**Quick Deploy (All-in-One):**
```bash
./scripts/api-manager.sh quick-deploy MyAPI 1.0.0 /myapi http://backend:8080
```

**Step-by-Step:**
```bash
./scripts/api-manager.sh create-api MyAPI 1.0.0 /myapi http://backend:8080
./scripts/api-manager.sh deploy-api <API_ID>
```

### 3. Complete API Call Flow

```bash
# 1. Create API
API_ID=$(./scripts/api-manager.sh create-api TestAPI 1.0.0 /test http://service:8080 | grep -oP 'API ID: \K[^\s]+')

# 2. Deploy
./scripts/api-manager.sh deploy-api $API_ID

# 3. Create App
APP_OUTPUT=$(./scripts/wso2-toolkit.sh create-app TestApp http://localhost/callback)
APP_ID=$(echo "$APP_OUTPUT" | grep -oP 'Application ID: \K[^\s]+')
CLIENT_ID=$(echo "$APP_OUTPUT" | grep -oP 'Client ID: \K[^\s]+')
CLIENT_SECRET=$(echo "$APP_OUTPUT" | grep -oP 'Client Secret: \K[^\s]+')

# 4. Subscribe
./scripts/api-manager.sh subscribe $APP_ID $API_ID

# 5. Register & Activate User
./scripts/wso2is-user.sh register user pass email@test.com
./scripts/wso2is-user.sh activate-user user activate

# 6. Get Token
TOKEN_OUTPUT=$(./scripts/wso2is-user.sh login user pass $CLIENT_ID $CLIENT_SECRET)
TOKEN=$(echo "$TOKEN_OUTPUT" | grep -oP 'Access Token: \K[^\s]+')

# 7. Call API
curl -k -H "Authorization: Bearer $TOKEN" https://localhost:8243/test/health
```

---

## 🎨 Output Examples

### Successful Application Creation
```
========================================
  Create Application
========================================

Application Name: TestApp
Callback URL: http://localhost:8080/callback
Key Manager: WSO2IS

[✓] Application created successfully!

Application ID: 12345-67890-abcdef
Client ID: abc123_CLIENT_ID
Client Secret: xyz789_SECRET
```

### Successful User Registration
```
========================================
  Register User
========================================

[✓] User registered successfully!

User ID: 98765-43210-userid
Username: testuser
Email: test@example.com
```

### Successful API Deployment
```
========================================
  Deploy API
========================================

[✓] API published successfully!
[✓] Revision created successfully!
[✓] Revision deployed to gateway!

API is now available at:
https://localhost:8243/payment/*
```

---

## 📊 Command Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Complete Workflow Flow                        │
└─────────────────────────────────────────────────────────────────┘

    ┌──────────────────┐
    │  Health Check    │ ← wso2-toolkit.sh health
    └────────┬─────────┘
             │
    ┌────────▼─────────┐
    │  Key Manager     │ ← wso2-toolkit.sh setup-key-manager
    │  Setup           │
    └────────┬─────────┘
             │
    ┌────────▼─────────┐
    │  Check MTLS &    │ ← wso2-toolkit.sh check-mtls
    │  SSA JWKS        │ ← wso2-toolkit.sh check-ssa-jwks
    └────────┬─────────┘
             │
    ┌────────▼─────────┐
    │  Create Roles    │ ← wso2-toolkit.sh create-roles
    └────────┬─────────┘
             │
    ┌────────▼─────────┐
    │  Create API      │ ← api-manager.sh create-api
    └────────┬─────────┘
             │
    ┌────────▼─────────┐
    │  Deploy API      │ ← api-manager.sh deploy-api
    │  (Publish+       │
    │   Revision+      │
    │   Deploy)        │
    └────────┬─────────┘
             │
    ┌────────▼─────────┐
    │  Create App      │ ← wso2-toolkit.sh create-app
    └────────┬─────────┘
             │
    ┌────────▼─────────┐
    │  Subscribe       │ ← api-manager.sh subscribe
    └────────┬─────────┘
             │
    ┌────────▼─────────┐
    │  Register User   │ ← wso2is-user.sh register
    └────────┬─────────┘
             │
    ┌────────▼─────────┐
    │  Activate User   │ ← wso2is-user.sh activate-user
    └────────┬─────────┘
             │
    ┌────────▼─────────┐
    │  Login & Get     │ ← wso2is-user.sh login
    │  Token           │
    └────────┬─────────┘
             │
    ┌────────▼─────────┐
    │  Call API via    │ ← curl with Bearer token
    │  Gateway         │
    └──────────────────┘
```

---

## 🔗 Related Files

- **Main Documentation**: [README.md](README.md)
- **Workflow Guide**: [WORKFLOW_GUIDE.md](WORKFLOW_GUIDE.md)
- **TLS Setup**: [TLS-Setup.md](TLS-Setup.md)
- **Architecture**: [WSO2_Architecture.md](WSO2_Architecture.md)

---

**Last Updated:** 2025-01-30  
**Verified:** All commands tested and confirmed working
