#!/usr/bin/env bash

################################################################################
# WSO2 Identity Server - User Management
#
# Features:
# - Register new users
# - Login (authenticate)
# - Reset password
# - Activate/Deactivate users
# - List users
# - Update user profile
#
# Uses SCIM2 API
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
WSO2IS_HOST="${WSO2IS_HOST:-localhost}"
WSO2IS_PORT="${WSO2IS_PORT:-9444}"
WSO2IS_ADMIN_USER="${WSO2IS_ADMIN_USER:-admin}"
WSO2IS_ADMIN_PASS="${WSO2IS_ADMIN_PASS:-admin}"

# API endpoints
SCIM2_API="https://${WSO2IS_HOST}:${WSO2IS_PORT}/scim2"
OAUTH2_API="https://${WSO2IS_HOST}:${WSO2IS_PORT}/oauth2"

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Check dependencies
check_dependencies() {
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required but not installed"
        log_error "Install with: sudo apt-get install jq"
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl is required but not installed"
        return 1
    fi
    return 0
}

# Container verification
check_container() {
    if ! docker ps --format '{{.Names}}' | grep -q "^wso2is$"; then
        log_error "Container 'wso2is' is not running"
        log_error "Start it with: docker compose up -d wso2is"
        return 1
    fi
    return 0
}

# Enhanced curl with retry
curl_with_retry() {
    local max_attempts=3
    local timeout=30
    local attempt=1
    local http_code
    local temp_file=$(mktemp)
    
    while [ $attempt -le $max_attempts ]; do
        if [ $attempt -gt 1 ]; then
            log_info "Retry attempt $attempt of $max_attempts..."
            sleep 2
        fi
        
        http_code=$(curl --max-time $timeout -w "%{http_code}" -o "${temp_file}" "$@" 2>/dev/null)
        local curl_exit=$?
        
        if [ $curl_exit -eq 0 ]; then
            if [[ "$http_code" =~ ^[23] ]]; then
                cat "${temp_file}"
                rm -f "${temp_file}"
                return 0
            else
                log_error "HTTP error code: ${http_code}"
                cat "${temp_file}" >&2
                rm -f "${temp_file}"
                return 1
            fi
        fi
        
        ((attempt++))
    done
    
    rm -f "${temp_file}"
    log_error "Failed after $max_attempts attempts"
    return 1
}

# JSON utilities
validate_json() {
    local json="$1"
    if ! echo "$json" | jq empty 2>/dev/null; then
        log_error "Invalid JSON response"
        return 1
    fi
    return 0
}

extract_json_field() {
    local json="$1"
    local field="$2"
    local default="${3:-}"
    
    if [ -z "$json" ]; then
        echo "$default"
        return 1
    fi
    
    local result
    result=$(echo "$json" | jq -r "${field} // empty" 2>/dev/null)
    
    if [ -z "$result" ] || [ "$result" = "null" ]; then
        echo "$default"
        return 1
    fi
    
    echo "$result"
    return 0
}

json_escape() {
    local string="$1"
    echo -n "$string" | jq -Rs .
}

url_encode() {
    local string="$1"
    echo -n "$string" | jq -sRr @uri
}

# Input validation
validate_username() {
    local username="$1"
    if [[ ! "$username" =~ ^[a-zA-Z0-9._@-]+$ ]]; then
        log_error "Invalid username: '$username'"
        log_error "Only alphanumeric, ., _, @, - allowed"
        return 1
    fi
    return 0
}

validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid email: '$email'"
        return 1
    fi
    return 0
}

