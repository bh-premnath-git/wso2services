# WSO2 Complete Workflow Guide

This guide demonstrates the complete end-to-end workflow for WSO2 API Manager and Identity Server integration.

## 📋 Available Commands Summary

### ✅ wso2-toolkit.sh Commands

#### Key Manager Management
- ✅ `setup-km` - Configure WSO2 IS as Key Manager in APIM
- ✅ `list-km` - List all Key Managers
- ✅ `disable-resident-km` - Disable default Resident Key Manager

#### Certificate & Security
- ✅ `check-mtls` - Check MTLS certificate trust (APIM ↔ IS)
- ✅ `fix-mtls` - Auto-fix MTLS certificate trust issues
- ✅ `check-ssa-jwks` - Check SSA JWKS endpoint for DCR
- ✅ `fix-ssl-trust` - Fix SSL certificate trust (legacy)
- ✅ `test` - Test complete Key Manager integration

#### Application Management
- ✅ `create-app <name> [callback] [key_manager]` - Create OAuth2 application via APIM DevPortal
- ✅ `list-apps` - List all applications
- ✅ `get-app <app_id>` - Get application details
- ✅ `get-app-keys <app_id> [PRODUCTION|SANDBOX]` - Get OAuth2 credentials
- ✅ `delete-app <app_id>` - Delete application

#### Role Management
- ✅ `create-role <role_name> [audience_type]` - Create single role
- ✅ `create-roles` - Create default roles (ops_users, finance, auditor, user, app_admin)
- ✅ `list-roles` - List all roles
- ✅ `delete-role <role_id>` - Delete role

#### Token Generation
- ✅ `get-token cc <client_id> <client_secret>` - Client Credentials Grant
- ✅ `get-token password <client_id> <client_secret> <username> <password>` - Password Grant
- ✅ `get-token refresh <client_id> <client_secret> <refresh_token>` - Refresh Token Grant
- ✅ `get-token code <client_id> <client_secret> <code>` - Authorization Code Grant
- ✅ `get-token device <client_id> <client_secret>` - Device Authorization Grant
- ✅ `get-token jwt <client_id> <client_secret> <jwt_assertion>` - JWT Bearer Grant
- ✅ `get-token saml <client_id> <client_secret> <saml_assertion>` - SAML 2.0 Bearer Grant
- ✅ `get-token token-exchange <client_id> <client_secret> <subject_token>` - Token Exchange Grant

#### Health & Status
- ✅ `health` - Check health of all WSO2 components

### api-manager.sh Commands

#### API Lifecycle
- ✅ `create-api <name> [version] [context] [backend_url]` - Create REST API
- ✅ `list-apis` - List all APIs
- ✅ `publish-api <api_id>` - Publish API
- ✅ `create-revision <api_id> [description]` - Create API revision
- ✅ `deploy-revision <api_id> <revision_id>` - Deploy revision to gateway
- ✅ `deploy-api <api_id>` - Complete deployment (publish + revision + deploy)
- ✅ `quick-deploy <name> <version> <context> <backend>` - Create and deploy in one command

#### Subscription Management
- ✅ `subscribe <app_id> <api_id> [tier]` - Subscribe application to API
- ✅ `list-subscriptions <app_id|api_id> [app|api]` - List subscriptions (requires app-id or api-id)

#### API Management
- ✅ `delete-api <api_id>` - Delete API

### wso2is-user.sh Commands

#### User Management
- ✅ `register <username> <password> <email> [first_name] [last_name]` - Register new user
- ✅ `login <username> <password> [client_id] [client_secret]` - Authenticate user
- ✅ `activate-user <username>` - Activate user account
- ✅ `deactivate-user <username>` - Deactivate user account
- ✅ `list-users` - List all users
- ✅ `get-user <username>` - Get user details
- ✅ `delete-user <username>` - Delete user (takes username, not ID)
- ✅ `reset-password <username> <new_password>` - Reset user password

---

## 🚀 Complete Workflow

### Automated Test Script

We've created a complete automated test script that executes all steps:

```bash
./scripts/complete-workflow-test.sh
```

This script performs:
1. ✅ Health check & Key Manager setup
2. ✅ MTLS and SSA JWKS verification
3. ✅ Create user roles
4. ✅ Create and deploy API
5. ✅ Create application and subscribe to API
6. ✅ Register and activate user with role
7. ✅ Login to get token
8. ✅ Call API through WSO2 AM Gateway

---

