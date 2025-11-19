#!/usr/bin/env bash

################################################################################
# Import APIs into WSO2 API Manager
# Creates the 7 core APIs programmatically
################################################################################

set -euo pipefail

APIM_HOST="localhost"
APIM_PORT="9443"
ADMIN_USER="admin"
ADMIN_PASS="admin"

# Backend service URLs (internal docker network)
# Note: These hostnames must be resolvable by the API Manager container
FOREX_URL="http://forex-service:8001"
LEDGER_URL="http://ledger-service:8002"
PAYMENT_URL="http://payment-service:8003"
PROFILE_URL="http://profile-service:8004"
RULE_ENGINE_URL="http://rule-engine-service:8005"
WALLET_URL="http://wallet-service:8006"
BANKING_URL="http://banking-service:8007"

log_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;32m[✓]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[✗]\033[0m $1"; }

create_api() {
    local name=$1
    local context=$2
    local version=$3
    local endpoint=$4
    
    log_info "Creating API: ${name} (${context}/${version})..."
    
    # Check if API exists
    local existing=$(curl -k -sS -u "${ADMIN_USER}:${ADMIN_PASS}" \
        "https://${APIM_HOST}:${APIM_PORT}/api/am/publisher/v4/apis?query=name:${name}")
    
    if echo "$existing" | grep -q "\"count\":0"; then
        # Create API Payload
        local payload=$(cat <<EOF
{
  "name": "${name}",
  "context": "${context}",
  "version": "${version}",
  "provider": "${ADMIN_USER}",
  "lifeCycleStatus": "CREATED",
  "type": "HTTP",
  "transport": ["http", "https"],
  "policies": ["Unlimited"],
  "visibility": "PUBLIC",
  "endpointConfig": {
    "endpoint_type": "http",
    "sandbox_endpoints": {
      "url": "${endpoint}"
    },
    "production_endpoints": {
      "url": "${endpoint}"
    }
  },
  "operations": [
    {
      "target": "/health",
      "verb": "GET",
      "authType": "Application & Application User",
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
  ]
}
EOF
)
        
        local response
        response=$(curl -k -sS -X POST \
            "https://${APIM_HOST}:${APIM_PORT}/api/am/publisher/v4/apis" \
            -u "${ADMIN_USER}:${ADMIN_PASS}" \
            -H "Content-Type: application/json" \
            -d "$payload")
            
        if echo "$response" | grep -q '"id"'; then
            local id=$(echo "$response" | jq -r '.id')
            log_success "API created successfully! ID: ${id}"
            return 0
        else
            log_error "Failed to create API"
            echo "$response" | jq . 2>/dev/null || echo "$response"
            return 1
        fi
    else
        log_info "API ${name} already exists."
        return 0
    fi
}

# Create the 7 APIs
create_api "ForexService" "/forex" "1.0.0" "${FOREX_URL}"
create_api "LedgerService" "/ledger" "1.0.0" "${LEDGER_URL}"
create_api "PaymentService" "/payment" "1.0.0" "${PAYMENT_URL}"
create_api "ProfileService" "/profile" "1.0.0" "${PROFILE_URL}"
create_api "RuleEngineService" "/rules" "1.0.0" "${RULE_ENGINE_URL}"
create_api "WalletService" "/wallet" "1.0.0" "${WALLET_URL}"
create_api "BankingService" "/banking" "1.0.0" "${BANKING_URL}"

log_success "All APIs processed."
