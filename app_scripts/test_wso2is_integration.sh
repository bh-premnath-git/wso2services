#!/usr/bin/env bash

################################################################################
# Test WSO2 IS Key Manager Integration
#
# This script validates the complete WSO2 IS + APIM integration by:
# 1. Creating a test application
# 2. Generating OAuth keys with WSO2-IS-KeyManager
# 3. Getting token from WSO2 IS for a user
# 4. Subscribing to APIs
# 5. Testing API calls through gateway with the token
#
# Usage: ./test_wso2is_integration.sh
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

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  WSO2 IS Key Manager - Integration Test                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Configuration
APIM_HOST="localhost"
APIM_PORT="9443"
IS_HOST="localhost"
IS_PORT="9444"
GATEWAY_URL="https://localhost:8243"
TEST_APP_NAME="IntegrationTestApp_$$"

# APIs to test
declare -a APIS=(
    "forex"
    "profile"
    "wallet"
    "payment"
    "ledger"
    "rules"
)

# Step 1: Create test application
log_info "[1/5] Creating test application..."

APP_RESPONSE=$(curl -sk -u "admin:admin" \
    -X POST "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"${TEST_APP_NAME}\",
        \"throttlingPolicy\": \"Unlimited\",
        \"description\": \"Integration test application\",
        \"tokenType\": \"JWT\"
    }")

APP_ID=$(echo "$APP_RESPONSE" | jq -r '.applicationId')

if [ -z "$APP_ID" ] || [ "$APP_ID" = "null" ]; then
    log_error "Failed to create test application"
    echo "$APP_RESPONSE" | jq '.'
    exit 1
fi

log_success "Test application created: $APP_ID"
echo ""

# Step 2: Generate keys with WSO2-IS-KeyManager
log_info "[2/5] Generating keys with WSO2-IS-KeyManager..."

KEYS_RESPONSE=$(curl -sk -u "admin:admin" \
    -X POST "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications/${APP_ID}/generate-keys" \
    -H "Content-Type: application/json" \
    -d '{
        "keyType": "PRODUCTION",
        "keyManager": "WSO2-IS-KeyManager",
        "grantTypesToBeSupported": ["password", "client_credentials", "refresh_token"],
        "callbackUrl": "https://localhost/callback",
        "scopes": ["default"],
        "validityTime": 3600
    }')

CLIENT_ID=$(echo "$KEYS_RESPONSE" | jq -r '.consumerKey')
CLIENT_SECRET=$(echo "$KEYS_RESPONSE" | jq -r '.consumerSecret')

if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" = "null" ]; then
    log_error "Failed to generate keys"
    echo "$KEYS_RESPONSE" | jq '.'
    exit 1
fi

log_success "Keys generated successfully"
log_info "Client ID: $CLIENT_ID"
echo ""

# Step 3: Get token from WSO2 IS for ops_user
log_info "[3/5] Getting token from WSO2 IS for ops_user..."

TOKEN_RESPONSE=$(curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \
    -X POST "https://${IS_HOST}:${IS_PORT}/oauth2/token" \
    -d "grant_type=password&username=ops_user&password=OpsUser123!")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    log_error "Failed to get token from WSO2 IS"
    echo "$TOKEN_RESPONSE" | jq '.'
    
    # Cleanup
    curl -sk -u "admin:admin" -X DELETE \
        "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications/${APP_ID}" \
        >/dev/null 2>&1 || true
    
    exit 1
fi

log_success "Token obtained from WSO2 IS"
echo "Token: ${ACCESS_TOKEN:0:50}..."
echo ""

# Step 4: Subscribe to APIs
log_info "[4/5] Subscribing test application to APIs..."

# Get all APIs
ALL_APIS=$(curl -sk -u "admin:admin" \
    "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/apis?limit=100")

SUBSCRIPTION_COUNT=0

