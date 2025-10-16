#!/usr/bin/env bash

################################################################################
# WSO2 Identity Server - Roles and Users Setup
#
# Creates roles and users in WSO2 IS 7.1.0 via SCIM2 API
# Supports proper role assignment and OAuth token generation
#
# Usage: ./setup_is_users_roles.sh
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ---------- Configuration ----------
IS_HOST="${IS_HOST:-localhost}"
IS_PORT="${IS_PORT:-9444}"  # Host-mapped port for external access
IS_BASE="https://${IS_HOST}:${IS_PORT}"
IS_ADMIN_USER="${IS_ADMIN_USER:-admin}"
IS_ADMIN_PASS="${IS_ADMIN_PASS:-admin}"

# Role to username mapping
declare -A USER_OF_ROLE=(
  [ops_users]="ops_user"
  [finance]="finance"
  [auditor]="auditor"
  [user]="user"
  [app_admin]="app_admin"
)

# User passwords (can be overridden via environment)
declare -A PASS_OF_USER=(
  [ops_user]="${OPS_USER_PASS:-OpsUser123!}"
  [finance]="${FINANCE_PASS:-Finance123!}"
  [auditor]="${AUDITOR_PASS:-Auditor123!}"
  [user]="${USER_PASS:-User1234!}"
  [app_admin]="${APP_ADMIN_PASS:-AppAdmin123!}"
)

MINT_TOKENS="${MINT_TOKENS:-true}"

# ---------- Setup ----------
auth_basic=(-u "${IS_ADMIN_USER}:${IS_ADMIN_PASS}")
json_hdr=(-H "Content-Type: application/json")
scim_groups="${IS_BASE}/scim2/Groups"
scim_users="${IS_BASE}/scim2/Users"
scim_roles="${IS_BASE}/scim2/Roles"

# Check dependencies
check_dependencies() {
  local missing=()
  
  for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  
  if [ ${#missing[@]} -gt 0 ]; then
    echo -e "${RED}[ERROR]${NC} Missing required commands: ${missing[*]}"
    echo "Install with: sudo apt-get install ${missing[*]}"
    exit 1
  fi
}

say() { 
  printf "\n${BLUE}▶${NC} %s\n" "$*" >&2
}

log_success() {
  echo -e "  ${GREEN}✅${NC} $1"
}

log_error() {
  echo -e "  ${RED}❌${NC} $1"
}

log_warning() {
  echo -e "  ${YELLOW}⚠️${NC}  $1"
}

log_info() {
  echo -e "  ${BLUE}→${NC} $1"
}

# ---------- Role Management ----------
get_role_id() {
  local role="$1"
  local response
  response=$(curl -sk "${auth_basic[@]}" \
    "${scim_roles}?filter=displayName%20eq%20%22${role}%22" 2>/dev/null)
  echo "$response" | jq -r '.Resources[0].id // empty' 2>/dev/null || echo ""
}

create_role() {
  local role="$1"
  say "Creating role: ${role}"

  # Check if exists
  local role_id
  role_id=$(get_role_id "${role}")
  if [ -n "${role_id}" ]; then
    log_success "exists: ${role_id}"
    echo "${role_id}"
    return 0
  fi

  # Create with audience for APIM integration
  # Use "APPLICATION" audience to make roles usable in apps
  local response
  response=$(curl -sk "${auth_basic[@]}" "${json_hdr[@]}" \
    -d "{
      \"displayName\": \"${role}\",
      \"audience\": {
        \"type\": \"application\",
        \"display\": \"Default\"
      }
    }" \
    "${scim_roles}" 2>/dev/null)

  role_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)

  if [ -n "${role_id}" ] && [ "${role_id}" != "null" ]; then
    log_success "created: ${role_id}"
    echo "${role_id}"
    return 0
  else
    # If audience fails, try without it (for internal roles)
    log_warning "Audience-based role failed, trying internal role..."
    response=$(curl -sk "${auth_basic[@]}" "${json_hdr[@]}" \
      -d "{\"displayName\": \"${role}\"}" \
      "${scim_roles}" 2>/dev/null)

    role_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)
    if [ -n "${role_id}" ] && [ "${role_id}" != "null" ]; then
      log_success "created as internal: ${role_id}"
      echo "${role_id}"
      return 0
    fi

    log_error "failed"
    echo "$response" | jq '.' 2>/dev/null || echo "$response"
    return 1
  fi
}

