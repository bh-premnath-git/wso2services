# WSO2 Complete Workflow Guide

This guide demonstrates the complete end-to-end workflow for WSO2 API Manager and Identity Server integration.

## 📋 Available Commands Summary

### ✅ wso2-toolkit.sh Commands

#### Key Manager Management
- ✅ `setup-key-manager` - Configure WSO2 IS as Key Manager in APIM
- ✅ `check-km` - Verify Key Manager configuration
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
- ✅ `token:client-credentials <app_name>` - Get token via client credentials
- ✅ `token:password <username> <password>` - Get token via password grant
- ✅ `token:refresh <refresh_token>` - Refresh access token
- ✅ `token:code <code>` - Exchange authorization code for token

#### Health & Status
- ✅ `health` - Check health of all WSO2 components

### ✅ api-manager.sh Commands

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
- ✅ `list-subscriptions` - List all subscriptions

#### API Management
- ✅ `delete-api <api_id>` - Delete API

### ✅ wso2is-user.sh Commands

#### User Management
- ✅ `register <username> <password> <email> [first_name] [last_name]` - Register new user
- ✅ `login <username> <password> [client_id] [client_secret]` - Authenticate user
- ✅ `activate-user <username> [activate|deactivate]` - Activate/deactivate user
- ✅ `list-users` - List all users
- ✅ `get-user <username>` - Get user details
- ✅ `delete-user <user_id>` - Delete user
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

## 📝 Manual Step-by-Step Workflow

### Step 1: Setup & Verification

#### 1.1 Check Health
```bash
./scripts/wso2-toolkit.sh health
```

#### 1.2 Setup Key Manager
```bash
./scripts/wso2-toolkit.sh setup-key-manager
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
./scripts/api-manager.sh list-subscriptions
```

---

### Step 5: Register and Activate User

#### 5.1 Register User
```bash
./scripts/wso2is-user.sh register johndoe Pass@123456 john@example.com John Doe
```

#### 5.2 Activate User
```bash
./scripts/wso2is-user.sh activate-user johndoe activate
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
./scripts/wso2-toolkit.sh token:password johndoe Pass@123456
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

### Validate Token
```bash
# Introspect token
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
# Check subscription
./scripts/api-manager.sh list-subscriptions

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
./scripts/wso2is-user.sh activate-user johndoe activate

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
./scripts/wso2is-user.sh activate-user trader activate

# 7. Get Token
./scripts/wso2is-user.sh login trader trader123 <CLIENT_ID> <CLIENT_SECRET>

# 8. Call Forex API
curl -k -H "Authorization: Bearer <TOKEN>" \
     https://localhost:8243/forex/rates/USDINR
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
./scripts/wso2is-user.sh activate-user payuser activate
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
./scripts/wso2-toolkit.sh setup-key-manager
./scripts/wso2-toolkit.sh check-mtls
./scripts/wso2-toolkit.sh create-roles
./scripts/api-manager.sh quick-deploy MyAPI 1.0.0 /myapi http://backend:8080
./scripts/wso2-toolkit.sh create-app MyApp
./scripts/api-manager.sh subscribe <APP_ID> <API_ID>
./scripts/wso2is-user.sh register user pass email@test.com
./scripts/wso2is-user.sh activate-user user activate
./scripts/wso2is-user.sh login user pass <CLIENT_ID> <SECRET>
curl -k -H "Authorization: Bearer <TOKEN>" https://localhost:8243/myapi/
```

---

**Last Updated:** 2025-01-30  
**Version:** 1.0.0
