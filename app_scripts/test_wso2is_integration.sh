#!/usr/bin/env bash

################################################################################
# Test WSO2 IS Key Manager Integration
#
# Tests the complete flow:
# 1. Generate keys with WSO2-IS-KeyManager
# 2. Get token from WSO2 IS
# 3. Call APIs through Gateway
#
# Usage: ./test_wso2is_integration.sh
################################################################################

set -eo pipefail

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
echo "║  WSO2 IS Key Manager - Integration Test                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Create test application
log_info "[1/5] Creating test application..."

TEST_APP=$(curl -sk -u "admin:admin" -X POST \
  "https://localhost:9443/api/am/devportal/v3/applications" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "WSO2ISTestApp",
    "throttlingPolicy": "Unlimited",
    "description": "Test application for WSO2-IS-KeyManager integration",
    "tokenType": "OAUTH"
  }')

TEST_APP_ID=$(echo "$TEST_APP" | jq -r '.applicationId')

if [ -z "$TEST_APP_ID" ] || [ "$TEST_APP_ID" = "null" ]; then
  log_error "Failed to create test application"
  echo "$TEST_APP" | jq '.'
  exit 1
fi

log_success "Test application created: $TEST_APP_ID"
echo ""

# Step 2: Generate keys with WSO2-IS-KeyManager
log_info "[2/5] Generating keys with WSO2-IS-KeyManager..."

GEN_RESP=$(curl -sk -u "admin:admin" -X POST \
  "https://localhost:9443/api/am/devportal/v3/applications/${TEST_APP_ID}/generate-keys" \
  -H "Content-Type: application/json" \
  -d '{
    "keyType": "PRODUCTION",
    "keyManager": "WSO2-IS-KeyManager",
    "grantTypesToBeSupported": ["password", "client_credentials", "refresh_token"],
    "callbackUrl": "https://localhost/callback",
    "validityTime": 3600
  }')

CLIENT_ID=$(echo "$GEN_RESP" | jq -r '.consumerKey')
CLIENT_SECRET=$(echo "$GEN_RESP" | jq -r '.consumerSecret')

if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" = "null" ]; then
  log_error "Failed to generate keys"
  echo "$GEN_RESP" | jq '.'
  
  if echo "$GEN_RESP" | grep -q "certificate"; then
    log_warning "SSL certificate error detected"
    echo ""
    echo "Run: ./app_scripts/fix_ssl_certificates.sh"
  fi
  
  # Cleanup
  curl -sk -u "admin:admin" -X DELETE \
    "https://localhost:9443/api/am/devportal/v3/applications/${TEST_APP_ID}" >/dev/null 2>&1
  exit 1
fi

log_success "Keys generated successfully"
log_info "Client ID: $CLIENT_ID"
echo ""

# Step 3: Get token from WSO2 IS
log_info "[3/5] Getting token from WSO2 IS for ops_user..."

TOKEN_RESP=$(curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \
  -d "grant_type=password&username=ops_user&password=OpsUser123!" \
  "https://localhost:9444/oauth2/token")

ACCESS_TOKEN=$(echo "$TOKEN_RESP" | jq -r '.access_token')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
  log_error "Failed to get token"
  echo "$TOKEN_RESP" | jq '.'
  
  # Cleanup
  curl -sk -u "admin:admin" -X DELETE \
    "https://localhost:9443/api/am/devportal/v3/applications/${TEST_APP_ID}" >/dev/null 2>&1
  exit 1
fi

log_success "Token obtained from WSO2 IS"
echo "Token: ${ACCESS_TOKEN:0:40}..."
echo ""

# Step 4: Subscribe to APIs
log_info "[4/5] Subscribing test application to APIs..."

# Get API list
APIS=$(curl -sk -u "admin:admin" \
  "https://localhost:9443/api/am/devportal/v3/apis?limit=10" | \
  jq -r '.list[] | .id')

