#!/usr/bin/env bash

################################################################################
# Quick Script to Subscribe All APIs to Latest Test Application
################################################################################

set -euo pipefail

APIM_HOST="localhost"
APIM_PORT="9443"
ADMIN_USER="admin"
ADMIN_PASS="admin"

# Accept APP_ID as argument
APP_ID="${1:-}"

if [ -z "$APP_ID" ]; then
    echo "Fetching test applications..."
    APP_LIST=$(curl -k -sS -X GET "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications?limit=10" -u "${ADMIN_USER}:${ADMIN_PASS}")

    # Get the most recent TestApp
    APP_ID=$(echo "$APP_LIST" | jq -r '.list[] | select(.name | startswith("TestApp")) | .applicationId' | head -1)
else
    # Fetch app details to get name
    APP_LIST=$(curl -k -sS -X GET "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications/${APP_ID}" -u "${ADMIN_USER}:${ADMIN_PASS}")
    APP_NAME=$(echo "$APP_LIST" | jq -r ".name")
fi

if [ -z "$APP_ID" ] || [ "$APP_ID" = "null" ]; then
    echo "ERROR: No test application found!"
    if [ -n "${APP_LIST}" ]; then
        echo "Available applications:"
        echo "$APP_LIST" | jq -r '.list[] | "\(.name) - \(.applicationId)"' 2>/dev/null || echo "$APP_LIST"
    fi
    exit 1
fi

echo "Using Application ID: ${APP_ID}"
if [ -z "$APP_NAME" ]; then
    APP_NAME=$(echo "$APP_LIST" | jq -r ".list[] | select(.applicationId == \"$APP_ID\") | .name")
fi
echo "Application Name: ${APP_NAME}"
echo ""

# API names
apis=("ForexService" "LedgerService" "PaymentService" "ProfileService" "RuleEngineService" "WalletService" "BankingService")

failed=0
for api_name in "${apis[@]}"; do
    echo "Subscribing to ${api_name}..."
    
    # Get API ID
    API_RESPONSE=$(curl -k -sS -X GET "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/apis?query=name:${api_name}" -u "${ADMIN_USER}:${ADMIN_PASS}")
    API_ID=$(echo "$API_RESPONSE" | jq -r '.list[0].id // empty')
    
    if [ -z "$API_ID" ] || [ "$API_ID" = "null" ]; then
        echo "  ⚠ ${api_name} not found - skipped"
        failed=$((failed + 1))
        continue
    fi
    
    # Check if already subscribed
    EXISTING_SUB=$(curl -k -sS -X GET "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/subscriptions?apiId=${API_ID}&applicationId=${APP_ID}" -u "${ADMIN_USER}:${ADMIN_PASS}")
    SUB_COUNT=$(echo "$EXISTING_SUB" | jq -r '.count // 0')
    
    if [ "$SUB_COUNT" -gt 0 ]; then
        echo "  ✓ Already subscribed to ${api_name}"
        continue
    fi
    
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
        echo "$RESULT" | jq . 2>/dev/null || echo "$RESULT"
        failed=$((failed + 1))
    fi
done

echo ""
if [ $failed -eq 0 ]; then
    echo "✅ All subscriptions completed successfully!"
    echo ""
    echo "Verify subscriptions:"
    curl -k -sS -X GET "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/subscriptions?applicationId=${APP_ID}" -u "${ADMIN_USER}:${ADMIN_PASS}" | jq '.list[] | {api: .apiInfo.name, status: .status}'
    exit 0
else
    echo "⚠️  Subscriptions completed with ${failed} failures"
    echo ""
    echo "Verify subscriptions:"
    curl -k -sS -X GET "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/subscriptions?applicationId=${APP_ID}" -u "${ADMIN_USER}:${ADMIN_PASS}" | jq '.list[] | {api: .apiInfo.name, status: .status}'
    exit 1
fi
