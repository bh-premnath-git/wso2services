# User Registration & JWT Claims Guide

## Overview

The Profile Service now includes user registration with optional phone and address fields. These fields automatically appear in JWT tokens when appropriate OAuth2 scopes are requested.

## Features

✅ **User Registration** - SCIM2-based registration with WSO2 IS  
✅ **Optional Fields** - Phone and address are completely optional  
✅ **JWT Claims** - Phone/address appear in JWT when scopes requested  
✅ **Strong Password** - Enforced password policy  
✅ **Email Validation** - RFC 5322 compliant  
✅ **Phone Validation** - E.164 format (+12025551234)  

---

## API Endpoints

### 1. Register User

**Endpoint:** `POST http://localhost:8004/register`

**Required Fields:**
- `username` (3-50 chars, alphanumeric, underscore, hyphen)
- `password` (8+ chars, uppercase, lowercase, digit, special char)
- `email` (valid email address)
- `first_name` (1-100 chars)
- `last_name` (1-100 chars)

**Optional Fields:**
- `phone` (E.164 format: +12025551234)
- `address` (object with optional subfields):
  - `street`
  - `locality` (city)
  - `region` (state/province)
  - `postal_code`
  - `country`

**Example - Full Registration:**
```bash
curl -X POST http://localhost:8004/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "johndoe",
    "password": "SecurePass123!",
    "email": "john.doe@example.com",
    "first_name": "John",
    "last_name": "Doe",
    "phone": "+12025551234",
    "address": {
      "street": "123 Main St",
      "locality": "New York",
      "region": "NY",
      "postal_code": "10001",
      "country": "USA"
    }
  }'
```

**Example - Minimal Registration:**
```bash
curl -X POST http://localhost:8004/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "janedoe",
    "password": "AnotherPass456!",
    "email": "jane.doe@example.com",
    "first_name": "Jane",
    "last_name": "Doe"
  }'
```

**Response:**
```json
{
  "status": "success",
  "message": "User registered successfully",
  "user_id": "abc123-def456",
  "username": "johndoe",
  "claims_available": {
    "profile": ["given_name", "family_name", "email"],
    "phone": ["phone_number"],
    "address": ["street_address", "locality", "region", "postal_code", "country", "formatted"]
  },
  "jwt_scopes_hint": "Use scopes: openid profile email phone address"
}
```

---

### 2. Login & Get JWT Tokens

**Endpoint:** `POST http://localhost:8004/auth/login`

**OAuth2 Scopes Control JWT Claims:**
- `openid` - Required for OIDC
- `profile` - Adds given_name, family_name to JWT
- `email` - Adds email to JWT
- `phone` - Adds phone_number to JWT (if user has phone)
- `address` - Adds address object to JWT (if user has address)

**Example:**
```bash
# First, get client credentials from .oauth_credentials file
source .oauth_credentials

curl -X POST http://localhost:8004/auth/login \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"johndoe\",
    \"password\": \"SecurePass123!\",
    \"client_id\": \"$CLIENT_ID\",
    \"client_secret\": \"$CLIENT_SECRET\",
    \"scopes\": [\"openid\", \"profile\", \"email\", \"phone\", \"address\"]
  }"
```

**Response with Full Scopes:**
```json
{
  "access_token": "eyJ4NXQi...",
  "id_token": "eyJ4NXQi...",
  "refresh_token": "b3e2d1f...",
  "expires_in": 3600,
  "token_type": "Bearer",
  "scope": "openid profile email phone address",
  "decoded_claims": {
    "sub": "johndoe",
    "email": "john.doe@example.com",
    "given_name": "John",
    "family_name": "Doe",
    "phone_number": "+12025551234",
    "address": {
      "street_address": "123 Main St",
      "locality": "New York",
      "region": "NY",
      "postal_code": "10001",
      "country": "USA",
      "formatted": "123 Main St, New York, NY 10001, USA"
    }
  }
}
```

**Response with Profile Scope Only:**
```json
{
  "access_token": "eyJ4NXQi...",
  "id_token": "eyJ4NXQi...",
  "decoded_claims": {
    "sub": "johndoe",
    "email": "john.doe@example.com",
    "given_name": "John",
    "family_name": "Doe"
  }
}
```

---

### 3. Get User Info

**Endpoint:** `GET http://localhost:8004/auth/userinfo?access_token={token}`

Returns user claims based on scopes used during login.

**Example:**
```bash
TOKEN="your_access_token_here"

curl -X GET "http://localhost:8004/auth/userinfo?access_token=$TOKEN"
```

**Response:**
```json
{
  "sub": "johndoe",
  "email": "john.doe@example.com",
  "given_name": "John",
  "family_name": "Doe",
  "phone_number": "+12025551234",
  "address": {
    "street_address": "123 Main St",
    "locality": "New York",
    "region": "NY",
    "postal_code": "10001",
    "country": "USA",
    "formatted": "123 Main St, New York, NY 10001, USA"
  }
}
```

---

### 4. Refresh Token

