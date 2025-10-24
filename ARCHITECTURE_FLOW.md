# WSO2 API Manager + Identity Server Architecture
## Complete Integration & Flow Documentation

---

## 📊 System Overview

```
╔══════════════════════════════════════════════════════════════════════════╗
║                        WSO2 ECOSYSTEM ARCHITECTURE                       ║
║                     API Manager 4.5 + Identity Server 7.1                ║
╚══════════════════════════════════════════════════════════════════════════╝

┌────────────────────────────────────────────────────────────────────────┐
│                              🖥️  HOST MACHINE                           │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │  🛠️  WSO2 Toolkit Script (wso2-toolkit.sh)                    │    │
│  │  • Health checks                                              │    │
│  │  • Key Manager setup                                          │    │
│  │  • Application management                                     │    │
│  │  • Token generation                                           │    │
│  │  • Certificate management                                     │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                              │                                          │
│                              │ HTTPS/REST API                           │
│                              ▼                                          │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                    🐳 DOCKER NETWORK                           │    │
│  │                                                                │    │
│  │  ┌─────────────────────────────────────────────────────────┐ │    │
│  │  │  🌐 WSO2 API Manager (wso2am)                           │ │    │
│  │  │  Port: 9443 (Management) | 8243 (Gateway)               │ │    │
│  │  │                                                          │ │    │
│  │  │  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ │ │    │
│  │  │  ┃  📱 Publisher Portal                               ┃ │ │    │
│  │  │  ┃  • API Design & Publishing                         ┃ │ │    │
│  │  │  ┃  • Lifecycle Management                            ┃ │ │    │
│  │  │  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ │ │    │
│  │  │                                                          │ │    │
│  │  │  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ │ │    │
│  │  │  ┃  🏪 Developer Portal (DevPortal)                   ┃ │ │    │
│  │  │  ┃  • Application Management ⭐                       ┃ │ │    │
│  │  │  ┃  • API Subscription                                ┃ │ │    │
│  │  │  ┃  • OAuth2 Key Generation                           ┃ │ │    │
│  │  │  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ │ │    │
│  │  │                                                          │ │    │
│  │  │  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ │ │    │
│  │  │  ┃  🔐 Key Manager Integration                        ┃ │ │    │
│  │  │  ┃  • DCR (Dynamic Client Registration)              ┃ │ │    │
│  │  │  ┃  • Token Validation                                ┃ │ │    │
│  │  │  ┃  • Multi-KM Support                                ┃ │ │    │
│  │  │  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ │ │    │
│  │  │                                                          │ │    │
│  │  │  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ │ │    │
│  │  │  ┃  🚪 API Gateway                                    ┃ │ │    │
│  │  │  ┃  • Request Routing                                 ┃ │ │    │
│  │  │  ┃  • JWT Validation (JWKS)                           ┃ │ │    │
│  │  │  ┃  • Throttling & Rate Limiting                      ┃ │ │    │
│  │  │  ┃  • Analytics & Monitoring                          ┃ │ │    │
│  │  │  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ │ │    │
│  │  └────────────────────┬────────────────────────────────┘ │    │
│  │                       │ MTLS (Mutual TLS)                 │    │
│  │                       │ Certificate Trust                 │    │
│  │  ┌────────────────────┴────────────────────────────────┐ │    │
│  │  │  🔑 WSO2 Identity Server (wso2is)                   │ │    │
│  │  │  Port: 9444 (External) | 9443 (Internal)            │ │    │
│  │  │                                                       │ │    │
│  │  │  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓  │ │    │
│  │  │  ┃  🎟️  OAuth2 Authorization Server                 ┃  │ │    │
│  │  │  ┃  • Token Endpoint (/oauth2/token)                ┃  │ │    │
│  │  │  ┃  • Authorization Endpoint                         ┃  │ │    │
│  │  │  ┃  • Introspection & Revocation                     ┃  │ │    │
│  │  │  ┃  • JWKS Endpoint (/oauth2/jwks)                   ┃  │ │    │
│  │  │  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛  │ │    │
│  │  │                                                       │ │    │
│  │  │  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓  │ │    │
│  │  │  ┃  📋 DCR API (Dynamic Client Registration)        ┃  │ │    │
│  │  │  ┃  • /api/identity/oauth2/dcr/v1.1/register        ┃  │ │    │
│  │  │  ┃  • Client Management                             ┃  │ │    │
│  │  │  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛  │ │    │
│  │  │                                                       │ │    │
│  │  │  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓  │ │    │
│  │  │  ┃  👥 SCIM2 API (User & Role Management)          ┃  │ │    │
│  │  │  ┃  • /scim2/Users                                  ┃  │ │    │
│  │  │  ┃  • /scim2/Roles                                  ┃  │ │    │
│  │  │  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛  │ │    │
│  │  └───────────────────────────────────────────────────┘ │    │
│  │                                                          │    │
│  │  ┌───────────────────────────────────────────────────┐ │    │
│  │  │  🗄️  PostgreSQL Database (postgres-wso2)          │ │    │
│  │  │                                                     │ │    │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────┐ │ │    │
│  │  │  │  apim_db     │  │ identity_db  │  │shared_db │ │ │    │
│  │  │  │              │  │              │  │          │ │ │    │
│  │  │  │ • AM Apps    │  │ • IS Users   │  │ • Common │ │ │    │
│  │  │  │ • APIs       │  │ • Roles      │  │ • Config │ │ │    │
│  │  │  │ • Subscript. │  │ • OAuth2 Cli │  │          │ │ │    │
│  │  │  └──────────────┘  └──────────────┘  └──────────┘ │ │    │
│  │  └───────────────────────────────────────────────────┘ │    │
│  └────────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Application Creation Flow (2-Step Process)

```
╔══════════════════════════════════════════════════════════════════════════╗
║                    APPLICATION CREATION WORKFLOW                         ║
║                         (Correct APIM Integration)                       ║
╚══════════════════════════════════════════════════════════════════════════╝

