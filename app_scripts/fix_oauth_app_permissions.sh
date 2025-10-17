#!/usr/bin/env bash

################################################################################
# Fix OAuth Application Permissions
#
# Updates OAuth application in WSO2 IS to allow ALL users (not just admin)
# Sets "saas": true which enables multi-user/multi-tenant access
################################################################################

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Fix OAuth Application Permissions                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Load OAuth credentials
if [ ! -f ".oauth_credentials" ]; then
  log_error "OAuth credentials not found! Run ./app_scripts/create_working_password_grant_app.sh first"
  exit 1
fi

source .oauth_credentials

log_info "Looking up OAuth application in WSO2 IS for client: ${CLIENT_ID:0:20}..."

# Search for the application by client ID
APP_SEARCH=$(curl -sk -u "admin:admin" \
  "https://localhost:9444/t/carbon.super/api/server/v1/applications?filter=clientId+eq+${CLIENT_ID}" 2>/dev/null)

APP_ID=$(echo "$APP_SEARCH" | jq -r '.applications[0].id // empty')

if [ -z "$APP_ID" ]; then
  log_error "Could not find application with client ID: $CLIENT_ID"
  exit 1
fi

APP_NAME=$(echo "$APP_SEARCH" | jq -r '.applications[0].name')
log_success "Found application: $APP_NAME (ID: $APP_ID)"

# Update application to allow all users
log_info "Updating application permissions to allow all users..."

PATCH_RESPONSE=$(curl -sk -u "admin:admin" \
  -X PATCH "https://localhost:9444/t/carbon.super/api/server/v1/applications/${APP_ID}" \
  -H "Content-Type: application/json" \
  -d '{
    "accessUrl": "http://localhost",
    "advancedConfigurations": {
      "saas": true,
      "discoverableByEndUsers": true
    },
    "claimConfiguration": {
      "dialect": "LOCAL",
      "requestedClaims": [],
      "subject": {
        "useMappedLocalSubject": false
      }
    }
  }' 2>/dev/null)

if echo "$PATCH_RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
  log_success "Application permissions updated!"
  echo ""
  echo "The OAuth application now allows ALL users to authenticate with password grant."
  echo ""
  
  # Test with ops_user
  log_info "Testing password grant with ops_user..."
  
  TOKEN_RESPONSE=$(curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \
    -X POST "https://localhost:9444/oauth2/token" \
    -d "grant_type=password&username=ops_user&password=OpsUser123!" 2>/dev/null)
  
  ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
  
  if [ -n "$ACCESS_TOKEN" ]; then
    log_success "Password grant working for ops_user!"
    echo "Token: ${ACCESS_TOKEN:0:50}..."
    echo ""
    
    # Test /auth/login endpoint
    log_info "Testing /auth/login endpoint..."
    LOGIN_RESP=$(curl -s -X POST "http://localhost:8004/auth/login" \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"ops_user\",\"password\":\"OpsUser123!\",\"client_id\":\"${CLIENT_ID}\",\"client_secret\":\"${CLIENT_SECRET}\",\"scopes\":[\"openid\",\"profile\",\"email\"]}" 2>/dev/null)
    
    if echo "$LOGIN_RESP" | jq -e '.access_token' >/dev/null 2>&1; then
      log_success "/auth/login endpoint works!"
      echo ""
      echo "╔════════════════════════════════════════════════════════════╗"
      echo "║  🎉 AUTHENTICATION FULLY WORKING!                          ║"
      echo "╚════════════════════════════════════════════════════════════╝"
    else
      log_error "/auth/login endpoint failed"
      echo "$LOGIN_RESP" | jq '.' 2>/dev/null || echo "$LOGIN_RESP"
    fi
  else
    log_error "Password grant still failing"
    echo "$TOKEN_RESPONSE" | jq '.' 2>/dev/null || echo "$TOKEN_RESPONSE"
  fi
else
  log_error "Failed to update application"
  echo "$PATCH_RESPONSE" | jq '.' 2>/dev/null || echo "$PATCH_RESPONSE"
  exit 1
fi