**Endpoint:** `POST http://localhost:8004/auth/refresh`

**Example:**
```bash
curl -X POST http://localhost:8004/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{
    "refresh_token": "your_refresh_token",
    "client_id": "your_client_id",
    "client_secret": "your_client_secret"
  }'
```

---

## Testing

### Quick Test Script

Run the automated test script:

```bash
./test_user_registration.sh
```

This script will:
1. ✅ Register user with phone & address
2. ✅ Register user without phone & address
3. ✅ Login with all scopes and show JWT claims
4. ✅ Get user info from /userinfo endpoint
5. ✅ Login minimal user (no phone/address in JWT)

---

## JWT Token Structure

### User WITH Phone & Address

When requesting scopes: `openid profile email phone address`

```json
{
  "sub": "johndoe",
  "aud": "client_id",
  "iss": "https://localhost:9444/oauth2/token",
  "exp": 1234567890,
  "iat": 1234564290,
  "email": "john.doe@example.com",
  "given_name": "John",
  "family_name": "Doe",
  "phone_number": "+12025551234",
  "address": {
    "street_address": "123 Main St",
    "locality": "New York",
    "region": "NY",
    "postal_code": "10001",
    "country": "USA",
    "formatted": "123 Main St, New York, NY 10001, USA"
  }
}
```

### User WITHOUT Phone & Address

When requesting same scopes but user has no phone/address:

```json
{
  "sub": "janedoe",
  "aud": "client_id",
  "iss": "https://localhost:9444/oauth2/token",
  "exp": 1234567890,
  "iat": 1234564290,
  "email": "jane.doe@example.com",
  "given_name": "Jane",
  "family_name": "Doe"
}
```

**Note:** Phone and address claims are **not present** if user doesn't have them.

---

## Password Policy

Enforced rules:
- ✅ Minimum 8 characters
- ✅ At least one uppercase letter
- ✅ At least one lowercase letter
- ✅ At least one digit
- ✅ At least one special character

**Valid Examples:**
- `SecurePass123!`
- `MyP@ssw0rd`
- `Testing#2024`

---

## Phone Number Format

Must be in **E.164 format**: `+[country code][number]`

**Valid Examples:**
- `+12025551234` (USA)
- `+442071234567` (UK)
- `+919876543210` (India)

**Invalid Examples:**
- `2025551234` ❌ (missing +)
- `+1 202 555 1234` ❌ (spaces)
- `(202) 555-1234` ❌ (formatting)

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Profile Service (port 8004)                    │
│  ┌──────────────────────────────────────────┐   │
│  │  /register                               │   │
│  │  /auth/login                             │   │
│  │  /auth/userinfo                          │   │
│  │  /auth/refresh                           │   │
│  └──────────────────────────────────────────┘   │
│            ↓ uses                                │
│  ┌──────────────────────────────────────────┐   │
│  │  common/auth/wso2_client.py              │   │
│  │  - WSO2IdentityClient                    │   │
│  │  - register_user()                       │   │
│  │  - authenticate()                        │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
                    ↓
        SCIM2 & OAuth2 APIs
                    ↓
┌─────────────────────────────────────────────────┐
│  WSO2 Identity Server (port 9444)               │
│  - SCIM2 User Management                        │
│  - OAuth2 Token Generation                      │
│  - JWT with Custom Claims                       │
│  - OIDC Scopes: phone, address, profile        │
└─────────────────────────────────────────────────┘
```

---

## Benefits

### For Developers
- ✅ **Centralized Auth** - All auth logic in `common/auth/`
- ✅ **Reusable** - Any service can import and use
- ✅ **Type Safe** - Pydantic models with validation
- ✅ **Clean API** - Simple async methods

### For Users
- ✅ **Flexible** - Phone and address optional
- ✅ **Secure** - Strong password policy enforced
- ✅ **Standards Compliant** - SCIM2, OAuth2, OIDC
- ✅ **JWT Claims** - Rich user context in tokens

---

## Troubleshooting

### Registration Fails: "User already exists"
```bash
# Delete user via WSO2 IS Console
https://localhost:9444/console
# Or use SCIM2 API to delete
```

### Login Fails: "Invalid credentials"
- Check username and password
- Verify user was created in WSO2 IS
- Check WSO2 IS logs: `docker compose logs wso2is`

### JWT Missing Phone/Address Claims
- Verify scopes include `phone` and `address`
- Check user actually has phone/address in registration
- User registered without phone/address won't have those claims

### Connection Refused
- Ensure services are running: `docker compose ps`
- Check profile service health: `curl http://localhost:8004/health`
- Verify WSO2 IS is healthy: `curl -k https://localhost:9444/carbon/admin/login.jsp`

---

## Next Steps

1. ✅ Run `./complete_startup.sh` to start all services
2. ✅ Run `./test_user_registration.sh` to test registration
3. ✅ Register your own users via `/register` endpoint
4. ✅ Use JWT tokens to access other microservices

For integration with other services, see: `README.md`