┌──────────────────────────────────────────────────────────────────────────┐
│  USER                                                                    │
└──────┬───────────────────────────────────────────────────────────────────┘
       │
       │  $ ./wso2-toolkit.sh create-app MyApp http://localhost:8080/callback
       │
       ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  🛠️  TOOLKIT SCRIPT                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  Input Validation                                                │    │
│  │  ✓ App name format                                               │    │
│  │  ✓ Callback URL                                                  │    │
│  │  ✓ Container health                                              │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└──────┬───────────────────────────────────────────────────────────────────┘
       │
       │  ╔════════════════════════════════════════════════════════════╗
       │  ║  STEP 1: Create Application in APIM                       ║
       │  ╚════════════════════════════════════════════════════════════╝
       │
       │  POST /api/am/devportal/v3/applications
       │  {
       │    "name": "MyApp",
       │    "throttlingPolicy": "Unlimited",
       │    "description": "OAuth2/OIDC application",
       │    "tokenType": "JWT"
       │  }
       │
       ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  🌐 WSO2 API MANAGER - DEVPORTAL                                         │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  Application Record Created                                      │    │
│  │  ────────────────────────────                                    │    │
│  │  • Application ID: abc-123-def                                   │    │
│  │  • Owner: admin                                                  │    │
│  │  • Status: CREATED                                               │    │
│  │  • Throttling Policy: Unlimited                                  │    │
│  │  • Token Type: JWT                                               │    │
│  │                                                                   │    │
│  │  Database Operations:                                            │    │
│  │  ────────────────────                                            │    │
│  │  INSERT INTO AM_APPLICATION                                      │    │
│  │  INSERT INTO AM_SUBSCRIBER                                       │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└──────┬───────────────────────────────────────────────────────────────────┘
       │
       │  Returns: { "applicationId": "abc-123-def", ... }
       │
       ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  🛠️  TOOLKIT SCRIPT                                                      │
│  Application created successfully! ✓                                     │
│  Application ID: abc-123-def                                             │
└──────┬───────────────────────────────────────────────────────────────────┘
       │
       │  ╔════════════════════════════════════════════════════════════╗
       │  ║  STEP 2: Generate OAuth2 Keys with Key Manager            ║
       │  ╚════════════════════════════════════════════════════════════╝
       │
       │  POST /api/am/devportal/v3/applications/abc-123-def/generate-keys
       │  {
       │    "keyType": "PRODUCTION",
       │    "keyManager": "WSO2IS",
       │    "grantTypesToBeSupported": [
       │      "client_credentials",
       │      "password",
       │      "authorization_code",
       │      "refresh_token",
       │      "urn:ietf:params:oauth:grant-type:device_code",
       │      "urn:ietf:params:oauth:grant-type:jwt-bearer"
       │    ],
       │    "callbackUrl": "http://localhost:8080/callback"
       │  }
       │
       ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  🌐 WSO2 API MANAGER - KEY MANAGER INTEGRATION                           │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  Key Manager Lookup                                              │    │
