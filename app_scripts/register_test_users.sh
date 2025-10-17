#!/usr/bin/env bash

################################################################################
# Register Test Users via Profile Service Registration API
#
# Registers test users using the new registration endpoint
# instead of directly via SCIM2
#
# Prerequisites:
#   - Profile service running (port 8004)
#   - Roles created (run setup_roles_only.sh first)
#
# Usage: ./register_test_users.sh
################################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROFILE_SERVICE="${PROFILE_SERVICE:-http://localhost:8004}"
REGISTER_ENDPOINT="${PROFILE_SERVICE}/register"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

# Test users with role assignments
declare -A TEST_USERS=(
  [ops_user]="OpsUser123!"
  [finance]="Finance123!"
  [auditor]="Auditor123!"
  [user]="User1234!"
  [app_admin]="AppAdmin123!"
)

# User details (first_name, last_name, email)
declare -A USER_DETAILS=(
  [ops_user]="Operations:User:ops@example.com"
  [finance]="Finance:User:finance@example.com"
  [auditor]="Audit:User:auditor@example.com"
  [user]="Regular:User:user@example.com"
  [app_admin]="Admin:User:appadmin@example.com"
)

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Register Test Users via Registration API                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check if profile service is accessible
log_info "Checking Profile Service availability..."
if ! curl -s "${PROFILE_SERVICE}/health" > /dev/null 2>&1; then
    log_error "Profile Service not accessible at ${PROFILE_SERVICE}"
    log_info "Start it with: docker compose up -d profile-service"
    exit 1
fi
log_success "Profile Service is running"
echo ""

# Register each user
REGISTERED=0
FAILED=0
EXISTED=0

for username in "${!TEST_USERS[@]}"; do
    password="${TEST_USERS[$username]}"
    details="${USER_DETAILS[$username]}"
    
    IFS=':' read -r first_name last_name email <<< "$details"
    
    log_info "Registering user: ${username}"
    
    # Call registration API
    response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "${REGISTER_ENDPOINT}" \
        -H "Content-Type: application/json" \
        -d "{
            \"username\": \"${username}\",
            \"password\": \"${password}\",
            \"email\": \"${email}\",
            \"first_name\": \"${first_name}\",
            \"last_name\": \"${last_name}\"
        }" 2>/dev/null)
    
    http_code=$(echo "$response" | grep -o 'HTTP_CODE:[0-9]*' | cut -d':' -f2)
    response_body=$(echo "$response" | sed 's/HTTP_CODE:[0-9]*//')
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        user_id=$(echo "$response_body" | jq -r '.user_id // empty' 2>/dev/null)
        if [ -n "$user_id" ]; then
            log_success "Registered: ${username} (ID: ${user_id:0:20}...)"
            
            # Activate user (users are created inactive by default)
            curl -sk -u "admin:admin" \
                -X PATCH "https://localhost:9444/scim2/Users/${user_id}" \
                -H "Content-Type: application/json" \
                -d '{
                    "schemas": ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
                    "Operations": [{
                        "op": "replace",
                        "value": {"active": true}
                    }]
                }' >/dev/null 2>&1
            
            log_success "Activated: ${username}"
            REGISTERED=$((REGISTERED + 1))
        else
            log_error "Registration response invalid for ${username}"
            FAILED=$((FAILED + 1))
        fi
    elif [ "$http_code" = "409" ]; then
        log_warning "Already exists: ${username}"
        EXISTED=$((EXISTED + 1))
    else
        log_error "Failed to register ${username} (HTTP ${http_code})"
        echo "$response_body" | jq '.' 2>/dev/null || echo "$response_body"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Registration Summary                                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  ✅ Registered:      ${REGISTERED}"
echo "  ⚠️  Already existed: ${EXISTED}"
echo "  ❌ Failed:          ${FAILED}"
echo ""

if [ $FAILED -gt 0 ]; then
    log_error "Some users failed to register"
    exit 1
fi

echo "📝 Registered Users:"
for username in "${!TEST_USERS[@]}"; do
    echo "  - ${username} (password: ${TEST_USERS[$username]})"
done
echo ""

log_info "Users can now login via: POST ${PROFILE_SERVICE}/auth/login"
log_info "Test all users with: ./test_all_users_apis.sh"
echo ""

log_success "User registration complete!"
