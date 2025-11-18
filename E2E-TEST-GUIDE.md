# End-to-End Integration Test Guide

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         User/Client Application                      │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │   WSO2 Identity Server │  Port 9444
              │      (Authentication)  │
              └───────────┬────────────┘
                          │
                          │ OAuth Tokens
                          │
                          ▼
              ┌────────────────────────┐
              │   WSO2 API Manager     │  Port 9443
              │   (API Gateway)        │
              └───────────┬────────────┘
                          │
              ┌───────────┴────────────┐
              │                        │
              ▼                        ▼
    ┌──────────────────┐    ┌──────────────────┐
    │  Gateway HTTP    │    │  Gateway HTTPS   │
    │  Port: 8280      │    │  Port: 8243      │
    └────────┬─────────┘    └────────┬─────────┘
             │                       │
             └───────────┬───────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ▼                ▼                ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│   Profile    │  │    Forex     │  │   Banking    │
│   Service    │  │   Service    │  │   Service    │
│  Port: 8002  │  │  Port: 8001  │  │  Port: 8003  │
└──────────────┘  └──────────────┘  └──────────────┘
        │                │                │
        └────────────────┼────────────────┘
                         │
                         ▼
              ┌────────────────────┐
              │   Redis (Cache)    │
              │   DynamoDB (Data)  │
              │   Kafka (Events)   │
              └────────────────────┘
```

## 📋 Services Breakdown

### Core Infrastructure:
- **MySQL** (3306): Database for WSO2 IS & APIM
- **WSO2 Identity Server** (9444): User management, OAuth2 provider
- **WSO2 API Manager** (9443, 8280, 8243): API gateway, rate limiting, security
- **Redis** (6379): Caching layer
- **DynamoDB Local** (8000): NoSQL data storage
- **Redpanda** (9092): Event streaming (Kafka-compatible)
- **Jaeger** (16686): Distributed tracing
- **OpenTelemetry Collector** (4318): Metrics & traces

### Application Services:
- **Profile Service** (8002): User registration, authentication, KYC
- **Forex Service** (8001): Currency exchange rates
- **Banking Service** (8003): Account management
- **Ledger Service** (8004): Transaction ledger
- **Wallet Service** (8005): Digital wallet
- **Payment Service** (8006): Payment processing
- **Rule Engine Service** (8007): Business rules

## 🚀 Complete Test Flow

### Step 1: Start All Services

```bash
# Start complete stack
docker compose up -d

# Wait for services to be healthy (takes ~3-5 minutes)
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "is-as-km|api-manager"

# Check health
./scripts/wso2-toolkit.sh health
```

### Step 2: Verify Key Manager Setup

```bash
# List configured Key Managers
./scripts/wso2-toolkit.sh list-km

# Should show:
# - WSO2IS (WSO2-IS-7) - enabled
# - Resident Key Manager (default) - disabled
```

### Step 3: Run End-to-End Test

```bash
# This will:
# 1. Create a test user in WSO2 IS
# 2. Generate OAuth tokens
# 3. Create APIM application
# 4. Subscribe to APIs
# 5. Test API calls through gateway

./scripts/end-to-end-test.sh
```

## 📝 Manual Test Steps

If you prefer to test manually, follow these steps:

### 1. Create Test User in WSO2 IS

```bash
curl -k -X POST "https://localhost:9444/scim2/Users" \
  -H "Authorization: Basic $(echo -n 'admin:admin' | base64)" \
  -H "Content-Type: application/scim+json" \
  -d '{
    "schemas": ["urn:ietf:params:scim:schemas:core:2.0:User"],
    "userName": "testuser",
    "password": "Test@123456",
    "active": true,
    "name": {
      "givenName": "Test",
      "familyName": "User"
    },
    "emails": [{
      "value": "test@example.com",
      "primary": true
    }]
  }' | jq .
```

### 2. Create OAuth Application

```bash
curl -k -X POST "https://localhost:9444/api/identity/oauth2/dcr/v1.1/register" \
  -H "Authorization: Basic $(echo -n 'admin:admin' | base64)" \
  -H "Content-Type: application/json" \
  -d '{
    "client_name": "TestApp",
    "grant_types": ["password", "refresh_token", "client_credentials"],
    "redirect_uris": ["http://localhost:8080/callback"]
  }' | jq .
```

**Save the `client_id` and `client_secret` from the response!**

### 3. Get OAuth Access Token (Password Grant)

```bash
CLIENT_ID="your_client_id"
CLIENT_SECRET="your_client_secret"

curl -k -X POST "https://localhost:9444/oauth2/token" \
  -u "${CLIENT_ID}:${CLIENT_SECRET}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&username=testuser&password=Test@123456&scope=openid profile email" | jq .
```

**Save the `access_token`!**

### 4. Access APIM Developer Portal

Open: `https://localhost:9443/devportal`

Login with: `testuser` / `Test@123456`

### 5. Create Application in APIM

**Via UI:**
1. Go to "Applications" → "Add New Application"
2. Name: "MyTestApp"
3. Throttling Policy: "Unlimited"
4. Click "Save"