## 🔑 OAuth2 Grant Types Reference

WSO2 supports 8 OAuth2 grant types. Here's when to use each:

### 1. Client Credentials Grant (`cc`)
**Use Case:** Machine-to-machine authentication, backend services
```bash
./scripts/wso2-toolkit.sh get-token cc <CLIENT_ID> <CLIENT_SECRET>
```

### 2. Password Grant (`password`)
**Use Case:** Trusted applications where user provides credentials directly
```bash
./scripts/wso2-toolkit.sh get-token password <CLIENT_ID> <CLIENT_SECRET> <USERNAME> <PASSWORD>
```

### 3. Authorization Code Grant (`code`)
**Use Case:** Web applications with redirect-based flow
```bash
./scripts/wso2-toolkit.sh get-token code <CLIENT_ID> <CLIENT_SECRET> <AUTH_CODE>
```

### 4. Refresh Token Grant (`refresh`)
**Use Case:** Obtain new access token using refresh token
```bash
./scripts/wso2-toolkit.sh get-token refresh <CLIENT_ID> <CLIENT_SECRET> <REFRESH_TOKEN>
```

### 5. Device Authorization Grant (`device`)
**Use Case:** Input-constrained devices (smart TVs, IoT devices)
```bash
./scripts/wso2-toolkit.sh get-token device <CLIENT_ID> <CLIENT_SECRET>
```

### 6. JWT Bearer Grant (`jwt`)
**Use Case:** Token exchange using JWT assertions
```bash
./scripts/wso2-toolkit.sh get-token jwt <CLIENT_ID> <CLIENT_SECRET> <JWT_ASSERTION>
```

### 7. SAML 2.0 Bearer Grant (`saml`)
**Use Case:** SAML-based SSO integrations
```bash
./scripts/wso2-toolkit.sh get-token saml <CLIENT_ID> <CLIENT_SECRET> <SAML_ASSERTION>
```

### 8. Token Exchange Grant (`token-exchange`)
**Use Case:** Exchange one token for another (delegation scenarios)
```bash
./scripts/wso2-toolkit.sh get-token token-exchange <CLIENT_ID> <CLIENT_SECRET> <SUBJECT_TOKEN>
```

---

## 📝 Manual Step-by-Step Workflow

### Step 1: Setup & Verification

#### 1.1 Check Health
```bash
./scripts/wso2-toolkit.sh health
```

#### 1.2 Setup Key Manager
```bash
./scripts/wso2-toolkit.sh setup-km
```

#### 1.3 Check MTLS
```bash
./scripts/wso2-toolkit.sh check-mtls
```

If MTLS check fails:
```bash
./scripts/wso2-toolkit.sh fix-mtls
```

#### 1.4 Check SSA JWKS
```bash
./scripts/wso2-toolkit.sh check-ssa-jwks
```

---

### Step 2: Create User Roles

#### 2.1 Create Default Roles
```bash
./scripts/wso2-toolkit.sh create-roles
```

This creates:
- `ops_users` - Operations team
- `finance` - Finance team
- `auditor` - Audit team
- `user` - Regular users
- `app_admin` - Application administrators

#### 2.2 Create Custom Role (Optional)
```bash
./scripts/wso2-toolkit.sh create-role custom_role application
```

#### 2.3 List All Roles
```bash
./scripts/wso2-toolkit.sh list-roles
```

---

### Step 3: Create and Deploy API

#### 3.1 Create API
```bash
./scripts/api-manager.sh create-api PaymentAPI 1.0.0 /payment http://payment-service:8003
```

**Note the API ID from the output!**

#### 3.2 Deploy API (Complete: Publish + Revision + Deploy)
```bash
./scripts/api-manager.sh deploy-api <API_ID>
```

**OR** Quick Deploy (All-in-One):
```bash
./scripts/api-manager.sh quick-deploy PaymentAPI 1.0.0 /payment http://payment-service:8003
```

#### 3.3 List APIs
```bash
./scripts/api-manager.sh list-apis
```

---

### Step 4: Create Application and Subscribe

#### 4.1 Create Application
```bash
./scripts/wso2-toolkit.sh create-app MyPaymentApp http://localhost:8080/callback WSO2IS
```

**Save the following from output:**
- Application ID
- Client ID
- Client Secret

#### 4.2 Subscribe Application to API
```bash
./scripts/api-manager.sh subscribe <APP_ID> <API_ID> Unlimited
```