│  │  ────────────────────                                            │    │
│  │  • Find Key Manager: "WSO2IS"                                    │    │
│  │  • Get DCR endpoint configuration                                │    │
│  │  • Prepare DCR request                                           │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└──────┬───────────────────────────────────────────────────────────────────┘
       │
       │  MTLS Connection
       │  POST https://wso2is:9443/api/identity/oauth2/dcr/v1.1/register
       │  {
       │    "client_name": "MyApp_PRODUCTION",
       │    "redirect_uris": ["http://localhost:8080/callback"],
       │    "grant_types": ["client_credentials", "password", ...]
       │  }
       │
       ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  🔑 WSO2 IDENTITY SERVER - DCR API                                       │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  OAuth2 Client Registration                                      │    │
│  │  ────────────────────────────                                    │    │
│  │  1. Validate request                                             │    │
│  │  2. Generate client_id                                           │    │
│  │  3. Generate client_secret                                       │    │
│  │  4. Store in identity_db                                         │    │
│  │  5. Configure grant types                                        │    │
│  │  6. Set callback URLs                                            │    │
│  │                                                                   │    │
│  │  Database Operations:                                            │    │
│  │  ────────────────────                                            │    │
│  │  INSERT INTO IDN_OAUTH_CONSUMER_APPS                             │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└──────┬───────────────────────────────────────────────────────────────────┘
       │
       │  Returns:
       │  {
       │    "client_id": "xK7gH8pQ2mN4vR9w",
       │    "client_secret": "yL3jP5sT7uV1bM8n",
       │    "client_name": "MyApp_PRODUCTION",
       │    "grant_types": [...]
       │  }
       │
       ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  🌐 WSO2 API MANAGER - KEY MANAGER INTEGRATION                           │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  Store OAuth2 Credentials                                        │    │
│  │  ──────────────────────────                                      │    │
│  │  • Map app_id ↔ client_id                                        │    │
│  │  • Store credentials (encrypted)                                 │    │
│  │  • Update application status                                     │    │
│  │                                                                   │    │
│  │  Database Operations:                                            │    │
│  │  ────────────────────                                            │    │
│  │  INSERT INTO AM_APPLICATION_KEY_MAPPING                          │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└──────┬───────────────────────────────────────────────────────────────────┘
       │
       │  Returns to script:
       │  {
       │    "consumerKey": "xK7gH8pQ2mN4vR9w",
       │    "consumerSecret": "yL3jP5sT7uV1bM8n",
       │    "keyManager": "WSO2IS",
       │    "callbackUrl": "http://localhost:8080/callback"
       │  }
       │
       ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  🛠️  TOOLKIT SCRIPT - SUCCESS                                           │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  ╔══════════════════════════════════════════════════════════╗   │    │
│  │  ║  SAVE THESE CREDENTIALS - SHOWN ONLY ONCE               ║   │    │
│  │  ╚══════════════════════════════════════════════════════════╝   │    │
│  │                                                                  │    │
│  │  Application Name:   MyApp                                       │    │
│  │  Application ID:     abc-123-def                                 │    │
│  │  Client ID:          xK7gH8pQ2mN4vR9w                            │    │
│  │  Client Secret:      yL3jP5sT7uV1bM8n                            │    │
│  │  Callback URL:       http://localhost:8080/callback              │    │
│  │  Key Manager:        WSO2IS                                      │    │
│  │                                                                  │    │
│  │  Grant Types Enabled:                                            │    │
│  │    ✓ Client Credentials                                          │    │
│  │    ✓ Password                                                    │    │
│  │    ✓ Authorization Code                                          │    │
│  │    ✓ Refresh Token                                               │    │
│  │    ✓ Device Code                                                 │    │
│  │    ✓ JWT Bearer                                                  │    │
│  │                                                                  │    │
│  │  Test token generation:                                          │    │
│  │  $ ./wso2-toolkit.sh get-token cc xK7gH8pQ2mN4vR9w \            │    │
│  │                                     yL3jP5sT7uV1bM8n             │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  📊 FINAL STATE                                                          │
│  ────────────────────────────────────────────────────────────────────────│
│                                                                          │
│  APIM Database:                     WSO2IS Database:                     │
│  ───────────────                    ────────────────                     │
│  • Application record               • OAuth2 client record               │
│  • Owner mapping                    • Client credentials                 │
│  • Throttling policy                • Grant type configs                 │
│  • Client ID reference              • Callback URLs                      │
│                                                                          │
│  DevPortal UI:                      Identity Server UI:                  │
│  ──────────────                     ───────────────────                  │
│  ✓ App visible                      ✓ Client visible                     │
│  ✓ Can subscribe to APIs            ✓ Can manage permissions             │
│  ✓ Can view keys                    ✓ Can view audit logs                │
│  ✓ Analytics enabled                                                     │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 🎫 Token Generation & API Call Flow