**Via API:**
```bash
ACCESS_TOKEN="your_access_token"

curl -k -X POST "https://localhost:9443/api/am/devportal/v3/applications" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "MyTestApp",
    "throttlingPolicy": "Unlimited",
    "description": "Test application",
    "tokenType": "JWT"
  }' | jq .
```

### 6. Generate Application Keys

**Via UI:**
1. Go to your application
2. Click "Production Keys"
3. Click "Generate Keys"
4. Copy the Consumer Key and Consumer Secret

**Via API:**
```bash
APP_ID="your_app_id"

curl -k -X POST "https://localhost:9443/api/am/devportal/v3/applications/${APP_ID}/generate-keys" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "keyType": "PRODUCTION",
    "grant_types": ["password", "client_credentials", "refresh_token"],
    "validityTime": 3600
  }' | jq .
```

### 7. Subscribe to APIs

**Via UI:**
1. Go to "APIs" tab
2. Select an API
3. Click "Subscribe"
4. Select your application
5. Choose throttling policy
6. Click "Subscribe"

**Via API:**
```bash
API_ID="your_api_id"
APP_ID="your_app_id"

curl -k -X POST "https://localhost:9443/api/am/devportal/v3/subscriptions" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "apiId": "'${API_ID}'",
    "applicationId": "'${APP_ID}'",
    "throttlingPolicy": "Unlimited"
  }' | jq .
```

### 8. Test API Calls Through Gateway

**Generate API Token:**
```bash
CONSUMER_KEY="your_consumer_key"
CONSUMER_SECRET="your_consumer_secret"

curl -k -X POST "https://localhost:9444/oauth2/token" \
  -u "${CONSUMER_KEY}:${CONSUMER_SECRET}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&scope=default" | jq .
```

**Call API through Gateway:**
```bash
API_TOKEN="your_api_token"

# Example: Profile Service Health Check
curl -k -X GET "http://localhost:8280/profile/v1/health" \
  -H "Authorization: Bearer ${API_TOKEN}"

# Example: Forex Service - Get Rates
curl -k -X GET "http://localhost:8280/forex/v1/rates?base=USD&target=INR" \
  -H "Authorization: Bearer ${API_TOKEN}"
```

## 🔍 Service Endpoints

### Profile Service (Port 8002)
- **POST** `/register` - Register new user
- **POST** `/login` - Authenticate user
- **GET** `/profile` - Get user profile
- **PUT** `/profile` - Update profile
- **GET** `/health` - Health check

### Forex Service (Port 8001)
- **GET** `/rates` - Get forex rates
- **GET** `/convert` - Convert currency
- **GET** `/health` - Health check

### Banking Service (Port 8003)
- **GET** `/accounts` - List accounts
- **POST** `/accounts` - Create account
- **GET** `/accounts/{id}` - Get account details
- **GET** `/health` - Health check

## 🛠️ Troubleshooting

### Services Not Starting

```bash
# Check logs
docker logs global-transfer-backend-is-as-km-1
docker logs global-transfer-backend-api-manager-1

# Restart specific service
docker compose restart is-as-km

# Full restart
docker compose down
docker compose up -d
```

### Key Manager Issues

```bash
# Verify Key Manager
./scripts/wso2-toolkit.sh list-km

# Recreate Key Manager
./scripts/wso2-toolkit.sh delete-km WSO2IS
./scripts/wso2-toolkit.sh setup-km
```

### OAuth Token Issues

**Error: "invalid_client"**
- Verify client credentials are correct
- Check that OAuth app exists in IS

**Error: "invalid_grant"**
- Verify username/password are correct
- Check user is active in IS
- Ensure grant type is enabled

**Error: "invalid_scope"**
- Remove or adjust scopes in request
- Check application permissions

### API Gateway Issues

**Error: 401 Unauthorized**
- Verify API token is valid
- Check token hasn't expired
- Ensure you're using the correct token

**Error: 403 Forbidden**
- Verify application is subscribed to the API
- Check throttling policies
- Ensure API is published

**Error: 404 Not Found**
- Verify API context path
- Check API version
- Ensure API is deployed

## 📊 Monitoring & Observability

### View Traces in Jaeger
Open: `http://localhost:16686`

Search for traces by service name:
- `profile-service`
- `forex-service`
- `banking-service`

### Check OpenTelemetry Metrics
```bash
curl http://localhost:8888/metrics
```

### View Kafka Events
```bash
docker exec redpanda rpk topic list
docker exec redpanda rpk topic consume your-topic-name
```

## 📚 Additional Resources

- WSO2 IS Documentation: https://is.docs.wso2.com
- WSO2 APIM Documentation: https://apim.docs.wso2.com
- OAuth 2.0 Spec: https://oauth.net/2/
- OpenID Connect: https://openid.net/connect/

## ✅ Success Criteria

Your setup is working correctly if:

1. ✅ All Docker containers are healthy
2. ✅ WSO2IS Key Manager is enabled in APIM
3. ✅ Test user can be created in WSO2 IS
4. ✅ OAuth tokens can be generated
5. ✅ APIM application can be created
6. ✅ Application keys can be generated
7. ✅ APIs can be subscribed
8. ✅ API calls through gateway return 200 OK
9. ✅ Traces appear in Jaeger
10. ✅ Services can communicate with each other

---

**Happy Testing! 🎉**