for api in "${APIS[@]}"; do
    API_ID=$(echo "$ALL_APIS" | jq -r ".list[] | select(.name | ascii_downcase | contains(\"${api}\")) | .id")
    
    if [ -n "$API_ID" ] && [ "$API_ID" != "null" ]; then
        SUB_RESPONSE=$(curl -sk -u "admin:admin" \
            -X POST "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/subscriptions" \
            -H "Content-Type: application/json" \
            -d "{
                \"apiId\": \"${API_ID}\",
                \"applicationId\": \"${APP_ID}\",
                \"throttlingPolicy\": \"Unlimited\"
            }" 2>/dev/null)
        
        if echo "$SUB_RESPONSE" | jq -e '.subscriptionId' >/dev/null 2>&1; then
            SUBSCRIPTION_COUNT=$((SUBSCRIPTION_COUNT + 1))
        fi
    fi
done

log_success "Subscribed to $SUBSCRIPTION_COUNT APIs"
echo ""

# Step 5: Test API calls through gateway
log_info "[5/5] Testing API calls through Gateway..."
echo ""

PASSED=0
FAILED=0

for api in "${APIS[@]}"; do
    API_URL="${GATEWAY_URL}/${api}/v1/health"
    
    RESPONSE=$(curl -sk -H "Authorization: Bearer ${ACCESS_TOKEN}" "$API_URL" 2>/dev/null)
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${ACCESS_TOKEN}" "$API_URL" 2>/dev/null)
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "   ${api}:    ✅ HTTP ${HTTP_CODE}"
        PASSED=$((PASSED + 1))
    else
        echo -e "   ${api}:    ❌ HTTP ${HTTP_CODE}"
        FAILED=$((FAILED + 1))
    fi
done

echo ""

# Summary
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Test Results                                             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Application ID:   $APP_ID"
echo "Client ID:        $CLIENT_ID"
echo "Client Secret:    ${CLIENT_SECRET:0:20}..."
echo "Key Manager:      WSO2-IS-KeyManager"
echo ""
echo "API Test Results: ${PASSED}/${#APIS[@]} passed"
echo ""

# Save credentials
CRED_FILE="/tmp/wso2is_integration_success.txt"
cat > "$CRED_FILE" <<EOF
═══════════════════════════════════════════════════════════
WSO2 IS Key Manager Integration Test - SUCCESS
═══════════════════════════════════════════════════════════

Application ID: ${APP_ID}
Application Name: ${TEST_APP_NAME}

Client ID: ${CLIENT_ID}
Client Secret: ${CLIENT_SECRET}

Key Manager: WSO2-IS-KeyManager
Token Endpoint: https://${IS_HOST}:${IS_PORT}/oauth2/token

Test Results: ${PASSED}/${#APIS[@]} APIs passed

Test Command:
curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \\
  -X POST "https://${IS_HOST}:${IS_PORT}/oauth2/token" \\
  -d "grant_type=password&username=ops_user&password=OpsUser123!"

═══════════════════════════════════════════════════════════
Generated: $(date)
═══════════════════════════════════════════════════════════
EOF

if [ $PASSED -eq ${#APIS[@]} ]; then
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  ✅ WSO2 IS Key Manager Integration SUCCESSFUL!            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Users can now:"
    echo "  ✅ Authenticate with WSO2 IS (ops_user, finance, etc.)"
    echo "  ✅ Get OAuth tokens from WSO2 IS"
    echo "  ✅ Access all APIs through WSO2 AM Gateway"
    echo ""
    log_success "Credentials saved to: $CRED_FILE"
    echo ""
    
    # Ask if user wants to delete test app
    read -p "Delete test application? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        curl -sk -u "admin:admin" -X DELETE \
            "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications/${APP_ID}" \
            >/dev/null 2>&1
        log_info "Test application deleted"
    fi
    
    exit 0
else
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  ⚠️  Some API tests failed                                 ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Check:"
    echo "  1. Are all APIs deployed? ./app_scripts/deploy_apis_to_gateway.sh"
    echo "  2. Are microservices running? docker compose ps"
    echo ""
    exit 1
fi