# ---------- User Management ----------
find_user_id() {
  local uname="$1"
  local response
  response=$(curl -sk "${auth_basic[@]}" \
    "${scim_users}?filter=userName%20eq%20%22${uname}%22" 2>/dev/null)
  echo "$response" | jq -r '.Resources[0].id // empty' 2>/dev/null || echo ""
}

create_user_simple() {
  local uname="$1" pass="$2"
  say "Creating user: ${uname}"

  local uid
  uid=$(find_user_id "${uname}")
  if [ -n "${uid}" ]; then
    log_success "exists: ${uid}"
    echo "${uid}"
    return 0
  fi

  # Create user WITHOUT roles first (roles assigned separately)
  local response
  response=$(curl -sk "${auth_basic[@]}" "${json_hdr[@]}" \
    -d "{
      \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:User\"],
      \"userName\": \"${uname}\",
      \"password\": \"${pass}\",
      \"name\": {
        \"givenName\": \"${uname}\",
        \"familyName\": \"User\"
      },
      \"emails\": [{
        \"primary\": true,
        \"value\": \"${uname}@innover.local\"
      }]
    }" \
    "${scim_users}" 2>/dev/null)

  uid=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)

  if [ -n "${uid}" ] && [ "${uid}" != "null" ]; then
    log_success "created: ${uid}"
    echo "${uid}"
    return 0
  else
    log_error "failed"
    echo "$response" | jq '.detail // .scimType // .' 2>/dev/null || echo "$response"
    return 1
  fi
}

assign_role_to_user() {
  local user_id="$1"
  local role_id="$2"
  local role_name="$3"
  local username="$4"

  log_info "Assigning role '${role_name}' to user '${username}'..."

  # WSO2 IS 7.1+: PATCH the ROLE (not the user) to add users
  # The user's groups/roles attribute is immutable/read-only
  local response http_code
  response=$(curl -sk -w "\nHTTP_CODE:%{http_code}" "${auth_basic[@]}" \
    -H "Content-Type: application/json" \
    -X PATCH \
    -d "{
      \"schemas\": [\"urn:ietf:params:scim:api:messages:2.0:PatchOp\"],
      \"Operations\": [{
        \"op\": \"add\",
        \"path\": \"users\",
        \"value\": [{
          \"value\": \"${user_id}\",
          \"display\": \"${username}\"
        }]
      }]
    }" \
    "${scim_roles}/${role_id}" 2>/dev/null || echo "HTTP_CODE:000")

  http_code=$(echo "$response" | grep -o 'HTTP_CODE:[0-9]*' | cut -d':' -f2)
  response_body=$(echo "$response" | sed 's/HTTP_CODE:[0-9]*//')

  if [ "$http_code" = "200" ] || echo "$response_body" | jq -e '.id' >/dev/null 2>&1; then
    log_success "Role '${role_name}' assigned to '${username}' ✅"
    return 0
  else
    log_warning "Role assignment returned HTTP ${http_code}"
    if [ -n "$response_body" ]; then
      echo "$response_body" | jq -C '.detail // .scimType // .' 2>/dev/null || echo "$response_body"
    fi
    # Don't fail on role assignment errors
    return 0
  fi
}

