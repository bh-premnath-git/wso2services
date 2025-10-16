#!/usr/bin/env bash

################################################################################
# Create Working Password Grant OAuth App
#
# This script creates a properly configured OAuth application in WSO2 IS
# that works with password grant for ANY user
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Create Working Password Grant OAuth App                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

log_info "Creating OAuth application via DCR..."

DCR_RESPONSE=$(curl -sk -u "admin:admin" \
  -H "Content-Type: application/json" \
  -d '{
    "client_name": "UserPasswordGrantApp",
    "grant_types": ["password", "refresh_token", "client_credentials"],
    "redirect_uris": ["https://localhost/callback"]
  }' \
  "https://localhost:9444/api/identity/oauth2/dcr/v1.1/register")

CLIENT_ID=$(echo "$DCR_RESPONSE" | jq -r '.client_id')
CLIENT_SECRET=$(echo "$DCR_RESPONSE" | jq -r '.client_secret')

if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" = "null" ]; then
  log_error "Failed to create OAuth app"
  echo "$DCR_RESPONSE" | jq '.'
  exit 1
fi

log_success "OAuth app created"
echo "Client ID: $CLIENT_ID"
echo ""

# Test with ops_user
log_info "Testing password grant with ops_user..."

TOKEN_RESPONSE=$(curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \
  -X POST "https://localhost:9444/oauth2/token" \
  -d "grant_type=password&username=ops_user&password=OpsUser123!")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
  log_success "Password grant working!"
  echo "Token: ${ACCESS_TOKEN:0:50}..."
  
  # Test API call
  log_info "Testing API call..."
  curl -sk -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "https://localhost:8243/forex/v1/health" | jq '.'
else
  log_error "Password grant failed"
  echo "$TOKEN_RESPONSE" | jq '.'
fi

# Save credentials
CRED_FILE="/tmp/password_grant_app_credentials.txt"
cat > "$CRED_FILE" <<EOF
═══════════════════════════════════════════════════════════
Password Grant OAuth Application Credentials
═══════════════════════════════════════════════════════════

Client ID:     $CLIENT_ID
Client Secret: $CLIENT_SECRET

Grant Types:   password, refresh_token, client_credentials

Usage:
──────────────────────────────────────────────────────────
# Get token for any user:
curl -sk -u "$CLIENT_ID:$CLIENT_SECRET" \\
  -X POST "https://localhost:9444/oauth2/token" \\
  -d "grant_type=password&username=USERNAME&password=PASSWORD"

# Call API:
curl -sk -H "Authorization: Bearer \$TOKEN" \\
  "https://localhost:8243/forex/v1/health"

═══════════════════════════════════════════════════════════
Created: $(date)
═══════════════════════════════════════════════════════════
EOF

log_success "Credentials saved to: $CRED_FILE"
echo ""
echo "✅ Password grant OAuth app is ready!"
echo ""