```
╔══════════════════════════════════════════════════════════════════════════╗
║                     TOKEN GENERATION & VALIDATION FLOW                   ║
╚══════════════════════════════════════════════════════════════════════════╝

┌──────────────────────────────────────────────────────────────────────────┐
│  STEP 1: Generate Access Token                                          │
└──────────────────────────────────────────────────────────────────────────┘

  User/Application
       │
       │  $ ./wso2-toolkit.sh get-token cc <client_id> <client_secret>
       │
       ▼
  ┌────────────────────────────────────────┐
  │  🛠️  Toolkit Script                    │
  │  • Encode credentials to Base64        │
  │  • Prepare token request               │
  └──────────────┬─────────────────────────┘
                 │
                 │  POST /oauth2/token
                 │  Headers:
                 │    Authorization: Basic <base64(client_id:client_secret)>
                 │  Body:
                 │    grant_type=client_credentials
                 │    scope=default
                 │
                 ▼
  ┌──────────────────────────────────────────────────────────────────┐
  │  🔑 WSO2 Identity Server - OAuth2 Token Endpoint                 │
  │  ┌──────────────────────────────────────────────────────────┐   │
  │  │  Token Request Processing                                │   │
  │  │  ──────────────────────────                              │   │
  │  │  1️⃣  Decode Authorization header                         │   │
  │  │  2️⃣  Validate client credentials                         │   │
  │  │     • Query IDN_OAUTH_CONSUMER_APPS                      │   │
  │  │     • Verify client_id exists                            │   │
  │  │     • Validate client_secret hash                        │   │
  │  │  3️⃣  Check grant type permissions                        │   │
  │  │     • Verify "client_credentials" is allowed             │   │
  │  │  4️⃣  Generate JWT access token                           │   │
  │  │     • Create JWT header                                  │   │
  │  │     • Create JWT payload (claims)                        │   │
  │  │     • Sign with private key (RS256)                      │   │
  │  │  5️⃣  Store token metadata                                │   │
  │  │     • INSERT INTO IDN_OAUTH2_ACCESS_TOKEN                │   │
  │  └──────────────────────────────────────────────────────────┘   │
  └──────────────┬───────────────────────────────────────────────────┘
                 │
                 │  Response (200 OK):
                 │  {
                 │    "access_token": "eyJhbGciOiJSUzI1NiIs...",
                 │    "token_type": "Bearer",
                 │    "expires_in": 3600,
                 │    "scope": "default"
                 │  }
                 │
                 ▼
  ┌────────────────────────────────────────┐
  │  🛠️  Toolkit Script                    │
  │  ✓ Token generated successfully        │
  │  • Display access token                │
  │  • Show expiry time                    │
  └────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  STEP 2: Call API with Token                                            │
└──────────────────────────────────────────────────────────────────────────┘

  Client Application
       │
       │  GET /api/v1/products
       │  Headers:
       │    Authorization: Bearer eyJhbGciOiJSUzI1NiIs...
       │
       ▼
  ┌──────────────────────────────────────────────────────────────────┐
  │  🚪 WSO2 API Manager - Gateway (Port 8243)                       │
  │  ┌──────────────────────────────────────────────────────────┐   │
  │  │  Request Validation Pipeline                             │   │
  │  │  ──────────────────────────                              │   │
  │  │  1️⃣  Extract JWT from Authorization header               │   │
  │  │                                                           │   │
  │  │  2️⃣  Fetch JWKS from WSO2 IS                             │   │
  │  │     GET https://wso2is:9443/oauth2/jwks                  │   │
  │  │     {                                                     │   │
  │  │       "keys": [{                                          │   │
  │  │         "kty": "RSA",                                     │   │
  │  │         "n": "public_key_modulus...",                     │   │
  │  │         "e": "AQAB",                                      │   │
  │  │         "kid": "key-id"                                   │   │
  │  │       }]                                                  │   │
  │  │     }                                                     │   │
  │  │                                                           │   │
  │  │  3️⃣  Validate JWT Signature                              │   │
  │  │     • Decode JWT header & payload                        │   │
  │  │     • Get public key from JWKS (by kid)                  │   │
  │  │     • Verify signature using public key                  │   │
  │  │     • ✓ Signature valid                                  │   │
  │  │                                                           │   │
  │  │  4️⃣  Validate JWT Claims                                 │   │
  │  │     • Check "exp" (expiration)                           │   │
  │  │     • Check "iat" (issued at)                            │   │
  │  │     • Check "iss" (issuer)                               │   │
  │  │     • Check "aud" (audience)                             │   │
  │  │     • ✓ All claims valid                                 │   │
  │  │                                                           │   │
  │  │  5️⃣  Check API Subscription                              │   │
  │  │     • Extract client_id from JWT                         │   │
  │  │     • Query AM_SUBSCRIPTION table                        │   │
  │  │     • Verify app subscribed to this API                  │   │
  │  │     • ✓ Subscription exists                              │   │
  │  │                                                           │   │
  │  │  6️⃣  Apply Throttling Policy                             │   │
  │  │     • Get throttling tier from subscription              │   │
  │  │     • Check current rate limit                           │   │
  │  │     • Increment request counter                          │   │
  │  │     • ✓ Within limits                                    │   │
  │  │                                                           │   │
  │  │  7️⃣  Record Analytics                                    │   │
  │  │     • Log request metadata                               │   │
  │  │     • Track API usage                                    │   │
  │  │                                                           │   │
  │  │  8️⃣  Forward to Backend                                  │   │
  │  │     • Add internal headers                               │   │
  │  │     • Route to backend API                               │   │
  │  └──────────────────────────────────────────────────────────┘   │
  └──────────────┬───────────────────────────────────────────────────┘
                 │
                 │  Forward to Backend API
                 │
                 ▼
  ┌────────────────────────────────────────┐
  │  🎯 Backend API Server                 │
  │  • Process business logic              │
  │  • Return response                     │
  └──────────────┬─────────────────────────┘
                 │
                 │  Response (200 OK):
                 │  {
                 │    "products": [...]
                 │  }
                 │
                 ▼
  ┌────────────────────────────────────────┐
  │  🚪 APIM Gateway                       │
  │  • Add response headers                │
  │  • Record analytics                    │
  │  • Return to client                    │
  └──────────────┬─────────────────────────┘
                 │
                 ▼
  ┌────────────────────────────────────────┐
  │  Client Application                    │
  │  ✓ Response received                   │
  └────────────────────────────────────────┘
```

