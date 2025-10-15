#!/usr/bin/env bash

################################################################################
# WSO2 API Gateway - Test Script
#
# Tests calling microservices through WSO2 API Gateway with OAuth tokens
# Uses WSO2 IS Key Manager for authentication
#
# Usage: ./test_api_gateway.sh [username] [password]
################################################################################

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

USERNAME="${1:-ops_user}"
PASSWORD="${2:-OpsUser123!}"

GATEWAY_URL="https://localhost:8243"
IS_TOKEN_URL="https://localhost:9444/oauth2/token"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  WSO2 API Gateway Test - User: $USERNAME"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check if credentials file exists
if [ ! -f /tmp/apim_credentials.txt ]; then
  log_error "Application credentials not found!"
  log_info "Please run: ./app_scripts/register_apis.sh first"
  exit 1
fi

CREDENTIALS=$(cat /tmp/apim_credentials.txt)
CONSUMER_KEY=$(echo "$CREDENTIALS" | cut -d: -f1)
CONSUMER_SECRET=$(echo "$CREDENTIALS" | cut -d: -f2)

log_info "Using application credentials from WSO2 IS Key Manager"
echo ""

# Step 1: Get access token using password grant (user authentication)
log_info "Step 1: Getting access token for user: $USERNAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

TOKEN_RESPONSE=$(curl -sk -u "${CONSUMER_KEY}:${CONSUMER_SECRET}" \
  -d "grant_type=password&username=${USERNAME}&password=${PASSWORD}&scope=default" \
  "$IS_TOKEN_URL" 2>/dev/null)

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

if [ -z "$ACCESS_TOKEN" ]; then
  log_error "Failed to get access token"
  echo "$TOKEN_RESPONSE" | jq '.'
  exit 1
fi

EXPIRES_IN=$(echo "$TOKEN_RESPONSE" | jq -r '.expires_in')
log_success "Access token obtained"
echo "Token: ${ACCESS_TOKEN:0:40}..."
echo "Expires in: $EXPIRES_IN seconds"
echo ""

# Step 2: Call APIs through gateway
log_info "Step 2: Testing API calls through WSO2 API Gateway"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

declare -A APIS=(
  ["Forex Service"]="/forex/v1/health"
  ["Profile Service"]="/profile/v1/health"
  ["Payment Service"]="/payment/v1/health"
  ["Ledger Service"]="/ledger/v1/health"
  ["Wallet Service"]="/wallet/v1/health"
  ["Rule Engine Service"]="/rules/v1/health"
)

SUCCESS_COUNT=0
FAIL_COUNT=0

for api_name in "${!APIS[@]}"; do
  endpoint="${APIS[$api_name]}"
  
  echo -n "Testing $api_name... "
  
  RESPONSE=$(curl -sk -w "\nHTTP_CODE:%{http_code}" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "${GATEWAY_URL}${endpoint}" 2>/dev/null)
  
  HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
  BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE/d')
  
  if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ OK${NC} (HTTP $HTTP_CODE)"
    ((SUCCESS_COUNT++))
  else
    echo -e "${RED}❌ FAILED${NC} (HTTP $HTTP_CODE)"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    ((FAIL_COUNT++))
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Summary:"
echo "  ✅ Passed: $SUCCESS_COUNT"
echo "  ❌ Failed: $FAIL_COUNT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Show example curl commands
echo "Example API calls:"
echo ""
echo "# Export token"
echo "export TOKEN=\"$ACCESS_TOKEN\""
echo ""
echo "# Call Forex Service"
echo "curl -k -H \"Authorization: Bearer \$TOKEN\" \\"
echo "  ${GATEWAY_URL}/forex/v1/health"
echo ""
echo "# Call Profile Service"
echo "curl -k -H \"Authorization: Bearer \$TOKEN\" \\"
echo "  ${GATEWAY_URL}/profile/v1/health"
echo ""
echo "# Call with different user"
echo "./app_scripts/test_api_gateway.sh finance Finance123!"
echo ""

if [ $SUCCESS_COUNT -eq ${#APIS[@]} ]; then
  log_success "All API tests passed! Gateway is working correctly."
  exit 0
else
  log_error "Some API tests failed. Check API registration and service health."
  exit 1
fi
