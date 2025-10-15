#!/usr/bin/env bash

################################################################################
# Setup Application Keys with WSO2 IS Key Manager
#
# This script:
# 1. Removes any existing application keys (Resident Key Manager)
# 2. Creates OAuth client in WSO2 IS
# 3. Maps OAuth client to APIM application
# 4. Tests the complete flow
#
# Usage: ./setup_application_keys_with_is.sh
################################################################################

set -eo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
APP_ID="d5701bf3-8569-4c05-beff-9f8d4a9fd5b9"
APP_NAME="AllServicesApp"
APIM_HOST="${APIM_HOST:-localhost}"
APIM_PORT="${APIM_PORT:-9443}"
IS_HOST="${IS_HOST:-localhost}"
IS_PORT="${IS_PORT:-9444}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Setup Application Keys with WSO2 IS                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Remove existing keys
log_info "[1/4] Removing existing application keys..."
EXISTING_KEYS=$(curl -sk -u "admin:admin" \
  "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications/${APP_ID}/oauth-keys" | \
  jq -r '.list[] | .keyMappingId')

if [ -n "$EXISTING_KEYS" ]; then
  for KEY_ID in $EXISTING_KEYS; do
    log_info "Deleting key mapping: $KEY_ID"
    curl -sk -u "admin:admin" -X DELETE \
      "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications/${APP_ID}/oauth-keys/${KEY_ID}" \
      2>/dev/null || true
  done
  log_success "Existing keys removed"
else
  log_info "No existing keys found"
fi
echo ""

# Step 2: Create OAuth client in WSO2 IS
log_info "[2/4] Creating OAuth client in WSO2 IS..."

# Check if client already exists and delete it
EXISTING_CLIENT=$(curl -sk -u "admin:admin" \
  "https://${IS_HOST}:${IS_PORT}/api/identity/oauth2/dcr/v1.1/applications" 2>/dev/null | \
  jq -r ".applications[] | select(.client_name==\"${APP_NAME}_Production\") | .client_id" || echo "")

if [ -n "$EXISTING_CLIENT" ]; then
  log_warning "Deleting existing OAuth client: $EXISTING_CLIENT"
  curl -sk -u "admin:admin" -X DELETE \
    "https://${IS_HOST}:${IS_PORT}/api/identity/oauth2/dcr/v1.1/register/${EXISTING_CLIENT}" \
    2>/dev/null || true
  sleep 1
fi

# Create new OAuth client
DCR_RESP=$(curl -sk -u "admin:admin" -X POST \
  "https://${IS_HOST}:${IS_PORT}/api/identity/oauth2/dcr/v1.1/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"client_name\": \"${APP_NAME}_Production\",
    \"grant_types\": [\"password\", \"client_credentials\", \"refresh_token\"],
    \"redirect_uris\": [\"https://localhost/callback\"],
    \"ext_application_owner\": \"admin\",
    \"ext_application_token_lifetime\": 3600
  }")

CLIENT_ID=$(echo "$DCR_RESP" | jq -r '.client_id')
CLIENT_SECRET=$(echo "$DCR_RESP" | jq -r '.client_secret')

if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" = "null" ]; then
  log_error "Failed to create OAuth client in WSO2 IS"
  echo "$DCR_RESP" | jq '.'
  exit 1
fi

log_success "OAuth client created in WSO2 IS"
log_info "Client ID: $CLIENT_ID"
echo ""

# Step 3: Map OAuth client to APIM application
log_info "[3/4] Mapping OAuth client to APIM application..."

MAP_RESP=$(curl -sk -u "admin:admin" -X POST \
  "https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3/applications/${APP_ID}/map-keys" \
  -H "Content-Type: application/json" \
  -d "{
    \"keyType\": \"PRODUCTION\",
    \"keyManager\": \"WSO2-IS-KeyManager\",
    \"consumerKey\": \"${CLIENT_ID}\",
    \"consumerSecret\": \"${CLIENT_SECRET}\"
  }")

if echo "$MAP_RESP" | jq -e '.consumerKey' >/dev/null 2>&1; then
  log_success "OAuth keys mapped to application"
else
  log_error "Failed to map keys to application"
  echo "$MAP_RESP" | jq '.'
  exit 1
