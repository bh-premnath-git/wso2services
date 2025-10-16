#!/bin/bash

################################################################################
# Test All Users with All API Health Endpoints
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# OAuth Credentials
CLIENT_ID="eV6gdOIlD8XmYGZd7fuK47A4jmsa"
CLIENT_SECRET="dL60GCNtzxJUn1a2NAO7f6C5AjRHfjZRYXEGUzw059Ma"

# API endpoints
declare -a APIS=(
    "forex:https://localhost:8243/forex/v1/health"
    "wallet:https://localhost:8243/wallet/v1/health"
    "payment:https://localhost:8243/payment/v1/health"
    "profile:https://localhost:8243/profile/v1/health"
    "ledger:https://localhost:8243/ledger/v1/health"
    "rules:https://localhost:8243/rules/v1/health"
)

# Users to test
declare -A USERS=(
    [admin]="admin"
    [ops_user]="OpsUser123!"
    [finance]="Finance123!"
    [auditor]="Auditor123!"
    [user]="User1234!"
    [app_admin]="AppAdmin123!"
)

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Test All Users with All API Health Endpoints            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

for username in "${!USERS[@]}"; do
    password="${USERS[$username]}"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "👤 Testing User: $username"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Get token
    echo -e "${BLUE}[1/2]${NC} Getting OAuth token..."
    TOKEN_RESPONSE=$(curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \
        -X POST "https://localhost:9444/oauth2/token" \
        -d "grant_type=password&username=${username}&password=${password}" 2>/dev/null)
    
    TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
    
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo -e "${RED}❌ Failed to get token for $username${NC}"
        ERROR=$(echo "$TOKEN_RESPONSE" | jq -r '.error_description // .error')
        echo "   Error: $ERROR"
        echo ""
        
        # Count failed tests (1 for token + 6 for APIs)
        FAILED_TESTS=$((FAILED_TESTS + 7))
        TOTAL_TESTS=$((TOTAL_TESTS + 7))
        continue
    fi
    
    echo -e "${GREEN}✅ Token obtained${NC}"
    echo "   Token: ${TOKEN:0:50}..."
    echo ""
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    PASSED_TESTS=$((PASSED_TESTS + 1))
    
    # Test all APIs
    echo -e "${BLUE}[2/2]${NC} Testing API Gateway endpoints..."
    echo ""
    
    USER_API_PASSED=0
    USER_API_FAILED=0
    
    for api_entry in "${APIS[@]}"; do
        api_name="${api_entry%%:*}"
        api_url="${api_entry#*:}"
        
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        
        API_RESPONSE=$(curl -sk -H "Authorization: Bearer $TOKEN" \
            "$api_url" 2>/dev/null)
        
        if echo "$API_RESPONSE" | jq -e '.status' >/dev/null 2>&1; then
            STATUS=$(echo "$API_RESPONSE" | jq -r '.status')
            SERVICE=$(echo "$API_RESPONSE" | jq -r '.service')
            echo -e "   ${GREEN}✅${NC} $api_name: $STATUS ($SERVICE)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            USER_API_PASSED=$((USER_API_PASSED + 1))
        else
            echo -e "   ${RED}❌${NC} $api_name: Failed"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            USER_API_FAILED=$((USER_API_FAILED + 1))
        fi
    done
    
    echo ""
    echo "   User Summary: ${USER_API_PASSED}/6 APIs working"
    echo ""
done

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Test Results Summary                                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Total Tests:  $TOTAL_TESTS"
echo -e "${GREEN}Passed:${NC}       $PASSED_TESTS"
echo -e "${RED}Failed:${NC}       $FAILED_TESTS"
echo ""

SUCCESS_RATE=$(awk "BEGIN {printf \"%.1f\", ($PASSED_TESTS/$TOTAL_TESTS)*100}")
echo "Success Rate: ${SUCCESS_RATE}%"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ ALL TESTS PASSED!                                      ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "All users can:"
    echo "  ✅ Authenticate with WSO2 IS"
    echo "  ✅ Get OAuth tokens via password grant"
    echo "  ✅ Access all 6 API health endpoints"
    echo ""
    exit 0
else
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠️  SOME TESTS FAILED                                     ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. For failed users: Reset password via Console"
    echo "     https://localhost:9444/console"
    echo ""
    echo "  2. For API failures: Check if APIs are deployed"
    echo "     ./app_scripts/deploy_apis_to_gateway.sh"
    echo ""
    exit 1
fi
