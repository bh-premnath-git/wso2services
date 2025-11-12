#!/usr/bin/env bash

################################################################################
# WSO2 API Manager - Complete API Lifecycle Management
#
# Features:
# - Create REST APIs
# - Subscribe applications to APIs
# - Create API revisions
# - Deploy APIs to gateway
# - Uses external WSO2 IS Key Manager
#
# Usage: ./api-manager.sh <command> [options]
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
APIM_ADMIN_USER="${APIM_ADMIN_USER:-admin}"
APIM_ADMIN_PASS="${APIM_ADMIN_PASS:-admin}"

GATEWAY_ENV="${GATEWAY_ENV:-Default}"

# API endpoints
PUBLISHER_API="https://${APIM_HOST}:${APIM_PORT}/api/am/publisher/v4"
DEVPORTAL_API="https://${APIM_HOST}:${APIM_PORT}/api/am/devportal/v3"
ADMIN_API="https://${APIM_HOST}:${APIM_PORT}/api/am/admin/v4"

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Input validation
validate_api_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid API name: '$name'"
        log_error "Only alphanumeric characters, underscores, and hyphens allowed"
        return 1
    fi
    return 0
}

validate_version() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Invalid version: '$version'"
        log_error "Use semantic versioning: 1.0, 1.0.0, etc."
        return 1
    fi
    return 0
}