# ---------- OAuth Token Minting ----------
mint_oauth_tokens() {
  say "Registering OAuth client & minting tokens"

  CLIENT_NAME="is-password-client-$(date +%s)"
  DCR_RESP=$(curl -sk "${auth_basic[@]}" "${json_hdr[@]}" \
    -d "{
      \"client_name\": \"${CLIENT_NAME}\",
      \"grant_types\": [\"password\", \"refresh_token\"],
      \"redirect_uris\": [\"https://localhost/cb\"]
    }" \
    "${IS_BASE}/api/identity/oauth2/dcr/v1.1/register" 2>/dev/null)

  CLIENT_ID=$(echo "${DCR_RESP}" | jq -r '.client_id // empty')
  CLIENT_SECRET=$(echo "${DCR_RESP}" | jq -r '.client_secret // empty')

  if [ -n "${CLIENT_ID}" ] && [ -n "${CLIENT_SECRET}" ]; then
    log_success "OAuth client: ${CLIENT_ID}"
    echo ""

    for role in "${!USER_OF_ROLE[@]}"; do
      u="${USER_OF_ROLE[$role]}"
      p="${PASS_OF_USER[$u]}"

      TOK_RESP=$(curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \
        -d "grant_type=password&username=${u}&password=${p}&scope=openid" \
        "${IS_BASE}/oauth2/token" 2>/dev/null)

      TOK=$(echo "${TOK_RESP}" | jq -r '.access_token // empty')
      if [ -n "${TOK}" ]; then
        echo -e "${GREEN}✅${NC} ${role}/${u}: ${TOK:0:40}..."
      else
        echo -e "${RED}❌${NC} ${role}/${u}: token generation failed"
      fi
    done
  else
    log_error "DCR registration failed"
    echo "${DCR_RESP}" | jq '.' 2>/dev/null || echo "${DCR_RESP}"
  fi
}

# ---------- Print Summary ----------
print_summary() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║  Created Users and Roles Summary                           ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Roles:"
  for role in "${!USER_OF_ROLE[@]}"; do
    echo "  - ${role}"
  done
  echo ""
  echo "Users (username : role):"
  for role in "${!USER_OF_ROLE[@]}"; do
    u="${USER_OF_ROLE[$role]}"
    echo "  - ${u} : ${role}"
  done
  echo ""
  echo "Credentials can be found in the script configuration"
  echo "Access WSO2 IS Console: ${IS_BASE}/console"
  echo ""
}

# ---------- Main Workflow ----------
main() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║  WSO2 Identity Server - Users & Roles Setup               ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Target: ${IS_BASE}"
  echo ""

  # Check dependencies
  check_dependencies

  # Check if WSO2 IS is accessible
  if ! curl -sk "${IS_BASE}/carbon/" -o /dev/null -w "%{http_code}" 2>/dev/null | grep -q "302\|200"; then
    echo -e "${RED}[ERROR]${NC} WSO2 Identity Server is not accessible at ${IS_BASE}"
    echo "Please ensure WSO2 IS is running: docker compose up -d wso2is"
    exit 1
  fi

  declare -A ROLE_IDS
  declare -A USER_IDS

  # Step 1: Create all roles and capture their IDs
  say "STEP 1: Creating roles"
  for role in "${!USER_OF_ROLE[@]}"; do
    # Capture only last line (the ID) from the function
    role_id=$(create_role "${role}" 2>&1 | tail -n 1)
    ROLE_IDS[$role]="$role_id"
  done

  # Step 2: Create users
  say "STEP 2: Creating users"
  for role in "${!USER_OF_ROLE[@]}"; do
    u="${USER_OF_ROLE[$role]}"
    p="${PASS_OF_USER[$u]}"
    # Capture only last line (the ID) from the function
    user_id=$(create_user_simple "${u}" "${p}" 2>&1 | tail -n 1)
    USER_IDS[$u]="$user_id"
  done

  # Step 3: Assign roles to users
  say "STEP 3: Assigning roles to users"
  for role in "${!USER_OF_ROLE[@]}"; do
    u="${USER_OF_ROLE[$role]}"
    user_id="${USER_IDS[$u]}"
    role_id="${ROLE_IDS[$role]}"

    if [ -n "${user_id}" ] && [ -n "${role_id}" ]; then
      assign_role_to_user "${user_id}" "${role_id}" "${role}" "${u}" || true
    else
      log_warning "Skipping ${u} - missing IDs (user:${user_id}, role:${role_id})"
    fi
  done

  # Step 4: Token Minting (optional)
  if [ "${MINT_TOKENS}" = "true" ]; then
    echo ""
    mint_oauth_tokens
  fi

  # Print summary
  print_summary

  say "✅ Setup complete"
}

# Run main
main "$@"