SUB_COUNT=0
for API_ID in $APIS; do
  SUB_RESP=$(curl -sk -u "admin:admin" -X POST \
    "https://localhost:9443/api/am/devportal/v3/subscriptions" \
    -H "Content-Type: application/json" \
    -d "{
      \"applicationId\": \"${TEST_APP_ID}\",
      \"apiId\": \"${API_ID}\",
      \"throttlingPolicy\": \"Unlimited\"
    }" 2>/dev/null)
  
  if echo "$SUB_RESP" | jq -e '.subscriptionId' >/dev/null 2>&1; then
    SUB_COUNT=$((SUB_COUNT + 1))
  fi
done

log_success "Subscribed to $SUB_COUNT APIs"
echo ""

# Step 5: Test API calls
log_info "[5/5] Testing API calls through Gateway..."
echo ""

declare -a APIS=("forex" "profile" "wallet" "payment" "ledger" "rules")
SUCCESS_COUNT=0
FAIL_COUNT=0

for API in "${APIS[@]}"; do
  printf "   %-10s" "${API}:"
  
  API_RESP=$(curl -sk -w "\nHTTP_CODE:%{http_code}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "https://localhost:8243/${API}/v1/health" 2>/dev/null)
  
  HTTP_CODE=$(echo "$API_RESP" | grep "HTTP_CODE" | cut -d: -f2)
  
  if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ HTTP $HTTP_CODE${NC}"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo -e "${RED}❌ HTTP $HTTP_CODE${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Test Results                                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Application ID:   $TEST_APP_ID"
echo "Client ID:        $CLIENT_ID"
echo "Client Secret:    ${CLIENT_SECRET:0:20}..."
echo "Key Manager:      WSO2-IS-KeyManager"
echo ""
echo "API Test Results: ${SUCCESS_COUNT}/${#APIS[@]} passed"
echo ""

if [ "$SUCCESS_COUNT" -eq "${#APIS[@]}" ]; then
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║  ✅ WSO2 IS Key Manager Integration SUCCESSFUL!            ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Users can now:"
  echo "  ✅ Authenticate with WSO2 IS (ops_user, finance, etc.)"
  echo "  ✅ Get OAuth tokens from WSO2 IS"
  echo "  ✅ Access all APIs through WSO2 AM Gateway"
  echo ""
  echo "Save credentials:"
  cat > /tmp/wso2is_integration_success.txt << CREDS
# WSO2 IS Key Manager - Working Integration

APPLICATION_ID=${TEST_APP_ID}
CLIENT_ID=${CLIENT_ID}
CLIENT_SECRET=${CLIENT_SECRET}
KEY_MANAGER=WSO2-IS-KeyManager

# Get token:
TOKEN=\$(curl -sk -u "\${CLIENT_ID}:\${CLIENT_SECRET}" \\
  -d "grant_type=password&username=ops_user&password=OpsUser123!" \\
  https://localhost:9444/oauth2/token | jq -r '.access_token')

# Call API:
curl -k -H "Authorization: Bearer \$TOKEN" \\
  https://localhost:8243/forex/v1/health
CREDS
  
  log_success "Credentials saved to: /tmp/wso2is_integration_success.txt"
  echo ""
  
  # Optionally delete test app
  read -p "Delete test application? (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    curl -sk -u "admin:admin" -X DELETE \
      "https://localhost:9443/api/am/devportal/v3/applications/${TEST_APP_ID}" >/dev/null 2>&1
    log_info "Test application deleted"
  else
    log_info "Test application kept for further testing"
  fi
  
  exit 0
else
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║  ⚠️  Integration Test FAILED                               ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""
  log_warning "$FAIL_COUNT APIs failed"
  echo ""
  echo "Troubleshooting:"
  echo "  1. Check API subscriptions"
  echo "  2. Verify token validation settings"
  echo "  3. Check Gateway logs: docker compose logs wso2am | tail -50"
  echo ""
  
  # Cleanup
  read -p "Delete test application? (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    curl -sk -u "admin:admin" -X DELETE \
      "https://localhost:9443/api/am/devportal/v3/applications/${TEST_APP_ID}" >/dev/null 2>&1
    log_info "Test application deleted"
  fi
  
  exit 1
fi