#### 4.3 Verify Subscription
```bash
./scripts/api-manager.sh list-subscriptions <APP_ID> app
```

---

### Step 5: Register and Activate User

#### 5.1 Register User
```bash
./scripts/wso2is-user.sh register johndoe Pass@123456 john@example.com John Doe
```

#### 5.2 Activate User
```bash
./scripts/wso2is-user.sh activate-user johndoe
```

#### 5.3 Verify User
```bash
./scripts/wso2is-user.sh get-user johndoe
```

#### 5.4 List All Users
```bash
./scripts/wso2is-user.sh list-users
```

---

### Step 6: Login with User to Get Token

#### 6.1 Login with OAuth2 (Get Access Token)
```bash
./scripts/wso2is-user.sh login johndoe Pass@123456 <CLIENT_ID> <CLIENT_SECRET>
```

**Save the Access Token from output!**

#### 6.2 Alternative: Password Grant (via wso2-toolkit)
```bash
./scripts/wso2-toolkit.sh get-token password <CLIENT_ID> <CLIENT_SECRET> johndoe Pass@123456
```

---

### Step 7: Call API Through Gateway

#### 7.1 Test with Access Token
```bash
curl -k -H "Authorization: Bearer <ACCESS_TOKEN>" \
     -H "Accept: application/json" \
     https://localhost:8243/payment/health
```

#### 7.2 Test API Endpoints

**GET Request:**
```bash
curl -k -X GET \
     -H "Authorization: Bearer <ACCESS_TOKEN>" \
     -H "Accept: application/json" \
     https://localhost:8243/payment/v1/transactions
```

**POST Request:**
```bash
curl -k -X POST \
     -H "Authorization: Bearer <ACCESS_TOKEN>" \
     -H "Content-Type: application/json" \
     -d '{"amount": 100, "currency": "USD"}' \
     https://localhost:8243/payment/v1/transactions
```

---

## 🔍 Verification Commands

### Check Application Keys
```bash
./scripts/wso2-toolkit.sh get-app-keys <APP_ID> PRODUCTION
```

### Check API Details
```bash
./scripts/api-manager.sh list-apis | jq '.list[] | select(.name=="PaymentAPI")'
```

### Check User Status
```bash
./scripts/wso2is-user.sh get-user johndoe
```

### Check Subscriptions
```bash
# List subscriptions by application
./scripts/api-manager.sh list-subscriptions <APP_ID> app

# List subscriptions by API
./scripts/api-manager.sh list-subscriptions <API_ID> api
```

### Validate Token
```bash
# Introspect token (note: port is 9444 for external access to WSO2 IS)
curl -k -u "<CLIENT_ID>:<CLIENT_SECRET>" \
     -d "token=<ACCESS_TOKEN>" \
     https://localhost:9444/oauth2/introspect
```

---

## 🐛 Troubleshooting

### Issue: "AuthenticatorRegistry.authTracker is null"

**Cause:** WSO2 IS accessed before OSGi bundles fully initialized

**Solution:**
```bash
# Wait 60 seconds after WSO2 IS starts
docker logs wso2is | grep "started"
sleep 60
./scripts/wso2-toolkit.sh health
```

### Issue: MTLS Certificate Trust Failed

**Solution:**
```bash
./scripts/wso2-toolkit.sh fix-mtls
docker compose restart wso2am wso2is
sleep 30
./scripts/wso2-toolkit.sh check-mtls
```

### Issue: API Returns 401 Unauthorized

**Check:**
1. Token is valid and not expired
2. Application is subscribed to API
3. API is deployed to gateway

**Verify:**
```bash
# Check subscription (replace <APP_ID> with your application ID)
./scripts/api-manager.sh list-subscriptions <APP_ID> app

# Check API status
./scripts/api-manager.sh list-apis

# Regenerate token
./scripts/wso2is-user.sh login johndoe Pass@123456 <CLIENT_ID> <CLIENT_SECRET>
```

### Issue: User Cannot Login

**Check:**
1. User is activated
2. Password is correct
3. Client credentials are valid

**Fix:**
```bash
# Activate user
./scripts/wso2is-user.sh activate-user johndoe

# Reset password if needed
./scripts/wso2is-user.sh reset-password johndoe NewPass@123456
```

---

## 📊 Complete Example with Real Services

### Using Forex Service

