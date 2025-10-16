#!/usr/bin/env bash

################################################################################
# WSO2 API Manager - API Registration Script
#
# Registers microservices as APIs in WSO2 API Manager with WSO2 IS Key Manager
# Creates applications, subscriptions, and generates OAuth tokens
#
# Usage: ./register_apis.sh
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
APIM_HOST="${APIM_HOST:-localhost}"
APIM_PORT="${APIM_PORT:-9443}"
APIM_BASE="https://${APIM_HOST}:${APIM_PORT}"
GATEWAY_URL="https://localhost:8243"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin}"

# Check dependencies
for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} Missing required command: $cmd"
    exit 1
  fi
done

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  WSO2 API Manager - API Registration                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Use Basic Auth for API Manager REST API
log_info "Using Basic Authentication with API Manager..."
AUTH_HEADER="Authorization: Basic $(echo -n "${ADMIN_USER}:${ADMIN_PASS}" | base64)"
log_success "Authentication configured"
echo ""

# Microservices configuration (matching docker-compose ports)
declare -A SERVICES=(
  ["Forex-Service-API"]="forex-service:8001:/forex:v1:Forex rate conversion service"
  ["Profile-Service-API"]="profile-service:8004:/profile:v1:User profile management service"
  ["Payment-Service-API"]="payment-service:8003:/payment:v1:Payment processing service"
  ["Ledger-Service-API"]="ledger-service:8002:/ledger:v1:Financial ledger service"
  ["Wallet-Service-API"]="wallet-service:8006:/wallet:v1:Digital wallet service"
  ["Rule-Engine-Service-API"]="rule-engine-service:8005:/rules:v1:Business rules engine service"
)

declare -A API_IDS

# Create and publish APIs
log_info "Creating and publishing APIs..."
echo ""

for api_name in "${!SERVICES[@]}"; do
  IFS=':' read -r backend_host backend_port context version description <<< "${SERVICES[$api_name]}"
  
  log_info "Processing: $api_name"
  
  # Check if API already exists
  EXISTING_API=$(curl -sk -H "$AUTH_HEADER" \
    "${APIM_BASE}/api/am/publisher/v4/apis?query=name:${api_name}" 2>/dev/null | jq -r '.list[0].id // empty')
  
  if [ -n "$EXISTING_API" ]; then
    log_warning "API already exists: $api_name (ID: $EXISTING_API)"
    API_IDS[$api_name]=$EXISTING_API
    continue
  fi
  
  # Create API
  API_PAYLOAD=$(cat <<EOF
{
  "name": "$api_name",
  "context": "$context",
  "version": "$version",
  "description": "$description",
  "type": "HTTP",
  "transport": ["http", "https"],
  "visibility": "PUBLIC",
  "endpointConfig": {
    "endpoint_type": "http",
    "production_endpoints": {
      "url": "http://${backend_host}:${backend_port}"
    },
    "sandbox_endpoints": {
      "url": "http://${backend_host}:${backend_port}"
    }
  },
  "operations": [
    {
      "target": "/health",
      "verb": "GET",
      "authType": "None",
      "throttlingPolicy": "Unlimited"
    },
    {
      "target": "/*",
      "verb": "GET",
      "authType": "Application & Application User",
      "throttlingPolicy": "Unlimited"
    },
    {
      "target": "/*",
      "verb": "POST",
      "authType": "Application & Application User",
      "throttlingPolicy": "Unlimited"
    },
    {
      "target": "/*",
      "verb": "PUT",
      "authType": "Application & Application User",
      "throttlingPolicy": "Unlimited"
    },
    {
      "target": "/*",
      "verb": "DELETE",
      "authType": "Application & Application User",
      "throttlingPolicy": "Unlimited"
    }
  ],
  "policies": ["Unlimited"],
  "corsConfiguration": {
    "corsConfigurationEnabled": true,
    "accessControlAllowOrigins": ["*"],
    "accessControlAllowHeaders": ["authorization", "content-type"],
    "accessControlAllowMethods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
  }
}
EOF
)
  
  CREATE_RESPONSE=$(curl -sk -X POST \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d "$API_PAYLOAD" \
    "${APIM_BASE}/api/am/publisher/v4/apis" 2>/dev/null)
  
  API_ID=$(echo "$CREATE_RESPONSE" | jq -r '.id // empty')
  
  if [ -z "$API_ID" ]; then
    log_error "Failed to create API: $api_name"
    echo "$CREATE_RESPONSE" | jq '.'
    continue
  fi
  
  API_IDS[$api_name]=$API_ID
  log_success "Created: $api_name (ID: $API_ID)"
  
  # Publish API
  curl -sk -X POST \
    -H "$AUTH_HEADER" \
    "${APIM_BASE}/api/am/publisher/v4/apis/change-lifecycle?apiId=${API_ID}&action=Publish" \
    >/dev/null 2>&1
  
  log_success "Published: $api_name"
  echo ""
done

log_success "All APIs created and published"
echo ""

# Create Application
log_info "Creating application: AllServicesApp"

APP_CHECK=$(curl -sk -H "$AUTH_HEADER" \
  "${APIM_BASE}/api/am/devportal/v3/applications?query=name:AllServicesApp" 2>/dev/null | jq -r '.list[0].applicationId // empty')

if [ -n "$APP_CHECK" ]; then
  log_warning "Application already exists: AllServicesApp (ID: $APP_CHECK)"
  APP_ID=$APP_CHECK
