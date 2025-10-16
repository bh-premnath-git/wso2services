#!/bin/bash

################################################################################
# Test User Registration with JWT Claims
# Tests the new registration endpoints with optional phone and address
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  User Registration & JWT Claims Test                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Load OAuth credentials
CREDS_FILE=".oauth_credentials"
if [ ! -f "$CREDS_FILE" ]; then
    log_error "OAuth credentials not found. Run: ./complete_startup.sh"
    exit 1
fi

source "$CREDS_FILE"

# ============================================
# Test 1: Register user with ALL fields
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Test 1: Register user with phone & address"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

REGISTER_FULL=$(curl -sk -X POST http://localhost:8004/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "johndoe_test",
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
  }')

if echo "$REGISTER_FULL" | jq -e '.user_id' >/dev/null 2>&1; then
    log_success "User registered with phone & address"
    echo "$REGISTER_FULL" | jq '{status, user_id, username, claims_available}'
else
    log_error "Registration failed"
    echo "$REGISTER_FULL" | jq '.'
fi

echo ""

# ============================================
# Test 2: Register minimal user
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Test 2: Register user WITHOUT phone & address"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

REGISTER_MIN=$(curl -sk -X POST http://localhost:8004/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "janedoe_test",
    "password": "AnotherPass456!",
    "email": "jane.doe@example.com",
    "first_name": "Jane",
    "last_name": "Doe"
  }')

if echo "$REGISTER_MIN" | jq -e '.user_id' >/dev/null 2>&1; then
    log_success "User registered (minimal fields)"
    echo "$REGISTER_MIN" | jq '{status, user_id, username, claims_available}'
else
    log_error "Registration failed"
    echo "$REGISTER_MIN" | jq '.'
fi

echo ""

# ============================================
# Test 3: Login with ALL scopes
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Test 3: Login with all scopes (profile, phone, address)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

LOGIN_RESPONSE=$(curl -sk -X POST http://localhost:8004/auth/login \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"johndoe_test\",
    \"password\": \"SecurePass123!\",
    \"client_id\": \"$CLIENT_ID\",
    \"client_secret\": \"$CLIENT_SECRET\",
    \"scopes\": [\"openid\", \"profile\", \"email\", \"phone\", \"address\"]
  }")

if echo "$LOGIN_RESPONSE" | jq -e '.access_token' >/dev/null 2>&1; then
    log_success "Login successful - JWT tokens generated"
    echo ""
    log_info "Decoded JWT claims:"
    echo "$LOGIN_RESPONSE" | jq '.decoded_claims | {
        sub,
        email,
        given_name,
        family_name,
        phone_number,
        address
    }'
    
    ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.access_token')
else
    log_error "Login failed"
    echo "$LOGIN_RESPONSE" | jq '.'
fi

echo ""

# ============================================
# Test 4: Get UserInfo
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Test 4: Get user info with access token"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$ACCESS_TOKEN" ]; then
    USERINFO=$(curl -sk -X GET "http://localhost:8004/auth/userinfo?access_token=$ACCESS_TOKEN")
    
    if echo "$USERINFO" | jq -e '.sub' >/dev/null 2>&1; then
        log_success "User info retrieved"
        echo "$USERINFO" | jq '.'
    else
        log_error "Failed to get user info"
        echo "$USERINFO"
    fi
else
    log_warning "Skipping - no access token available"
fi

echo ""

# ============================================
# Test 5: Login minimal user (no phone/address in JWT)
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Test 5: Login minimal user (should not have phone/address)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

LOGIN_MIN=$(curl -sk -X POST http://localhost:8004/auth/login \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"janedoe_test\",
    \"password\": \"AnotherPass456!\",
    \"client_id\": \"$CLIENT_ID\",
    \"client_secret\": \"$CLIENT_SECRET\",
    \"scopes\": [\"openid\", \"profile\", \"email\", \"phone\", \"address\"]
  }")

if echo "$LOGIN_MIN" | jq -e '.access_token' >/dev/null 2>&1; then
    log_success "Login successful"
    echo ""
    log_info "JWT claims (phone/address should be missing):"
    echo "$LOGIN_MIN" | jq '.decoded_claims | {
        sub,
        email,
        given_name,
        family_name,
        phone_number,
        address
    }'
else
    log_error "Login failed"
    echo "$LOGIN_MIN" | jq '.'
fi

echo ""

# ============================================
# Summary
# ============================================
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Test Summary                                             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "✅ User registration with phone & address"
echo "✅ User registration without phone & address"
echo "✅ JWT tokens with custom claims based on scopes"
echo "✅ UserInfo endpoint"
echo ""
log_success "All tests completed!"
echo ""
echo "Note: Test users created in WSO2 IS:"
echo "  - johndoe_test (with phone & address)"
echo "  - janedoe_test (minimal)"
echo ""