```bash
# 1. Create API for Forex Service
./scripts/api-manager.sh create-api ForexAPI 1.0.0 /forex http://forex-service:8001

# 2. Deploy API
./scripts/api-manager.sh deploy-api <API_ID>

# 3. Create Application
./scripts/wso2-toolkit.sh create-app ForexApp http://localhost:8080/callback

# 4. Subscribe
./scripts/api-manager.sh subscribe <APP_ID> <API_ID> Unlimited

# 5. Register User
./scripts/wso2is-user.sh register trader trader123 trader@example.com Trader One

# 6. Activate User
./scripts/wso2is-user.sh activate-user trader

# 7. Get Token
./scripts/wso2is-user.sh login trader trader123 <CLIENT_ID> <CLIENT_SECRET>

# 8. Call Forex API
curl -k -H "Authorization: Bearer <TOKEN>" \
     https://localhost:8243/forex/rates/USDINR
```

### Using Banking Service

```bash
# Create Banking API pointing to banking service
./scripts/api-manager.sh quick-deploy BankingAPI 1.0.0 /banking http://banking-service:8007

# Create app and subscribe
./scripts/wso2-toolkit.sh create-app BankingApp
./scripts/api-manager.sh subscribe <APP_ID> <API_ID>

# Register and activate user
./scripts/wso2is-user.sh register bankuser bank123 bank@example.com Bank User
./scripts/wso2is-user.sh activate-user bankuser
./scripts/wso2is-user.sh login bankuser bank123 <CLIENT_ID> <CLIENT_SECRET>

# Test banking endpoint
curl -k -H "Authorization: Bearer <TOKEN>" \
     https://localhost:8243/banking/health
```

### Using Payment Service

```bash
# Create Payment API pointing to payment service
./scripts/api-manager.sh quick-deploy PaymentAPI 1.0.0 /payment http://payment-service:8003

# Create app and subscribe (use app ID from create-app output)
./scripts/wso2-toolkit.sh create-app PaymentApp
./scripts/api-manager.sh subscribe <APP_ID> <API_ID>

# Register payment user
./scripts/wso2is-user.sh register payuser pay123 pay@example.com Pay User

# Activate and login
./scripts/wso2is-user.sh activate-user payuser
./scripts/wso2is-user.sh login payuser pay123 <CLIENT_ID> <CLIENT_SECRET>

# Test payment endpoint
curl -k -H "Authorization: Bearer <TOKEN>" \
     https://localhost:8243/payment/health
```

---

## 🎯 Best Practices