---

## 🔐 Security & Certificate Management

```
╔══════════════════════════════════════════════════════════════════════════╗
║                     MTLS CERTIFICATE TRUST SETUP                         ║
╚══════════════════════════════════════════════════════════════════════════╝

┌──────────────────────────────────────────────────────────────────────────┐
│  Initial State (No Trust)                                                │
└──────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────┐                    ┌─────────────────────┐
  │   WSO2 AM           │       ❌ SSL       │   WSO2 IS           │
  │                     │◄──────────────────►│                     │
  │  wso2carbon.jks     │    Handshake       │  wso2carbon.jks     │
  │  (Private Key)      │     Fails          │  (Private Key)      │
  │                     │                    │                     │
  │  client-truststore  │                    │  client-truststore  │
  │  (No IS cert) ❌    │                    │  (No AM cert) ❌    │
  └─────────────────────┘                    └─────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  Fix MTLS: ./wso2-toolkit.sh fix-mtls                                   │
└──────────────────────────────────────────────────────────────────────────┘

  Step 1: Export IS Certificate
  ───────────────────────────────
  ┌─────────────────────┐
  │  WSO2 IS Container  │
  │                     │
  │  $ keytool -export  │──┐
  │    -alias wso2carbon│  │  Exports to:
  │    -keystore wso2carbon.jks  │  /tmp/wso2is.crt
  │    -file /tmp/wso2is.crt     │
  └─────────────────────┘  │
                           │
  Step 2: Import to APIM Truststore
  ──────────────────────────────────
                           │
                           ▼
  ┌─────────────────────────────────┐
  │  Copy cert to APIM container    │
  └──────────────┬──────────────────┘
                 │
                 ▼
  ┌─────────────────────┐
  │  WSO2 AM Container  │
  │                     │
  │  $ keytool -import  │  Imports as:
  │    -alias wso2is    │  "wso2is" alias
  │    -file /tmp/wso2is.crt        │
  │    -keystore client-truststore.jks  │
  └─────────────────────┘
         │
         │  $ docker restart wso2am
         │
         ▼
  ┌─────────────────────────────────┐
  │  APIM restarts with trust ✓     │
  └─────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  Final State (Trust Established)                                         │
└──────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────┐                    ┌─────────────────────┐
  │   WSO2 AM           │       ✅ MTLS      │   WSO2 IS           │
  │                     │◄──────────────────►│                     │
  │  wso2carbon.jks     │    Successful      │  wso2carbon.jks     │
  │  (Private Key)      │                    │  (Private Key)      │
  │                     │                    │                     │
  │  client-truststore  │                    │  client-truststore  │
  │  ├─ wso2carbon      │                    │  ├─ wso2carbon      │
  │  └─ wso2is ✅       │                    │  └─ wso2am ✅       │
  └─────────────────────┘                    └─────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  JWT Token Validation with JWKS                                         │
└──────────────────────────────────────────────────────────────────────────┘

  Token Signing (WSO2 IS)          Token Validation (APIM Gateway)
  ───────────────────────          ──────────────────────────────

  ┌─────────────────────┐          ┌─────────────────────┐
  │  Private Key        │          │  JWKS Endpoint      │
  │  (wso2carbon.jks)   │          │  /oauth2/jwks       │
  │                     │          │                     │
  │  RS256 Algorithm    │          │  Public Key (JWK)   │
  │       │             │          │  {                  │
  │       ▼             │          │    "kty": "RSA",    │
  │  Sign JWT           │          │    "n": "...",      │
  │       │             │          │    "e": "AQAB",     │
  │       ▼             │          │    "kid": "123"     │
  │  eyJhbGci...        │          │  }                  │
  └───────┬─────────────┘          └──────────▲──────────┘
          │                                   │
          │  Token sent to API                │  Gateway fetches JWKS
          │                                   │
          └───────────────────────────────────┘
                        │
                        ▼
              ┌──────────────────┐
              │  Validation:     │
              │  1. Decode JWT   │
              │  2. Get kid      │
              │  3. Find JWK     │
              │  4. Verify sig   │
              │  5. Check claims │
              │  ✓ Valid         │
              └──────────────────┘
```