validate_password() {
    local password="$1"
    if [ ${#password} -lt 8 ]; then
        log_error "Password must be at least 8 characters"
        return 1
    fi
    return 0
}

################################################################################
# COMMAND: register - Register a new user
################################################################################

cmd_register() {
    local username=${1:-}
    local password=${2:-}
    local email=${3:-}
    local first_name=${4:-}
    local last_name=${5:-}
    
    if [ -z "${username}" ] || [ -z "${password}" ] || [ -z "${email}" ]; then
        log_error "Usage: $0 register <username> <password> <email> [first_name] [last_name]"
        echo ""
        echo "Example:"
        echo "  $0 register john john123456 john@example.com John Doe"
        return 1
    fi
    
    # Validate inputs
    validate_username "${username}" || return 1
    validate_password "${password}" || return 1
    validate_email "${email}" || return 1
    
    check_dependencies || return 1
    check_container || return 1
    
    echo ""
    echo "=========================================="
    echo "  Register New User"
    echo "=========================================="
    echo ""
    
    log_info "Creating user '${username}'..."
    
    # Build SCIM2 payload
    local payload
    payload=$(jq -n \
        --arg un "${username}" \
        --arg pw "${password}" \
        --arg em "${email}" \
        --arg fn "${first_name:-$username}" \
        --arg ln "${last_name:-User}" \
        '{
            schemas: ["urn:ietf:params:scim:schemas:core:2.0:User"],
            userName: $un,
            password: $pw,
            name: {
                givenName: $fn,
                familyName: $ln
            },
            emails: [{
                primary: true,
                value: $em
            }]
        }')
    
    local response
    response=$(curl_with_retry -k -sS -u "${WSO2IS_ADMIN_USER}:${WSO2IS_ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        -X POST "${SCIM2_API}/Users")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to connect to Identity Server"
        return 1
    fi
    
    if ! validate_json "${response}"; then
        log_error "Invalid response from server"
        echo "${response}"
        return 1
    fi
    
    local user_id=$(extract_json_field "${response}" ".id")
    
    if [ -n "${user_id}" ]; then
        log_success "User registered successfully!"
        echo ""
        echo "User ID: ${user_id}"
        echo "Username: ${username}"
        echo "Email: ${email}"
        echo ""
        return 0
    else
        log_error "Failed to register user"
        echo "${response}" | jq .
        return 1
    fi
}

################################################################################
# COMMAND: login - Authenticate user (Resource Owner Password Grant)
################################################################################

cmd_login() {
    local username=${1:-}
    local password=${2:-}
    local client_id=${3:-}
    local client_secret=${4:-}
    
    if [ -z "${username}" ] || [ -z "${password}" ]; then
        log_error "Usage: $0 login <username> <password> [client_id] [client_secret]"
        echo ""
        echo "Example:"
        echo "  $0 login john john123456"
        echo ""
        echo "With OAuth2 app:"
        echo "  $0 login john john123456 <client_id> <client_secret>"
        return 1
    fi
    
    check_dependencies || return 1
    check_container || return 1
    
    echo ""
    echo "=========================================="
    echo "  User Login"
    echo "=========================================="
    echo ""
    
    if [ -n "${client_id}" ] && [ -n "${client_secret}" ]; then
        log_info "Authenticating with OAuth2..."
        
        local response
        response=$(curl_with_retry -k -sS -u "${client_id}:${client_secret}" \
            -d "grant_type=password&username=${username}&password=${password}&scope=openid" \
            -X POST "${OAUTH2_API}/token")
        
        if [ $? -ne 0 ]; then
            log_error "Authentication failed"
            return 1
        fi
        
        if ! validate_json "${response}"; then
            log_error "Invalid response"
            echo "${response}"
            return 1
        fi
        
        local access_token=$(extract_json_field "${response}" ".access_token")
        
        if [ -n "${access_token}" ]; then
            log_success "Login successful!"
            echo ""
            echo "${response}" | jq .
            echo ""
            echo "Access Token (first 50 chars): ${access_token:0:50}..."
            return 0
        else
            log_error "Login failed"
            echo "${response}" | jq .
            return 1
        fi
    else
        # Basic authentication check via SCIM2 Me endpoint
        log_info "Verifying credentials..."
        
        local response
        response=$(curl_with_retry -k -sS -u "${username}:${password}" \
            -X GET "${SCIM2_API}/Me")
        
        if [ $? -eq 0 ] && validate_json "${response}"; then
            log_success "Login successful!"
            echo ""
            echo "User Details:"
            echo "${response}" | jq '{id, userName, name, emails}'
            return 0
        else
            log_error "Login failed - Invalid credentials"
            return 1
        fi
    fi
}

################################################################################
# COMMAND: reset-password - Reset user password
################################################################################

cmd_reset_password() {
    local username=${1:-}
    local new_password=${2:-}
    
    if [ -z "${username}" ] || [ -z "${new_password}" ]; then
        log_error "Usage: $0 reset-password <username> <new_password>"
        echo ""
        echo "Example:"
        echo "  $0 reset-password john newPassword123"
        return 1
    fi
    
    validate_username "${username}" || return 1
    validate_password "${new_password}" || return 1
    
    check_dependencies || return 1
    check_container || return 1
    
    echo ""
    echo "=========================================="
    echo "  Reset User Password"
    echo "=========================================="
    echo ""
    
    # Get user ID first
    log_info "Finding user '${username}'..."
    local encoded_username=$(url_encode "${username}")
    
    local response
    response=$(curl_with_retry -k -sS -u "${WSO2IS_ADMIN_USER}:${WSO2IS_ADMIN_PASS}" \
        "${SCIM2_API}/Users?filter=userName%20eq%20${encoded_username}")
    
    if [ $? -ne 0 ] || ! validate_json "${response}"; then
        log_error "Failed to find user"
        return 1
    fi
    
    local user_id=$(extract_json_field "${response}" ".Resources[0].id")
    
    if [ -z "${user_id}" ]; then
        log_error "User '${username}' not found"
        return 1
    fi
    
    log_info "Resetting password for user ID: ${user_id}..."
    
    # Update password
    local payload
    payload=$(jq -n \
        --arg pw "${new_password}" \
        '{
            schemas: ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
            Operations: [{
                op: "replace",
                value: {
                    password: $pw
                }
            }]
        }')
    
    response=$(curl_with_retry -k -sS -u "${WSO2IS_ADMIN_USER}:${WSO2IS_ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        -X PATCH "${SCIM2_API}/Users/${user_id}")
    
    if [ $? -eq 0 ] && validate_json "${response}"; then
        log_success "Password reset successfully!"
        echo ""
        echo "User: ${username}"
        echo "New password is active"
        return 0
    else
        log_error "Failed to reset password"
        echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: activate-user - Activate or deactivate user
################################################################################

cmd_activate_user() {
    local username=${1:-}
    local action=${2:-activate}
    
    if [ -z "${username}" ]; then
        log_error "Usage: $0 activate-user <username> [activate|deactivate]"
        echo ""
        echo "Examples:"
        echo "  $0 activate-user john activate"
        echo "  $0 activate-user john deactivate"
        return 1
    fi
    
    if [[ ! "$action" =~ ^(activate|deactivate)$ ]]; then
        log_error "Action must be 'activate' or 'deactivate'"
        return 1
    fi
    
    validate_username "${username}" || return 1
    check_dependencies || return 1
    check_container || return 1
    
    echo ""
    echo "=========================================="
    echo "  ${action^} User"
    echo "=========================================="
    echo ""
    
    # Get user ID
    log_info "Finding user '${username}'..."
    local encoded_username=$(url_encode "${username}")
    
    local response
    response=$(curl_with_retry -k -sS -u "${WSO2IS_ADMIN_USER}:${WSO2IS_ADMIN_PASS}" \
        "${SCIM2_API}/Users?filter=userName%20eq%20${encoded_username}")
    
    if [ $? -ne 0 ] || ! validate_json "${response}"; then
        log_error "Failed to find user"
        return 1
    fi
    
    local user_id=$(extract_json_field "${response}" ".Resources[0].id")
    
    if [ -z "${user_id}" ]; then
        log_error "User '${username}' not found"
        return 1
    fi
    
    local active_value="true"
    [ "$action" = "deactivate" ] && active_value="false"
    
    log_info "${action^}ing user..."
    
    local payload
    payload=$(jq -n \
        --arg active "${active_value}" \
        '{
            schemas: ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
            Operations: [{
                op: "replace",
                value: {
                    active: ($active == "true")
                }
            }]
        }')
    
    response=$(curl_with_retry -k -sS -u "${WSO2IS_ADMIN_USER}:${WSO2IS_ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        -X PATCH "${SCIM2_API}/Users/${user_id}")
    
    if [ $? -eq 0 ] && validate_json "${response}"; then
        log_success "User ${action}d successfully!"
        echo ""
        echo "User: ${username}"
        echo "Status: ${action}d"
        return 0
    else
        log_error "Failed to ${action} user"
        echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: list-users - List all users
################################################################################

cmd_list_users() {
    check_dependencies || return 1
    check_container || return 1
    
    echo ""
    echo "=========================================="
    echo "  All Users"
    echo "=========================================="
    echo ""
    
    log_info "Fetching users..."
    local response
    response=$(curl_with_retry -k -sS -u "${WSO2IS_ADMIN_USER}:${WSO2IS_ADMIN_PASS}" \
        "${SCIM2_API}/Users?count=100")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to connect"
        return 1
    fi
    
    if validate_json "${response}" && echo "${response}" | jq -e '.Resources' >/dev/null 2>&1; then
        echo "${response}" | jq .
    else
        log_error "Failed to fetch users"
        echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: get-user - Get user details
################################################################################

cmd_get_user() {
    local username=${1:-}
    
    if [ -z "${username}" ]; then
        log_error "Usage: $0 get-user <username>"
        return 1
    fi
    
    validate_username "${username}" || return 1
    check_dependencies || return 1
    check_container || return 1
    
    echo ""
    echo "=========================================="
    echo "  User Details"
    echo "=========================================="
    echo ""
    
    log_info "Fetching user '${username}'..."
    local encoded_username=$(url_encode "${username}")
    
    local response
    response=$(curl_with_retry -k -sS -u "${WSO2IS_ADMIN_USER}:${WSO2IS_ADMIN_PASS}" \
        "${SCIM2_API}/Users?filter=userName%20eq%20${encoded_username}")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to connect"
        return 1
    fi
    
    if validate_json "${response}"; then
        local total=$(extract_json_field "${response}" ".totalResults" "0")
        
        if [ "$total" = "0" ]; then
            log_error "User '${username}' not found"
            return 1
        fi
        
        echo "${response}" | jq '.Resources[0]'
    else
        log_error "Failed to fetch user"
        echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: delete-user - Delete a user
################################################################################

cmd_delete_user() {
    local username=${1:-}
    
    if [ -z "${username}" ]; then
        log_error "Usage: $0 delete-user <username>"
        return 1
    fi
    
    validate_username "${username}" || return 1
    check_dependencies || return 1
    check_container || return 1
    
    echo ""
    echo "=========================================="
    echo "  Delete User"
    echo "=========================================="
    echo ""
    
    # Get user ID
    log_info "Finding user '${username}'..."
    local encoded_username=$(url_encode "${username}")
    
    local response
    response=$(curl_with_retry -k -sS -u "${WSO2IS_ADMIN_USER}:${WSO2IS_ADMIN_PASS}" \
        "${SCIM2_API}/Users?filter=userName%20eq%20${encoded_username}")
    
    if [ $? -ne 0 ] || ! validate_json "${response}"; then
        log_error "Failed to find user"
        return 1
    fi
    
    local user_id=$(extract_json_field "${response}" ".Resources[0].id")
    
    if [ -z "${user_id}" ]; then
        log_error "User '${username}' not found"
        return 1
    fi
    
    log_info "Deleting user..."
    
    local temp_file=$(mktemp)
    local http_code
    
    http_code=$(curl --max-time 30 -k -sS -u "${WSO2IS_ADMIN_USER}:${WSO2IS_ADMIN_PASS}" \
        -o "${temp_file}" -w "%{http_code}" \
        -X DELETE "${SCIM2_API}/Users/${user_id}" 2>/dev/null)
    
    if [ "${http_code}" = "204" ]; then
        rm -f "${temp_file}"
        log_success "User deleted successfully"
        return 0
    else
        log_error "Failed to delete user (HTTP ${http_code})"
        cat "${temp_file}"
        rm -f "${temp_file}"
        return 1
    fi
}

################################################################################
# MAIN
################################################################################

show_help() {
    cat <<'HELP'

╔══════════════════════════════════════════════════════════════╗
║        WSO2 Identity Server - User Management                ║
╚══════════════════════════════════════════════════════════════╝

Usage: ./wso2is-user.sh <command> [options]

COMMANDS:
  register            Register a new user
  login               Authenticate user
  reset-password      Reset user password
  activate-user       Activate user account
  deactivate-user     Deactivate user account
  list-users          List all users
  get-user            Get user details
  delete-user         Delete a user

EXAMPLES:
  # Register new user
  ./wso2is-user.sh register john john123456 john@example.com John Doe

  # Login (basic authentication)
  ./wso2is-user.sh login john john123456

  # Login with OAuth2 (get tokens)
  ./wso2is-user.sh login john john123456 <client_id> <client_secret>

  # Reset password
  ./wso2is-user.sh reset-password john newPassword123

  # Activate/Deactivate
  ./wso2is-user.sh activate-user john activate
  ./wso2is-user.sh activate-user john deactivate

  # List all users
  ./wso2is-user.sh list-users

  # Get user details
  ./wso2is-user.sh get-user john

  # Delete user
  ./wso2is-user.sh delete-user john

NOTES:
  - Uses SCIM2 API for user operations
  - Passwords must be at least 8 characters
  - Admin credentials required for most operations
  - Login command can work with or without OAuth2 app

HELP
}

COMMAND=${1:-help}

case "${COMMAND}" in
    register)
        shift
        cmd_register "$@"
        ;;
    login)
        shift
        cmd_login "$@"
        ;;
    reset-password|reset_password)
        shift
        cmd_reset_password "$@"
        ;;
    activate-user|activate_user)
        shift
        cmd_activate_user "$@" activate
        ;;
    deactivate-user|deactivate_user)
        shift
        cmd_activate_user "$@" deactivate
        ;;
    list-users|list_users)
        cmd_list_users
        ;;
    get-user|get_user)
        shift
        cmd_get_user "$@"
        ;;
    delete-user|delete_user)
        shift
        cmd_delete_user "$@"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "Unknown command: ${COMMAND}"
        show_help
        exit 1
        ;;
esac