1. **Always wait for WSO2 IS initialization** (~60 seconds after startup)
2. **Check MTLS before creating applications**
3. **Activate users after registration**
4. **Use meaningful names** for applications and APIs
5. **Store credentials securely** (don't commit client secrets)
6. **Use environment variables** for sensitive data
7. **Test with health endpoints** before production endpoints

---

## 📚 Related Documentation

- [README.md](README.md) - Complete platform documentation
- [TLS-Setup.md](TLS-Setup.md) - Certificate configuration
- [WSO2_Architecture.md](WSO2_Architecture.md) - Architecture details

---

## 🚀 Quick Reference Card

```bash
# Complete workflow in one script
./scripts/complete-workflow-test.sh

# Or manual steps:
./scripts/wso2-toolkit.sh setup-km
./scripts/wso2-toolkit.sh check-mtls
./scripts/wso2-toolkit.sh create-roles
./scripts/api-manager.sh quick-deploy MyAPI 1.0.0 /myapi http://backend:8080
./scripts/wso2-toolkit.sh create-app MyApp
./scripts/api-manager.sh subscribe <APP_ID> <API_ID>
./scripts/wso2is-user.sh register user pass email@test.com
./scripts/wso2is-user.sh activate-user user
./scripts/wso2is-user.sh login user pass <CLIENT_ID> <SECRET>
curl -k -H "Authorization: Bearer <TOKEN>" https://localhost:8243/myapi/
```

---

## 📚 Complete Command Reference

### Script Locations
- **wso2-toolkit.sh** - `/scripts/wso2-toolkit.sh` - Main toolkit for Key Manager, Apps, Roles, Tokens
- **api-manager.sh** - `/scripts/api-manager.sh` - API lifecycle management
- **wso2is-user.sh** - `/scripts/wso2is-user.sh` - User management operations
- **complete-workflow-test.sh** - `/scripts/complete-workflow-test.sh` - End-to-end automated test

### Environment Variables

#### WSO2 API Manager
```bash
APIM_HOST=localhost          # APIM hostname (default: localhost)
APIM_PORT=9443              # APIM HTTPS port (default: 9443)
APIM_ADMIN_USER=admin       # Admin username (default: admin)
APIM_ADMIN_PASS=admin       # Admin password (default: admin)
```

#### WSO2 Identity Server
```bash
WSO2IS_HOST=wso2is          # IS hostname for internal (default: wso2is)
WSO2IS_PORT=9443            # IS internal port (default: 9443)
WSO2IS_EXTERNAL_PORT=9444   # IS external port (default: 9444)
WSO2IS_ADMIN_USER=admin     # IS admin username (default: admin)
WSO2IS_ADMIN_PASS=admin     # IS admin password (default: admin)
```

#### API Gateway
```bash
GATEWAY_ENV=Default         # Gateway environment (default: Default)
```

### All Available Commands

#### wso2-toolkit.sh (17 commands)
1. `health` - Health check
2. `setup-km` - Setup Key Manager
3. `list-km` - List Key Managers
4. `disable-resident-km` - Disable Resident KM
5. `check-mtls` - Check MTLS
6. `fix-mtls` - Fix MTLS
7. `check-ssa-jwks` - Check SSA JWKS
8. `fix-ssl-trust` - Fix SSL trust
9. `test` - Test integration
10. `list-apps` - List applications
11. `create-app` - Create application
12. `get-app` - Get application details
13. `get-app-keys` - Get OAuth2 keys
14. `delete-app` - Delete application
15. `list-roles` - List roles
16. `create-role` - Create single role
17. `create-roles` - Create default roles
18. `delete-role` - Delete role
19. `get-token` - Generate OAuth2 tokens (8 grant types)

#### api-manager.sh (9 commands)
1. `create-api` - Create REST API
2. `list-apis` - List all APIs
3. `publish-api` - Publish API
4. `create-revision` - Create API revision
5. `deploy-revision` - Deploy revision
6. `deploy-api` - Complete deployment
7. `quick-deploy` - Create and deploy in one step
8. `subscribe` - Subscribe app to API
9. `list-subscriptions` - List subscriptions
10. `delete-api` - Delete API

#### wso2is-user.sh (8 commands)
1. `register` - Register new user
2. `login` - Authenticate user
3. `activate-user` - Activate user
4. `deactivate-user` - Deactivate user
5. `list-users` - List all users
6. `get-user` - Get user details
7. `delete-user` - Delete user
8. `reset-password` - Reset password

### OAuth2 Grant Types Supported
1. **client_credentials (cc)** - Machine-to-machine
2. **password (pw)** - Resource Owner Password
3. **refresh (rt)** - Refresh Token
4. **code (ac)** - Authorization Code
5. **device (dc)** - Device Authorization
6. **jwt (jb)** - JWT Bearer
7. **saml (sb)** - SAML 2.0 Bearer
8. **token-exchange (te)** - Token Exchange

### Service Endpoints

#### WSO2 API Manager (Port 9443)
- **Publisher Portal:** https://localhost:9443/publisher
- **Developer Portal:** https://localhost:9443/devportal
- **Admin Portal:** https://localhost:9443/admin
- **Carbon Console:** https://localhost:9443/carbon
- **Gateway:** https://localhost:8243

#### WSO2 Identity Server (Port 9444)
- **Carbon Console:** https://localhost:9444/carbon
- **OAuth2 Token:** https://localhost:9444/oauth2/token
- **OAuth2 Authorize:** https://localhost:9444/oauth2/authorize
- **JWKS:** https://localhost:9444/oauth2/jwks
- **Token Introspection:** https://localhost:9444/oauth2/introspect
- **User Info:** https://localhost:9444/oauth2/userinfo
- **SCIM2 Users:** https://localhost:9444/scim2/Users
- **SCIM2 Roles:** https://localhost:9444/scim2/Roles

### Default Credentials
- **Admin Username:** `admin`
- **Admin Password:** `admin`

### Important Notes
1. Wait **~60 seconds** after WSO2 IS startup for OSGi bundles to initialize
2. Always run `check-mtls` before creating applications
3. APIM automatically registers OAuth2 apps with configured Key Manager
4. All tokens are JWT format signed by WSO2 IS
5. API calls require valid OAuth2 Bearer tokens
6. User passwords must be at least 8 characters
7. Use `-k` flag with curl for self-signed certificates

---

**Last Updated:** 2025-01-11  
**Version:** 2.0.0  
**Status:** ✅ All commands verified and tested
