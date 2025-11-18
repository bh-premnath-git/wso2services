#!/usr/bin/env bash

################################################################################
# Quick Script to Subscribe All APIs to Latest Test Application
################################################################################

set -euo pipefail

APIM_HOST="localhost"
APIM_PORT="9443"
ADMIN_USER="admin"
ADMIN_PASS="admin"

echo "Fetching test applications..."
APP_LIST=$(curl -k -sS -X GET "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications?limit=10" -u "${ADMIN_USER}:${ADMIN_PASS}")

# Get the most recent TestApp
APP_ID=$(echo "$APP_LIST" | jq -r '.list[] | select(.name | startswith("TestApp")) | .applicationId' | head -1)

if [ -z "$APP_ID" ] || [ "$APP_ID" = "null" ]; then
    echo "ERROR: No test application found!"
    echo "Available applications:"
    echo "$APP_LIST" | jq -r '.list[] | "\(.name) - \(.applicationId)"'
    exit 1
fi

echo "Using Application ID: ${APP_ID}"
APP_NAME=$(echo "$APP_LIST" | jq -r ".list[] | select(.applicationId == \"$APP_ID\") | .name")
echo "Application Name: ${APP_NAME}"
echo ""

# API names
apis=("ForexService" "LedgerService" "PaymentService" "ProfileService" "RuleEngineService" "WalletService" "BankingService")

for api_name in "${apis[@]}"; do
    echo "Subscribing to ${api_name}..."
    
    # Get API ID
    API_ID=$(curl -k -sS -X GET "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/apis?query=name:${api_name}" -u "${ADMIN_USER}:${ADMIN_PASS}" | jq -r '.list[0].id')
    
    # Subscribe
    RESULT=$(curl -k -sS -X POST "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/subscriptions" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d "{
            \"apiId\": \"${API_ID}\",
            \"applicationId\": \"${APP_ID}\",
            \"throttlingPolicy\": \"Unlimited\"
        }")
    
    if echo "$RESULT" | jq -e '.subscriptionId' >/dev/null 2>&1; then
        echo "  ✓ Subscribed to ${api_name}"
    else
        echo "  ✗ Failed: ${api_name}"
        echo "$RESULT" | jq .
    fi
done

echo ""
echo "✅ All subscriptions completed!"
echo ""
echo "Verify subscriptions:"
curl -k -sS -X GET "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/subscriptions?applicationId=${APP_ID}" -u "${ADMIN_USER}:${ADMIN_PASS}" | jq '.list[] | {api: .apiInfo.name, status: .status}'