fi
echo ""

# Step 4: Test the integration
log_info "[4/4] Testing integration..."
echo ""

log_info "Test 1: Getting token from WSO2 IS for ops_user..."
TOKEN_RESP=$(curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \
  -d "grant_type=password&username=ops_user&password=OpsUser123!" \
  "https://${IS_HOST}:${IS_PORT}/oauth2/token")

ACCESS_TOKEN=$(echo "$TOKEN_RESP" | jq -r '.access_token')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
  log_error "Failed to get token from WSO2 IS"
  echo "$TOKEN_RESP" | jq '.'
  exit 1
fi

log_success "Token obtained from WSO2 IS"
echo "   Token: ${ACCESS_TOKEN:0:40}..."
echo ""

log_info "Test 2: Calling APIs through WSO2 AM Gateway..."
echo ""

# Test APIs
declare -a APIS=("forex" "profile" "wallet" "payment" "ledger" "rules")
SUCCESS_COUNT=0

for API in "${APIS[@]}"; do
  printf "   %-10s" "${API}:"
  
  HTTP_CODE=$(curl -sk -w "%{http_code}" -o /dev/null \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "https://${APIM_HOST}:8243/${API}/v1/health" 2>/dev/null)
  
  if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ HTTP $HTTP_CODE${NC}"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo -e "${RED}❌ HTTP $HTTP_CODE${NC}"
  fi
done

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Setup Complete                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

echo "Results: ${SUCCESS_COUNT}/${#APIS[@]} APIs working with WSO2 IS tokens"
echo ""
echo "Application Configuration:"
echo "  Application ID:   $APP_ID"
echo "  Application Name: $APP_NAME"
echo "  Client ID:        $CLIENT_ID"
echo "  Client Secret:    $CLIENT_SECRET"
echo "  Key Manager:      WSO2-IS-KeyManager"
echo ""
echo "Token Endpoint: https://${IS_HOST}:${IS_PORT}/oauth2/token"
echo "Gateway URL:    https://${APIM_HOST}:8243"
echo ""
echo "Test Users (from WSO2 IS):"
echo "  - ops_user  / OpsUser123!"
echo "  - finance   / Finance123!"
echo "  - auditor   / Auditor123!"
echo "  - user      / User1234!"
echo "  - app_admin / AppAdmin123!"
echo ""
echo "Usage Example:"
echo "  # Get token from WSO2 IS"
echo "  TOKEN=\$(curl -sk -u \"${CLIENT_ID}:${CLIENT_SECRET}\" \\"
echo "    -d \"grant_type=password&username=ops_user&password=OpsUser123!\" \\"
echo "    https://${IS_HOST}:${IS_PORT}/oauth2/token | jq -r '.access_token')"
echo ""
echo "  # Call API through Gateway"
echo "  curl -k -H \"Authorization: Bearer \$TOKEN\" \\"
echo "    https://${APIM_HOST}:8243/forex/v1/health"
echo ""

# Save credentials
CREDS_FILE="/tmp/wso2_is_app_credentials.txt"
cat > "$CREDS_FILE" << EOF
# WSO2 Identity Server Application Credentials
CLIENT_ID=${CLIENT_ID}
CLIENT_SECRET=${CLIENT_SECRET}
APP_ID=${APP_ID}
KEY_MANAGER=WSO2-IS-KeyManager
TOKEN_ENDPOINT=https://${IS_HOST}:${IS_PORT}/oauth2/token
GATEWAY_URL=https://${APIM_HOST}:8243
EOF

log_success "Credentials saved to: $CREDS_FILE"
echo ""

if [ "$SUCCESS_COUNT" -eq "${#APIS[@]}" ]; then
  log_success "All APIs working with WSO2 IS authentication!"
  exit 0
else
  log_warning "Some APIs failed. Troubleshooting:"
  echo "  1. Check WSO2 AM logs: docker compose logs wso2am | grep -i error"
  echo "  2. Verify Key Manager: https://localhost:9443/admin (Admin Portal → Key Managers)"
  echo "  3. Test introspection: curl -sk -u admin:admin -d \"token=\$TOKEN\" https://localhost:9444/oauth2/introspect"
  exit 1
fi
