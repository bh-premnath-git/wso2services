#!/usr/bin/env bash

################################################################################
# Configure OAuth Application for Full User Claims
#
# WSO2 IS applications created via DCR don't automatically include user claims
# in ID tokens. This script configures the application to return all user info.
################################################################################

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Configure OAuth App for User Claims                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Get OAuth credentials
if [ ! -f "/tmp/password_grant_app_credentials.txt" ]; then
    log_warning "OAuth app not found. Run: ./app_scripts/create_working_password_grant_app.sh"
    exit 1
fi

CLIENT_ID=$(grep "Client ID:" /tmp/password_grant_app_credentials.txt | awk '{print $3}')
log_info "Configuring app with Client ID: ${CLIENT_ID:0:20}..."

# Find application
APP_SEARCH=$(curl -sk -u "admin:admin" \
  "https://localhost:9444/t/carbon.super/api/server/v1/applications?filter=clientId+eq+${CLIENT_ID}" 2>/dev/null)

APP_ID=$(echo "$APP_SEARCH" | jq -r '.applications[0].id // empty')

if [ -z "$APP_ID" ]; then
    log_warning "Application not found!"
    exit 1
fi

APP_NAME=$(echo "$APP_SEARCH" | jq -r '.applications[0].name')
log_success "Found: $APP_NAME"

# Update application with claim configuration
log_info "Configuring claims..."

PATCH_RESPONSE=$(curl -sk -u "admin:admin" \
  -X PATCH "https://localhost:9444/t/carbon.super/api/server/v1/applications/${APP_ID}" \
  -H "Content-Type: application/json" \
  -d '{
    "claimConfiguration": {
      "dialect": "LOCAL",
      "requestedClaims": [
        {
          "claim": {"uri": "http://wso2.org/claims/username"},
          "mandatory": false
        },
        {
          "claim": {"uri": "http://wso2.org/claims/emailaddress"},
          "mandatory": false
        },
        {
          "claim": {"uri": "http://wso2.org/claims/givenname"},
          "mandatory": false
        },
        {
          "claim": {"uri": "http://wso2.org/claims/lastname"},
          "mandatory": false
        },
        {
          "claim": {"uri": "http://wso2.org/claims/fullname"},
          "mandatory": false
        }
      ],
      "subject": {
        "claim": {"uri": "http://wso2.org/claims/username"},
        "includeTenantDomain": false,
        "includeUserDomain": false,
        "useMappedLocalSubject": false
      }
    }
  }' 2>/dev/null)

if echo "$PATCH_RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
    log_success "Claims configured"
else
    log_warning "Configuration may have failed"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Known Limitation                                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "⚠️  WSO2 IS 7.1.0 applications created via DCR (Dynamic Client"
echo "    Registration) have limited claim support in ID tokens."
echo ""
echo "📝 Current behavior:"
echo "   - ID Token: Only basic claims (sub, aud, iss, exp, etc.)"
echo "   - UserInfo endpoint: Only 'sub' claim"
echo ""
echo "✅ Workarounds:"
echo "   1. Use SCIM2 API to get full user data:"
echo "      curl -u admin:admin https://localhost:9444/scim2/Users?filter=userName+eq+USERNAME"
echo ""
echo "   2. Create application via WSO2 IS Console UI:"
echo "      https://localhost:9444/console → Applications → New Application"
echo "      (Manual creation properly configures all claim mappings)"
echo ""
echo "   3. Use the access token to call backend services which can"
echo "      look up full user data from WSO2 IS"
echo ""
echo "This is a known behavior in WSO2 IS when using DCR."
echo ""