---

## 📡 API Endpoints Reference

```
╔══════════════════════════════════════════════════════════════════════════╗
║                         API ENDPOINTS SUMMARY                            ║
╚══════════════════════════════════════════════════════════════════════════╝

┌──────────────────────────────────────────────────────────────────────────┐
│  WSO2 API MANAGER - DevPortal API                                       │
│  Base URL: https://localhost:9443/api/am/devportal/v3                   │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  📱 Applications                                                         │
│  ───────────────────────────────────────────────────────────────────────│
│  GET    /applications                    List all applications          │
│  POST   /applications                    Create new application         │
│  GET    /applications/{id}               Get application details        │
│  PUT    /applications/{id}               Update application             │
│  DELETE /applications/{id}               Delete application             │
│                                                                          │
│  🔑 OAuth2 Keys                                                          │
│  ───────────────────────────────────────────────────────────────────────│
│  POST   /applications/{id}/generate-keys  Generate OAuth2 credentials   │
│  GET    /applications/{id}/keys/{type}    Get production/sandbox keys   │
│  PUT    /applications/{id}/keys/{type}    Update key configuration      │
│  POST   /applications/{id}/keys/{type}/regenerate-secret                │
│                                            Regenerate client secret      │
│                                                                          │
│  📋 Subscriptions                                                        │
│  ───────────────────────────────────────────────────────────────────────│
│  GET    /subscriptions                   List subscriptions             │
│  POST   /subscriptions                   Subscribe to API               │
│  DELETE /subscriptions/{id}              Unsubscribe from API           │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  WSO2 API MANAGER - Admin API                                           │
│  Base URL: https://localhost:9443/api/am/admin/v4                       │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  🔐 Key Managers                                                         │
│  ───────────────────────────────────────────────────────────────────────│
│  GET    /key-managers                    List all key managers          │
│  POST   /key-managers                    Add new key manager            │
│  GET    /key-managers/{id}               Get key manager details        │
│  PUT    /key-managers/{id}               Update key manager             │
│  DELETE /key-managers/{id}               Delete key manager             │
│                                                                          │
│  🎯 Throttling Policies                                                  │
│  ───────────────────────────────────────────────────────────────────────│
│  GET    /throttling/policies             List all policies              │
│  POST   /throttling/policies/application Create application policy      │
│  POST   /throttling/policies/subscription Create subscription policy    │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  WSO2 IDENTITY SERVER - OAuth2 API                                      │
│  Base URL: https://localhost:9444/oauth2                                │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  🎟️  Token Operations                                                   │
│  ───────────────────────────────────────────────────────────────────────│
│  POST   /token                           Generate access token          │
│  POST   /revoke                          Revoke token                   │
│  POST   /introspect                      Introspect token               │
│  GET    /jwks                            Get JSON Web Key Set           │
│  POST   /authorize                       Authorization endpoint         │
│  GET    /token/.well-known/openid-configuration                         │
│                                          OpenID Connect discovery        │
│                                                                          │
│  📋 Device Flow                                                          │
│  ───────────────────────────────────────────────────────────────────────│
│  POST   /device_authorize                Initiate device flow           │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  WSO2 IDENTITY SERVER - DCR API                                         │
│  Base URL: https://localhost:9444/api/identity/oauth2/dcr/v1.1          │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  🔧 Dynamic Client Registration                                          │
│  ───────────────────────────────────────────────────────────────────────│
│  POST   /register                        Register OAuth2 client         │
│  GET    /register/{client_id}            Get client details             │
│  PUT    /register/{client_id}            Update client                  │
│  DELETE /register/{client_id}            Delete client                  │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  WSO2 IDENTITY SERVER - SCIM2 API                                       │
│  Base URL: https://localhost:9444/scim2                                 │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  👥 User Management                                                      │
│  ───────────────────────────────────────────────────────────────────────│
│  GET    /Users                           List all users                 │
│  POST   /Users                           Create user                    │
│  GET    /Users/{id}                      Get user details               │
│  PUT    /Users/{id}                      Update user                    │
│  DELETE /Users/{id}                      Delete user                    │
│                                                                          │
│  🎭 Role Management                                                      │
│  ───────────────────────────────────────────────────────────────────────│
│  GET    /Roles                           List all roles                 │
│  POST   /Roles                           Create role                    │
│  GET    /Roles/{id}                      Get role details               │
│  PUT    /Roles/{id}                      Update role                    │
│  DELETE /Roles/{id}                      Delete role                    │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Complete Lifecycle Diagram

```
╔══════════════════════════════════════════════════════════════════════════╗
║                  COMPLETE APPLICATION LIFECYCLE                          ║
╚══════════════════════════════════════════════════════════════════════════╝

