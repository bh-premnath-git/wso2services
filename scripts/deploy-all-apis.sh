#!/usr/bin/env bash

################################################################################
# Deploy All APIs to Gateway
# Creates revisions and deploys all APIs to the Default gateway environment
################################################################################

set -euo pipefail

APIM_HOST="localhost"
APIM_PORT="9443"
ADMIN_USER="admin"
ADMIN_PASS="admin"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║          Deploying All APIs to Gateway                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Get available gateway environments
echo "=== Available Gateway Environments ==="
ENVS=$(curl -k -sS "https://${APIM_HOST}:${APIM_PORT}/api/am/admin/v4/environments" -u "${ADMIN_USER}:${ADMIN_PASS}")
echo "$ENVS" | jq -r '.list[] | "  • \(.name) (\(.displayName)) - \(.gatewayType)"'

DEFAULT_ENV=$(echo "$ENVS" | jq -r '.list[] | select(.name == "Default") | .name')

if [ -z "$DEFAULT_ENV" ] || [ "$DEFAULT_ENV" = "null" ]; then
    echo "ERROR: Default gateway environment not found!"
    exit 1
fi

echo "Using environment: ${DEFAULT_ENV}"

echo ""
echo "=== Fetching All APIs ==="
APIS_RESPONSE=$(curl -k -sS "https://${APIM_HOST}:${APIM_PORT}/api/am/publisher/v4/apis?limit=20" -u "${ADMIN_USER}:${ADMIN_PASS}")

API_COUNT=$(echo "$APIS_RESPONSE" | jq -r '.count // 0')
echo "Found ${API_COUNT} APIs"
echo ""

if [ "$API_COUNT" -eq 0 ]; then
    echo "No APIs to deploy"
    exit 0
fi

# API names we care about
api_names=("ForexService" "LedgerService" "PaymentService" "ProfileService" "RuleEngineService" "WalletService" "BankingService")

deployed=0
skipped=0
failed=0

for api_name in "${api_names[@]}"; do
    echo "Processing ${api_name}..."
    
    # Get API ID and details
    API_DATA=$(echo "$APIS_RESPONSE" | jq -r ".list[] | select(.name == \"${api_name}\")")
    
    if [ -z "$API_DATA" ] || [ "$API_DATA" = "null" ]; then
        echo "  ⚠ ${api_name} not found - skipped"
        skipped=$((skipped + 1))
        continue
    fi
    
    API_ID=$(echo "$API_DATA" | jq -r '.id')
    LIFECYCLE=$(echo "$API_DATA" | jq -r '.lifeCycleStatus')
    
    # Publish API if not already published
    if [ "$LIFECYCLE" != "PUBLISHED" ]; then
        echo "  → API in ${LIFECYCLE} state, publishing..."
        PUBLISH_RESPONSE=$(curl -k -sS -X POST \
            "https://${APIM_HOST}:${APIM_PORT}/api/am/publisher/v4/apis/change-lifecycle?apiId=${API_ID}&action=Publish" \
            -u "${ADMIN_USER}:${ADMIN_PASS}" \
            -H "Content-Type: application/json")
        
        if echo "$PUBLISH_RESPONSE" | jq -e '.lifeCycleStatus' >/dev/null 2>&1; then
            NEW_STATE=$(echo "$PUBLISH_RESPONSE" | jq -r '.lifeCycleStatus')
            echo "  ✓ API published (State: ${NEW_STATE})"
        else
            echo "  ⚠ Failed to publish ${api_name}, attempting deployment anyway..."
            echo "$PUBLISH_RESPONSE" | jq . 2>/dev/null || echo "$PUBLISH_RESPONSE"
        fi
    else
        echo "  ✓ API already published"
    fi
    
    # Check current deployment status
    DEPLOYMENTS=$(curl -k -sS "https://${APIM_HOST}:${APIM_PORT}/api/am/publisher/v4/apis/${API_ID}/deployments" \
        -u "${ADMIN_USER}:${ADMIN_PASS}")
    
    DEPLOYMENT_COUNT=$(echo "$DEPLOYMENTS" | jq -r 'length')
    
    if [ "$DEPLOYMENT_COUNT" -gt 0 ]; then
        echo "  ✓ ${api_name} already deployed - skipped"
        skipped=$((skipped + 1))
        continue
    fi
    
    # Create a revision
    echo "  → Creating revision..."
    REVISION_RESPONSE=$(curl -k -sS -X POST \
        "https://${APIM_HOST}:${APIM_PORT}/api/am/publisher/v4/apis/${API_ID}/revisions" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d '{
            "description": "Auto-generated revision for deployment"
        }')
    
    REVISION_ID=$(echo "$REVISION_RESPONSE" | jq -r '.id // empty')
    
    if [ -z "$REVISION_ID" ] || [ "$REVISION_ID" = "null" ]; then
        echo "  ✗ Failed to create revision for ${api_name}"
        echo "$REVISION_RESPONSE" | jq .
        failed=$((failed + 1))
        continue
    fi
    
    echo "  → Revision created: ${REVISION_ID}"
    
    # Deploy the revision to Default gateway with vhost
    echo "  → Deploying to Default gateway..."
    DEPLOY_RESPONSE=$(curl -k -sS -X POST \
        "https://${APIM_HOST}:${APIM_PORT}/api/am/publisher/v4/apis/${API_ID}/deploy-revision?revisionId=${REVISION_ID}" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d '[{
            "name": "Default",
            "vhost": "localhost",
            "displayOnDevportal": true
        }]')
    
    if echo "$DEPLOY_RESPONSE" | jq -e '.[0].revisionUuid' >/dev/null 2>&1; then
        DEPLOY_STATUS=$(echo "$DEPLOY_RESPONSE" | jq -r '.[0].status')
        echo "  ✓ ${api_name} deployed successfully! (Status: ${DEPLOY_STATUS})"
        deployed=$((deployed + 1))
    else
        echo "  ✗ Failed to deploy ${api_name}"
        echo "$DEPLOY_RESPONSE" | jq .
        failed=$((failed + 1))
    fi
    
    echo ""
done

echo "╔════════════════════════════════════════════════════════════╗"
echo "║                  Deployment Summary                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Deployed: ${deployed}"
echo "Skipped:  ${skipped}"
echo "Failed:   ${failed}"
echo ""

if [ $failed -eq 0 ]; then
    echo "✅ All APIs are deployed to the gateway!"
    exit 0
else
    echo "⚠️  Some APIs failed to deploy"
    exit 1
fi
