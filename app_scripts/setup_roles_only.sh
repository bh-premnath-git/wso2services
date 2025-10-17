#!/usr/bin/env bash

################################################################################
# WSO2 Identity Server - Roles Setup (Users via Registration API)
#
# Creates roles in WSO2 IS 7.1.0 via SCIM2 API
# Users should be registered via the Profile Service registration API
#
# Usage: ./setup_roles_only.sh
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

# Roles to create
ROLES=(
  "ops_users"
  "finance"
  "auditor"
  "user"
  "app_admin"
)

# ---------- Setup ----------
auth_basic=(-u "${IS_ADMIN_USER}:${IS_ADMIN_PASS}")
json_hdr=(-H "Content-Type: application/json")
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

# ---------- Print Summary ----------
print_summary() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║  Roles Created - Users via Registration API               ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Roles created:"
  for role in "${ROLES[@]}"; do
    echo "  ✅ ${role}"
  done
  echo ""
  echo "📝 Next Steps:"
  echo "   1. Register users via: ./app_scripts/register_test_users.sh"
  echo "   2. Or use: POST http://localhost:8004/register"
  echo ""
  echo "Access WSO2 IS Console: ${IS_BASE}/console"
  echo ""
}

# ---------- Main Workflow ----------
main() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║  WSO2 Identity Server - Roles Setup                       ║"
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

  # Create all roles and capture their IDs
  say "Creating roles..."
  for role in "${ROLES[@]}"; do
    role_id=$(create_role "${role}" 2>&1 | tail -n 1)
    ROLE_IDS[$role]="$role_id"
  done

  # Print summary
  print_summary

  say "✅ Role setup complete"
  echo ""
  log_info "Users should now be registered via the registration API"
  log_info "Run: ./app_scripts/register_test_users.sh"
}

# Run main
main "$@"