┌──────────────────────────────────────────────────────────────────────────┐
│  PHASE 1: Infrastructure Setup                                          │
└──────────────────────────────────────────────────────────────────────────┘

  $ docker compose up -d
       │
       ├─→ PostgreSQL starts (apim_db, identity_db, shared_db)
       ├─→ WSO2 IS starts (port 9444)
       └─→ WSO2 AM starts (port 9443, 8243)

  $ ./wso2-toolkit.sh health
       │
       └─→ ✓ All services healthy

  $ ./wso2-toolkit.sh fix-mtls
       │
       └─→ ✓ Certificates trusted

  $ ./wso2-toolkit.sh setup-km
       │
       └─→ ✓ WSO2IS configured as Key Manager

  $ ./wso2-toolkit.sh disable-resident-km
       │
       └─→ ✓ Default Key Manager disabled

┌──────────────────────────────────────────────────────────────────────────┐
│  PHASE 2: Application Creation                                          │
└──────────────────────────────────────────────────────────────────────────┘

  $ ./wso2-toolkit.sh create-app MyApp http://localhost:8080/callback
       │
       ├─→ [APIM] Create application record
       ├─→ [APIM] Generate keys via WSO2IS Key Manager
       └─→ [WSO2IS] Register OAuth2 client
            │
            └─→ Returns: client_id, client_secret

┌──────────────────────────────────────────────────────────────────────────┐
│  PHASE 3: API Subscription (Optional - via UI or API)                   │
└──────────────────────────────────────────────────────────────────────────┘

  User → APIM DevPortal UI
       │
       ├─→ Browse available APIs
       ├─→ Select API
       └─→ Subscribe with application
            │
            └─→ ✓ Subscription created

┌──────────────────────────────────────────────────────────────────────────┐
│  PHASE 4: Token Generation                                              │
└──────────────────────────────────────────────────────────────────────────┘

  $ ./wso2-toolkit.sh get-token cc <client_id> <client_secret>
       │
       └─→ [WSO2IS] /oauth2/token
            │
            └─→ Returns: JWT access token

┌──────────────────────────────────────────────────────────────────────────┐
│  PHASE 5: API Invocation                                                │
└──────────────────────────────────────────────────────────────────────────┘

  $ curl -H "Authorization: Bearer <token>" \
         https://localhost:8243/api/v1/products
       │
       ├─→ [APIM Gateway] Validate JWT
       ├─→ [APIM Gateway] Check subscription
       ├─→ [APIM Gateway] Apply throttling
       ├─→ [APIM Gateway] Forward to backend
       └─→ [Backend] Process & return response