validate_context() {
    local context="$1"
    # Check basic format
    if [[ ! "$context" =~ ^/[a-zA-Z0-9/_-]+$ ]]; then
        log_error "Invalid context: '$context'"
        log_error "Context must start with / and contain only alphanumeric, /, _, -"
        return 1
    fi
    # Check for double slashes
    if [[ "$context" =~ // ]]; then
        log_error "Invalid context: '$context'"
        log_error "Context cannot contain double slashes (//)"
        return 1
    fi
    # Check for trailing slash
    if [[ "$context" =~ /$ ]] && [ "${context}" != "/" ]; then
        log_error "Invalid context: '$context'"
        log_error "Context cannot end with /"
        return 1
    fi
    return 0
}

check_container() {
    local container="$1"
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        log_error "Container '${container}' is not running"
        log_error "Start it with: docker compose up -d ${container}"
        return 1
    fi
    return 0
}

# Check if jq is available
check_dependencies() {
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required but not installed"
        log_error "Install with: sudo apt-get install jq"
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl is required but not installed"
        log_error "Install with: sudo apt-get install curl"
        return 1
    fi
    return 0
}

# Enhanced curl with timeout and retry logic
curl_with_retry() {
    local max_attempts=3
    local timeout=30
    local attempt=1
    local http_code
    local response
    local temp_file=$(mktemp)
    
    while [ $attempt -le $max_attempts ]; do
        if [ $attempt -gt 1 ]; then
            log_info "Retry attempt $attempt of $max_attempts..."
            sleep 2
        fi
        
        # Run curl with timeout and capture both response and HTTP code
        http_code=$(curl --max-time $timeout -w "%{http_code}" -o "${temp_file}" "$@" 2>/dev/null)
        local curl_exit=$?
        
        if [ $curl_exit -eq 0 ]; then
            # Check if HTTP code indicates success (2xx or 3xx)
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

# Safe JSON extraction using jq
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

# Validate JSON response
validate_json() {
    local json="$1"
    if ! echo "$json" | jq empty 2>/dev/null; then
        log_error "Invalid JSON response received"
        return 1
    fi
    return 0
}

# Create unique temp file with locking
create_temp_file() {
    local prefix="$1"
    local temp_file=$(mktemp /tmp/"${prefix}".XXXXXX)
    echo "${temp_file}"
}

# URL encode
url_encode() {
    local string="$1"
    echo -n "$string" | jq -sRr @uri
}

# JSON escape
json_escape() {
    local string="$1"
    echo -n "$string" | jq -Rs .
}

################################################################################
# COMMAND: create-api - Create a REST API
################################################################################

cmd_create_api() {
    local api_name=${1:-}
    local version=${2:-"1.0.0"}
    local context=${3:-}
    local backend_url=${4:-"http://httpbin.org"}
    
    if [ -z "${api_name}" ]; then
        log_error "Usage: $0 create-api <name> [version] [context] [backend_url]"
        echo ""
        echo "Examples:"
        echo "  $0 create-api PaymentAPI 1.0.0 /payment http://payment-service:8003"
        echo "  $0 create-api BankingAPI 1.0.0 /banking http://banking-service:8007"
        echo "  $0 create-api ForexAPI 1.0.0 /forex http://forex-service:8001"
        return 1
    fi
    
    # Set default context if not provided
    if [ -z "${context}" ]; then
        context="/${api_name,,}"  # Lowercase API name
    fi
    
    # Validate inputs
    validate_api_name "${api_name}" || return 1
    validate_version "${version}" || return 1
    validate_context "${context}" || return 1
    
    # Check dependencies and containers
    check_dependencies || return 1
    check_container "wso2am" || return 1
    
    echo ""
    echo "=========================================="
    echo "  Create REST API"
    echo "=========================================="
    echo ""
    
    log_info "API Name: ${api_name}"
    log_info "Version: ${version}"
    log_info "Context: ${context}"
    log_info "Backend: ${backend_url}"
    echo ""
    
    # Create API payload
    local payload
    read -r -d '' payload <<EOF || true
{
  "name": "${api_name}",
  "version": "${version}",
  "context": "${context}",
  "type": "HTTP",
  "transport": ["http", "https"],
  "visibility": "PUBLIC",
  "endpointConfig": {
    "endpoint_type": "http",
    "production_endpoints": {
      "url": "${backend_url}"
    },
    "sandbox_endpoints": {
      "url": "${backend_url}"
    }
  },
  "operations": [
    {
      "target": "/*",
      "verb": "GET",
      "throttlingPolicy": "Unlimited",
      "authType": "Application & Application User"
    },
    {
      "target": "/*",
      "verb": "POST",
      "throttlingPolicy": "Unlimited",
      "authType": "Application & Application User"
    },
    {
      "target": "/*",
      "verb": "PUT",
      "throttlingPolicy": "Unlimited",
      "authType": "Application & Application User"
    },
    {
      "target": "/*",
      "verb": "DELETE",
      "throttlingPolicy": "Unlimited",
      "authType": "Application & Application User"
    }
  ],
  "businessInformation": {
    "businessOwner": "API Team",
    "businessOwnerEmail": "api@example.com"
  },
  "policies": ["Unlimited"],
  "subscriptionAvailability": "ALL_TENANTS",
  "gatewayVendor": "wso2",
  "isDefaultVersion": false,
  "enableSchemaValidation": false,
  "accessControl": "NONE"
}
EOF
    
    log_info "Creating API..."
    local response
    response=$(curl_with_retry -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        -X POST "${PUBLISHER_API}/apis")
    
    local curl_exit=$?
    if [ $curl_exit -ne 0 ]; then
        log_error "Failed to connect to API Manager"
        return 1
    fi
    
    # Validate JSON response
    if ! validate_json "${response}"; then
        log_error "Invalid response from server"
        echo "${response}"
        return 1
    fi
    
    # Extract API ID using jq
    local api_id=$(extract_json_field "${response}" ".id")
    
    if [ -n "${api_id}" ]; then
        log_success "API created successfully!"
        echo ""
        echo "API ID: ${api_id}"
        echo "Name: ${api_name}"
        echo "Version: ${version}"
        echo "Context: ${context}"
        echo ""
        echo "Next steps:"
        echo "  1. Publish API: $0 publish-api ${api_id}"
        echo "  2. Subscribe: $0 subscribe <application-id> ${api_id}"
        echo "  3. Deploy: $0 deploy-api ${api_id}"
        echo ""
        
        # Store API ID in unique temp file with locking
        local temp_file=$(create_temp_file "api_manager_last_api")
        echo "${api_id}" > "${temp_file}"
        ln -sf "${temp_file}" /tmp/api_manager_last_api_id.txt
        return 0
    else
        log_error "Failed to create API"
        echo "${response}" | jq . 2>/dev/null || echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: list-apis - List all APIs
################################################################################

cmd_list_apis() {
    check_container "wso2am" || return 1
    
    echo ""
    echo "=========================================="
    echo "  All APIs"
    echo "=========================================="
    echo ""
    
    check_dependencies || return 1
    
    log_info "Fetching APIs..."
    local response
    response=$(curl_with_retry -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        "${PUBLISHER_API}/apis?limit=100")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to connect to API Manager"
        return 1
    fi
    
    if validate_json "${response}" && echo "${response}" | jq -e '.list' >/dev/null 2>&1; then
        echo "${response}" | jq .
    else
        log_error "Failed to fetch APIs or invalid response"
        echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: publish-api - Change API lifecycle to PUBLISHED
################################################################################

cmd_publish_api() {
    local api_id=${1:-}
    
    if [ -z "${api_id}" ]; then
        # Try to get last created API ID
        if [ -L /tmp/api_manager_last_api_id.txt ]; then
            api_id=$(cat /tmp/api_manager_last_api_id.txt 2>/dev/null)
            if [ -n "${api_id}" ]; then
                log_info "Using last created API ID: ${api_id}"
            else
                log_error "Could not read last API ID"
                return 1
            fi
        else
            log_error "Usage: $0 publish-api <api-id>"
            echo ""
            echo "Get API ID from: $0 list-apis"
            return 1
        fi
    fi
    
    check_dependencies || return 1
    
    check_container "wso2am" || return 1
    
    echo ""
    echo "=========================================="
    echo "  Publish API"
    echo "=========================================="
    echo ""
    
    # URL encode the API ID
    local encoded_api_id=$(url_encode "${api_id}")
    
    log_info "Publishing API ${api_id}..."
    local response
    response=$(curl_with_retry -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        -X POST "${PUBLISHER_API}/apis/change-lifecycle?apiId=${encoded_api_id}&action=Publish")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to connect to API Manager"
        return 1
    fi
    
    if validate_json "${response}"; then
        local state=$(extract_json_field "${response}" ".lifecycleState" "UNKNOWN")
        log_success "API published successfully!"
        echo ""
        echo "Lifecycle State: ${state}"
        echo ""
        return 0
    else
        log_error "Failed to publish API"
        echo "${response}" | jq . 2>/dev/null || echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: create-revision - Create API revision
################################################################################

cmd_create_revision() {
    local api_id=${1:-}
    local description=${2:-"Revision created via script"}
    
    if [ -z "${api_id}" ]; then
        if [ -L /tmp/api_manager_last_api_id.txt ]; then
            api_id=$(cat /tmp/api_manager_last_api_id.txt 2>/dev/null)
            if [ -n "${api_id}" ]; then
                log_info "Using last created API ID: ${api_id}"
            else
                log_error "Could not read last API ID"
                return 1
            fi
        else
            log_error "Usage: $0 create-revision <api-id> [description]"
            return 1
        fi
    fi
    
    check_dependencies || return 1
    check_container "wso2am" || return 1
    
    echo ""
    echo "=========================================="
    echo "  Create API Revision"
    echo "=========================================="
    echo ""
    
    log_info "Creating revision for API ${api_id}..."
    
    # Safely escape description for JSON
    local escaped_desc=$(json_escape "${description}")
    local payload="{\"description\": ${escaped_desc}}"
    
    # URL encode API ID
    local encoded_api_id=$(url_encode "${api_id}")
    
    local response
    response=$(curl_with_retry -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        -X POST "${PUBLISHER_API}/apis/${encoded_api_id}/revisions")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to connect to API Manager"
        return 1
    fi
    
    if ! validate_json "${response}"; then
        log_error "Invalid response from server"
        echo "${response}"
        return 1
    fi
    
    local revision_id=$(extract_json_field "${response}" ".id")
    
    if [ -n "${revision_id}" ]; then
        log_success "Revision created successfully!"
        echo ""
        echo "Revision ID: ${revision_id}"
        echo ""
        echo "Next step:"
        echo "  $0 deploy-revision ${api_id} ${revision_id}"
        echo ""
        
        # Store in unique temp file
        local temp_file=$(create_temp_file "api_manager_last_revision")
        echo "${revision_id}" > "${temp_file}"
        ln -sf "${temp_file}" /tmp/api_manager_last_revision_id.txt
        return 0
    else
        log_error "Failed to create revision"
        echo "${response}" | jq . 2>/dev/null || echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: deploy-revision - Deploy API revision to gateway
################################################################################

cmd_deploy_revision() {
    local api_id=${1:-}
    local revision_id=${2:-}
    
    if [ -z "${api_id}" ]; then
        if [ -L /tmp/api_manager_last_api_id.txt ]; then
            api_id=$(cat /tmp/api_manager_last_api_id.txt 2>/dev/null)
            if [ -n "${api_id}" ]; then
                log_info "Using last created API ID: ${api_id}"
            else
                log_error "Could not read last API ID"
                return 1
            fi
        else
            log_error "Usage: $0 deploy-revision <api-id> <revision-id>"
            return 1
        fi
    fi
    
    if [ -z "${revision_id}" ]; then
        if [ -L /tmp/api_manager_last_revision_id.txt ]; then
            revision_id=$(cat /tmp/api_manager_last_revision_id.txt 2>/dev/null)
            if [ -n "${revision_id}" ]; then
                log_info "Using last created revision ID: ${revision_id}"
            else
                log_error "Could not read last revision ID"
                return 1
            fi
        else
            log_error "Usage: $0 deploy-revision <api-id> <revision-id>"
            return 1
        fi
    fi
    
    check_dependencies || return 1
    check_container "wso2am" || return 1
    
    echo ""
    echo "=========================================="
    echo "  Deploy API Revision"
    echo "=========================================="
    echo ""
    
    log_info "Deploying revision ${revision_id} to ${GATEWAY_ENV}..."
    
    local payload
    read -r -d '' payload <<EOF || true
[
  {
    "name": "${GATEWAY_ENV}",
    "vhost": "localhost",
    "displayOnDevportal": true
  }
]
EOF
    
    # URL encode parameters
    local encoded_api_id=$(url_encode "${api_id}")
    local encoded_revision_id=$(url_encode "${revision_id}")
    
    local response
    response=$(curl_with_retry -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        -X POST "${PUBLISHER_API}/apis/${encoded_api_id}/deploy-revision?revisionId=${encoded_revision_id}")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to connect to API Manager"
        return 1
    fi
    
    if validate_json "${response}" && echo "${response}" | jq -e '.[0].name' >/dev/null 2>&1; then
        log_success "Revision deployed to gateway!"
        echo ""
        echo "Environment: ${GATEWAY_ENV}"
        echo "VHost: localhost"
        echo ""
        echo "API is now live and accessible via gateway!"
        echo ""
        return 0
    else
        log_error "Failed to deploy revision"
        echo "${response}" | jq . 2>/dev/null || echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: subscribe - Subscribe application to API
################################################################################

cmd_subscribe() {
    local app_id=${1:-}
    local api_id=${2:-}
    local tier=${3:-"Unlimited"}
    
    if [ -z "${app_id}" ] || [ -z "${api_id}" ]; then
        log_error "Usage: $0 subscribe <application-id> <api-id> [tier]"
        echo ""
        echo "Get application ID: ../wso2-toolkit.sh list-apps"
        echo "Get API ID: $0 list-apis"
        echo ""
        echo "Available tiers: Unlimited, Gold, Silver, Bronze"
        return 1
    fi
    
    check_dependencies || return 1
    check_container "wso2am" || return 1
    
    echo ""
    echo "=========================================="
    echo "  Subscribe Application to API"
    echo "=========================================="
    echo ""
    
    log_info "Creating subscription..."
    
    local payload
    read -r -d '' payload <<EOF || true
{
  "applicationId": "${app_id}",
  "apiId": "${api_id}",
  "throttlingPolicy": "${tier}"
}
EOF
    
    local response
    response=$(curl_with_retry -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        -X POST "${DEVPORTAL_API}/subscriptions")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to connect to API Manager"
        return 1
    fi
    
    if ! validate_json "${response}"; then
        log_error "Invalid response from server"
        echo "${response}"
        return 1
    fi
    
    local sub_id=$(extract_json_field "${response}" ".subscriptionId")
    
    if [ -n "${sub_id}" ]; then
        log_success "Subscription created successfully!"
        echo ""
        echo "Subscription ID: ${sub_id}"
        echo "Tier: ${tier}"
        echo ""
        echo "Application can now access the API using OAuth2 tokens!"
        echo ""
        return 0
    else
        log_error "Failed to create subscription"
        echo "${response}" | jq . 2>/dev/null || echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: list-subscriptions - List all subscriptions
################################################################################

cmd_list_subscriptions() {
    local id=${1:-}
    local filter_type=${2:-"app"}  # Default to application filter
    
    check_dependencies || return 1
    check_container "wso2am" || return 1
    
    echo ""
    echo "=========================================="
    echo "  API Subscriptions"
    echo "=========================================="
    echo ""
    
    local url="${DEVPORTAL_API}/subscriptions?limit=100"
    if [ -n "${id}" ]; then
        local encoded_id=$(url_encode "${id}")
        if [ "${filter_type}" = "api" ]; then
            url="${url}&apiId=${encoded_id}"
            log_info "Fetching subscriptions for API ${id}..."
        else
            url="${url}&applicationId=${encoded_id}"
            log_info "Fetching subscriptions for Application ${id}..."
        fi
    else
        log_error "Usage: $0 list-subscriptions <app-id|api-id> [app|api]"
        echo ""
        echo "Examples:"
        echo "  $0 list-subscriptions <app-id>        # List by application (default)"
        echo "  $0 list-subscriptions <app-id> app    # List by application"
        echo "  $0 list-subscriptions <api-id> api    # List by API"
        return 1
    fi
    
    local response
    response=$(curl_with_retry -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" "${url}")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to connect to API Manager"
        return 1
    fi
    
    if validate_json "${response}" && echo "${response}" | jq -e '.list' >/dev/null 2>&1; then
        echo "${response}" | jq .
    else
        log_error "Failed to fetch subscriptions or invalid response"
        echo "${response}"
        return 1
    fi
}

################################################################################
# COMMAND: deploy-api - Complete deployment (publish + revision + deploy)
################################################################################

cmd_deploy_api() {
    local api_id=${1:-}
    
    if [ -z "${api_id}" ]; then
        if [ -L /tmp/api_manager_last_api_id.txt ]; then
            api_id=$(cat /tmp/api_manager_last_api_id.txt 2>/dev/null)
            if [ -n "${api_id}" ]; then
                log_info "Using last created API ID: ${api_id}"
            else
                log_error "Could not read last API ID"
                return 1
            fi
        else
            log_error "Usage: $0 deploy-api <api-id>"
            return 1
        fi
    fi
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║          Complete API Deployment                         ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    
    # Step 1: Publish
    log_info "Step 1/3: Publishing API..."
    if ! cmd_publish_api "${api_id}"; then
        log_error "Failed at publish step"
        return 1
    fi
    
    # Step 2: Create revision
    log_info "Step 2/3: Creating revision..."
    if ! cmd_create_revision "${api_id}" "Auto-deployment revision"; then
        log_error "Failed at revision creation step"
        return 1
    fi
    
    local revision_id=$(cat /tmp/api_manager_last_revision_id.txt 2>/dev/null)
    if [ -z "${revision_id}" ]; then
        log_error "Could not read revision ID"
        return 1
    fi
    
    # Step 3: Deploy revision
    log_info "Step 3/3: Deploying to gateway..."
    if ! cmd_deploy_revision "${api_id}" "${revision_id}"; then
        log_error "Failed at deployment step"
        return 1
    fi
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║          ✅ API Deployed Successfully!                   ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    log_success "API is now live on the gateway!"
    echo ""
    echo "Test your API:"
    echo "  curl -H 'Authorization: Bearer <TOKEN>' https://localhost:8243<CONTEXT>"
    echo ""
}

################################################################################
# COMMAND: quick-deploy - Create, publish, and deploy in one command
################################################################################

cmd_quick_deploy() {
    local api_name=${1:-}
    local version=${2:-"1.0.0"}
    local context=${3:-}
    local backend_url=${4:-"http://httpbin.org"}
    
    if [ -z "${api_name}" ]; then
        log_error "Usage: $0 quick-deploy <name> [version] [context] [backend_url]"
        echo ""
        echo "Examples:"
        echo "  $0 quick-deploy PaymentAPI 1.0.0 /payment http://payment-service:8003"
        echo "  $0 quick-deploy BankingAPI 1.0.0 /banking http://banking-service:8007"
        return 1
    fi
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║          Quick API Deployment                            ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    
    # Step 1: Create API
    log_info "Step 1/4: Creating API..."
    if ! cmd_create_api "${api_name}" "${version}" "${context}" "${backend_url}"; then
        log_error "Failed to create API"
        return 1
    fi
    
    local api_id=$(cat /tmp/api_manager_last_api_id.txt 2>/dev/null)
    if [ -z "${api_id}" ]; then
        log_error "Could not read created API ID"
        return 1
    fi
    
    # Step 2-4: Deploy
    log_info "Step 2-4/4: Deploying API..."
    if ! cmd_deploy_api "${api_id}"; then
        log_error "Failed to deploy API"
        return 1
    fi
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║          ✅ Quick Deploy Complete!                       ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "API Details:"
    echo "  Name: ${api_name}"
    echo "  Version: ${version}"
    echo "  Context: ${context}"
    echo "  API ID: ${api_id}"
    echo ""
    echo "Next steps:"
    echo "  1. Create OAuth app: ../wso2-toolkit.sh create-app MyApp"
    echo "  2. Subscribe: $0 subscribe <app-id> ${api_id}"
    echo "  3. Get token: ../wso2-toolkit.sh get-token cc <client-id> <secret>"
    echo "  4. Call API: curl -H 'Authorization: Bearer <TOKEN>' https://localhost:8243${context}"
    echo ""
}

################################################################################
# COMMAND: delete-api - Delete an API
################################################################################

cmd_delete_api() {
    local api_id=${1:-}
    
    if [ -z "${api_id}" ]; then
        log_error "Usage: $0 delete-api <api-id>"
        echo ""
        echo "Get API ID from: $0 list-apis"
        return 1
    fi
    
    check_container "wso2am" || return 1
    
    echo ""
    echo "=========================================="
    echo "  Delete API"
    echo "=========================================="
    echo ""
    
    check_dependencies || return 1
    
    log_info "Deleting API ${api_id}..."
    
    local encoded_api_id=$(url_encode "${api_id}")
    local temp_file=$(mktemp)
    local http_code
    
    http_code=$(curl --max-time 30 -k -sS -u "${APIM_ADMIN_USER}:${APIM_ADMIN_PASS}" \
        -o "${temp_file}" -w "%{http_code}" \
        -X DELETE "${PUBLISHER_API}/apis/${encoded_api_id}" 2>/dev/null)
    
    local curl_exit=$?
    
    if [ $curl_exit -ne 0 ]; then
        rm -f "${temp_file}"
        log_error "Failed to connect to API Manager"
        return 1
    fi
    
    if [ "${http_code}" = "200" ]; then
        rm -f "${temp_file}"
        log_success "API deleted successfully"
        return 0
    else
        log_error "Failed to delete API (HTTP ${http_code})"
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
║        WSO2 API Manager - Complete API Lifecycle            ║
╚══════════════════════════════════════════════════════════════╝

Usage: ./api-manager.sh <command> [options]

COMMANDS:
  create-api          Create a REST API
  list-apis           List all APIs
  publish-api         Publish an API
  create-revision     Create API revision
  deploy-revision     Deploy revision to gateway
  deploy-api          Complete deployment (publish+revision+deploy)
  quick-deploy        Create and deploy in one command
  
  subscribe           Subscribe app to API
  list-subscriptions  List all subscriptions
  
  delete-api          Delete an API

EXAMPLES:
  # Quick deploy (everything in one command)
  ./api-manager.sh quick-deploy PaymentAPI 1.0.0 /payment http://payment-service:8003
  ./api-manager.sh quick-deploy BankingAPI 1.0.0 /banking http://banking-service:8007

  # Step by step
  ./api-manager.sh create-api ForexAPI 1.0.0 /forex http://forex-service:8001
  ./api-manager.sh deploy-api <api-id>

  # Available backend services:
  #   banking-service:8007, forex-service:8001, ledger-service:8002,
  #   payment-service:8003, profile-service:8004, rule-engine-service:8005,
  #   wallet-service:8006

  # Subscribe application
  ./api-manager.sh subscribe <app-id> <api-id> Unlimited

  # List resources
  ./api-manager.sh list-apis
  ./api-manager.sh list-subscriptions <app-id> app
  ./api-manager.sh list-subscriptions <api-id> api

NOTES:
  - Uses external WSO2 IS Key Manager for OAuth2
  - APIs require OAuth2 tokens for access
  - Create OAuth apps with: ../wso2-toolkit.sh create-app
  - Get tokens with: ../wso2-toolkit.sh get-token cc <id> <secret>

HELP
}

COMMAND=${1:-help}

case "${COMMAND}" in
    create-api)
        shift
        cmd_create_api "$@"
        ;;
    list-apis)
        cmd_list_apis
        ;;
    publish-api)
        shift
        cmd_publish_api "$@"
        ;;
    create-revision)
        shift
        cmd_create_revision "$@"
        ;;
    deploy-revision)
        shift
        cmd_deploy_revision "$@"
        ;;
    deploy-api)
        shift
        cmd_deploy_api "$@"
        ;;
    quick-deploy)
        shift
        cmd_quick_deploy "$@"
        ;;
    subscribe)
        shift
        cmd_subscribe "$@"
        ;;
    list-subscriptions)
        shift
        cmd_list_subscriptions "$@"
        ;;
    delete-api)
        shift
        cmd_delete_api "$@"
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