else
  APP_RESPONSE=$(curl -sk -X POST \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "AllServicesApp",
      "throttlingPolicy": "Unlimited",
      "description": "Application for all microservices",
      "tokenType": "JWT"
    }' \
    "${APIM_BASE}/api/am/devportal/v3/applications" 2>/dev/null)
  
  APP_ID=$(echo "$APP_RESPONSE" | jq -r '.applicationId // empty')
  
  if [ -z "$APP_ID" ]; then
    log_error "Failed to create application"
    echo "$APP_RESPONSE" | jq '.'
    exit 1
  fi
  
  log_success "Application created: $APP_ID"
fi

echo ""

# Subscribe application to all APIs
log_info "Subscribing application to APIs..."

for api_name in "${!API_IDS[@]}"; do
  api_id="${API_IDS[$api_name]}"
  
  SUB_RESPONSE=$(curl -sk -X POST \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d "{
      \"apiId\": \"$api_id\",
      \"applicationId\": \"$APP_ID\",
      \"throttlingPolicy\": \"Unlimited\"
    }" \
    "${APIM_BASE}/api/am/devportal/v3/subscriptions" 2>/dev/null)
  
  if echo "$SUB_RESPONSE" | jq -e '.subscriptionId' >/dev/null 2>&1; then
    log_success "Subscribed to: $api_name"
  else
    log_warning "Already subscribed to: $api_name"
  fi
done

echo ""

# First verify Key Manager is available and configured
log_info "Verifying WSO2-IS-KeyManager is available..."
KM_LIST=$(curl -sk -H "$AUTH_HEADER" \
  "${APIM_BASE}/api/am/admin/v4/key-managers" 2>/dev/null)

KM_EXISTS=$(echo "$KM_LIST" | jq -r '.list[] | select(.name=="WSO2-IS-KeyManager") | .name' || echo "")

if [ "$KM_EXISTS" != "WSO2-IS-KeyManager" ]; then
  log_error "WSO2-IS-KeyManager not found in APIM"
  echo "Available Key Managers:"
  echo "$KM_LIST" | jq -r '.list[].name'
  exit 1
fi

log_success "WSO2-IS-KeyManager is registered"

# Generate keys using WSO2 IS Key Manager
log_info "Generating OAuth keys with WSO2 IS Key Manager..."

# Retry logic for key generation (Key Manager might need a moment to sync)
MAX_RETRIES=3
RETRY_COUNT=0
CONSUMER_KEY=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ -z "$CONSUMER_KEY" ]; do
  if [ $RETRY_COUNT -gt 0 ]; then
    log_warning "Retry attempt $RETRY_COUNT/$MAX_RETRIES after 10 seconds..."
    sleep 10
  fi
  
  KEYS_RESPONSE=$(curl -sk -X POST \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d '{
      "keyType": "PRODUCTION",
      "keyManager": "WSO2-IS-KeyManager",
      "grantTypesToBeSupported": ["client_credentials", "password"],
      "validityTime": 3600,
      "scopes": ["default"]
    }' \
    "${APIM_BASE}/api/am/devportal/v3/applications/${APP_ID}/keys/PRODUCTION/generate" 2>/dev/null)

  CONSUMER_KEY=$(echo "$KEYS_RESPONSE" | jq -r '.consumerKey // empty')
  CONSUMER_SECRET=$(echo "$KEYS_RESPONSE" | jq -r '.consumerSecret // empty')
  
  RETRY_COUNT=$((RETRY_COUNT + 1))
done

if [ -z "$CONSUMER_KEY" ]; then
  log_error "Failed to generate keys after $MAX_RETRIES attempts"
  echo ""
  echo "Response from APIM:"
  echo "$KEYS_RESPONSE" | jq '.'
  echo ""
  log_error "Possible causes:"
  echo "  1. WSO2-IS-KeyManager not fully synced (wait longer)"
  echo "  2. Key Manager endpoint not reachable from APIM"
  echo "  3. SSL certificate issues between APIM and IS"
  echo ""
  echo "Check WSO2 AM logs:"
  echo "  docker compose logs wso2am | tail -50"
  echo ""
  exit 1
fi

log_success "OAuth keys generated"
echo ""

# Display summary
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Registration Complete                                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Application: AllServicesApp"
echo "Consumer Key: $CONSUMER_KEY"
echo "Consumer Secret: $CONSUMER_SECRET"
echo ""
echo "APIs Registered:"
for api_name in "${!API_IDS[@]}"; do
  echo "  - $api_name"
done
echo ""
echo "Gateway URL: $GATEWAY_URL"
echo ""
echo "Test API calls:"
echo "  # Generate token"
echo "  TOKEN=\$(curl -k -u \"${CONSUMER_KEY}:${CONSUMER_SECRET}\" \\"
echo "    -d \"grant_type=client_credentials\" \\"
echo "    https://localhost:9444/oauth2/token | jq -r '.access_token')"
echo ""
echo "  # Call Forex API"
echo "  curl -k -H \"Authorization: Bearer \$TOKEN\" \\"
echo "    ${GATEWAY_URL}/forex/v1/health"
echo ""

# Save credentials
echo "$CONSUMER_KEY:$CONSUMER_SECRET" > /tmp/apim_credentials.txt
log_info "Credentials saved to: /tmp/apim_credentials.txt"