┌──────────────────────────────────────────────────────────────────────────┐
│  PHASE 6: Monitoring & Analytics                                        │
└──────────────────────────────────────────────────────────────────────────┘

  User → APIM Analytics Dashboard
       │
       ├─→ View API usage
       ├─→ Monitor throttling
       ├─→ Check error rates
       └─→ Generate reports

┌──────────────────────────────────────────────────────────────────────────┐
│  PHASE 7: Cleanup (Optional)                                            │
└──────────────────────────────────────────────────────────────────────────┘

  $ ./wso2-toolkit.sh delete-app <app_id>
       │
       ├─→ [APIM] Delete application
       ├─→ [APIM] Remove subscriptions
       └─→ [WSO2IS] Delete OAuth2 client
            │
            └─→ ✓ Cleanup complete
```

---

## 🎯 Key Benefits Summary

```
╔══════════════════════════════════════════════════════════════════════════╗
║                     WHY THIS ARCHITECTURE IS CORRECT                     ║
╚══════════════════════════════════════════════════════════════════════════╝

┌──────────────────────────────────────────────────────────────────────────┐
│  ✅ Proper Separation of Concerns                                       │
├──────────────────────────────────────────────────────────────────────────┤
│  • APIM handles API governance, throttling, analytics                   │
│  • WSO2 IS handles identity, authentication, authorization              │
│  • Clear boundaries between components                                  │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  ✅ Full DevPortal Integration                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  • Applications visible in UI                                            │
│  • Self-service app creation                                            │
│  • API discovery and subscription                                       │
│  • Key regeneration support                                             │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  ✅ Enterprise-Grade Security                                           │
├──────────────────────────────────────────────────────────────────────────┤
│  • MTLS between APIM and WSO2IS                                         │
│  • JWT signature validation via JWKS                                    │
│  • Secure credential storage (encrypted)                                │
│  • OAuth2 best practices                                                │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  ✅ Comprehensive Governance                                            │
├──────────────────────────────────────────────────────────────────────────┤
│  • Throttling policies enforced                                         │
│  • API subscriptions tracked                                            │
│  • Usage analytics collected                                            │
│  • Audit logs maintained                                                │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  ✅ Scalability & Flexibility                                           │
├──────────────────────────────────────────────────────────────────────────┤
│  • Multiple Key Manager support                                         │
│  • Production/Sandbox separation                                        │
│  • Multi-tenant capable                                                 │
│  • Gateway clustering support                                           │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  ✅ Developer Experience                                                │
├──────────────────────────────────────────────────────────────────────────┤
│  • One command app creation                                             │
│  • Automated DCR flow                                                   │
│  • All grant types supported                                            │
│  • Comprehensive toolkit                                                │
└──────────────────────────────────────────────────────────────────────────┘
```

---
## 📊 API Gateway Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          CLIENT APPLICATION                         │
└────────────────┬────────────────────────────────────────────────────┘
                 │
                 │ HTTPS + Bearer Token
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│              WSO2 API GATEWAY (localhost:8243)                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Token Validation (JWKS from WSO2 IS)                        │  │
│  │  Subscription Check                                          │  │
│  │  Throttling Policies                                         │  │
│  │  Analytics & Monitoring                                      │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────┬────┬────┬────┬────┬────┬─────────────────────────────────────┘
     │    │    │    │    │    │
     │    │    │    │    │    └─→ http://wallet-service:8006
     │    │    │    │    └──────→ http://rule-engine-service:8005
     │    │    │    └───────────→ http://profile-service:8004
     │    │    └────────────────→ http://payment-service:8003
     │    └─────────────────────→ http://ledger-service:8002
     └──────────────────────────→ http://forex-service:8001
                                   
┌─────────────────────────────────────────────────────────────────────┐
│                    6 BACKEND MICROSERVICES                          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐             │
│  │  Forex   │ │  Ledger  │ │ Payment  │ │ Profile  │             │
│  │  :8001   │ │  :8002   │ │  :8003   │ │  :8004   │             │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘             │
│  ┌──────────┐ ┌──────────┐                                         │
│  │  Rules   │ │  Wallet  │                                         │
│  │  :8005   │ │  :8006   │                                         │
│  └──────────┘ └──────────┘                                         │
└─────────────────────────────────────────────────────────────────────┘
```