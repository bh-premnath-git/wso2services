#!/usr/bin/env bash

################################################################################
# Reset Test User Passwords
#
# Ensures test users have correct passwords set in WSO2 IS
# This is needed because users created via registration API may not have
# passwords properly synced for OAuth password grant
################################################################################

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Reset Test User Passwords                                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Define users and their passwords
declare -A USER_PASSWORDS=(
  ["ops_user"]="OpsUser123!"
  ["finance"]="Finance123!"
  ["auditor"]="Auditor123!"
  ["user"]="User1234!"
  ["app_admin"]="AppAdmin123!"
)

RESET_COUNT=0
FAILED_COUNT=0

for username in "${!USER_PASSWORDS[@]}"; do
  password="${USER_PASSWORDS[$username]}"
  
  log_info "Resetting password for: ${username}"
  
  # Get user ID
  USER_ID=$(curl -sk -u "admin:admin" \
    "https://localhost:9444/scim2/Users?filter=userName+eq+${username}" 2>/dev/null | \
    jq -r '.Resources[0].id // empty')
  
  if [ -z "$USER_ID" ]; then
    echo "  User not found, skipping"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi
  
  # Reset password and ensure user is active
  RESPONSE=$(curl -sk -u "admin:admin" \
    -X PATCH "https://localhost:9444/scim2/Users/${USER_ID}" \
    -H "Content-Type: application/json" \
    -d "{
      \"schemas\": [\"urn:ietf:params:scim:api:messages:2.0:PatchOp\"],
      \"Operations\": [{
        \"op\": \"replace\",
        \"value\": {
          \"password\": \"${password}\",
          \"active\": true
        }
      }]
    }" 2>/dev/null)
  
  if echo "$RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
    log_success "Password reset: ${username}"
    RESET_COUNT=$((RESET_COUNT + 1))
  else
    echo "  Failed to reset password"
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
done

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Password Reset Summary                                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  ✅ Reset: ${RESET_COUNT}"
echo "  ❌ Failed: ${FAILED_COUNT}"
echo ""

if [ $RESET_COUNT -gt 0 ]; then
  log_success "Test users are ready for password grant authentication"
fi
