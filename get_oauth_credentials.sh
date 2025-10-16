#!/bin/bash

################################################################################
# Get OAuth Client Credentials for Password Grant
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Get OAuth Client Credentials                             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

log_info "Fetching OAuth applications from WSO2 IS..."

# Get all applications
APPS=$(curl -sk -u "admin:admin" \
    "https://localhost:9444/t/carbon.super/api/server/v1/applications?limit=50")

# Find password grant apps
log_info "Looking for password grant OAuth applications..."
echo ""

# Filter applications with password grant
APP_COUNT=$(echo "$APPS" | jq '.applications | length')

if [ "$APP_COUNT" -eq 0 ]; then
    log_error "No applications found"
    exit 1
fi

echo "Found $APP_COUNT applications. Checking OAuth configurations..."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for i in $(seq 0 $((APP_COUNT - 1))); do
    APP_ID=$(echo "$APPS" | jq -r ".applications[$i].id")
    APP_NAME=$(echo "$APPS" | jq -r ".applications[$i].name")
    
    # Get OAuth config for this app
    OAUTH_CONFIG=$(curl -sk -u "admin:admin" \
        "https://localhost:9444/t/carbon.super/api/server/v1/applications/${APP_ID}/inbound-protocols/oidc" 2>/dev/null)
    
    if [ -n "$OAUTH_CONFIG" ] && [ "$OAUTH_CONFIG" != "null" ]; then
        CLIENT_ID=$(echo "$OAUTH_CONFIG" | jq -r '.clientId // empty')
        
        if [ -n "$CLIENT_ID" ]; then
            CLIENT_SECRET=$(echo "$OAUTH_CONFIG" | jq -r '.clientSecret // empty')
            GRANT_TYPES=$(echo "$OAUTH_CONFIG" | jq -r '.grantTypes[]' | tr '\n' ', ' | sed 's/,$//')
            
            # Check if it supports password grant
            if echo "$GRANT_TYPES" | grep -q "password"; then
                echo ""
                echo -e "${GREEN}✅ Password Grant App Found${NC}"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""
                echo "Application Name: $APP_NAME"
                echo "Application ID:   $APP_ID"
                echo ""
                echo -e "${BLUE}Client ID:${NC}        $CLIENT_ID"
                echo -e "${BLUE}Client Secret:${NC}    $CLIENT_SECRET"
                echo ""
                echo "Grant Types:      $GRANT_TYPES"
                echo ""
                
                # Test if it works
                log_info "Testing with admin user..."
                TOKEN_RESPONSE=$(curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \
                    -X POST "https://localhost:9444/oauth2/token" \
                    -d "grant_type=password&username=admin&password=admin" 2>/dev/null)
                
                TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
                
                if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
                    echo -e "${GREEN}✅ WORKING!${NC} Token obtained successfully"
                    echo "   Token: ${TOKEN:0:40}..."
                    echo ""
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo ""
                    echo "📋 Usage:"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo ""
                    echo "# Get token for any user:"
                    echo "curl -sk -u \"${CLIENT_ID}:${CLIENT_SECRET}\" \\"
                    echo "  -X POST \"https://localhost:9444/oauth2/token\" \\"
                    echo "  -d \"grant_type=password&username=USERNAME&password=PASSWORD\""
                    echo ""
                    echo "# Or use the helper script:"
                    echo "./get_user_token.sh USERNAME PASSWORD"
                    echo ""
                    
                    # Save to file
                    CRED_FILE="/tmp/oauth_working_credentials.txt"
                    cat > "$CRED_FILE" <<EOF
═══════════════════════════════════════════════════════════
Working OAuth Credentials (Password Grant)
═══════════════════════════════════════════════════════════

Application: $APP_NAME
Client ID:   $CLIENT_ID
Client Secret: $CLIENT_SECRET

Grant Types: $GRANT_TYPES

Token Endpoint: https://localhost:9444/oauth2/token

Test Command:
curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \\
  -X POST "https://localhost:9444/oauth2/token" \\
  -d "grant_type=password&username=admin&password=admin"

Helper Script:
./get_user_token.sh admin admin

═══════════════════════════════════════════════════════════
Generated: $(date)
═══════════════════════════════════════════════════════════
EOF
                    
                    log_success "Credentials saved to: $CRED_FILE"
                    
                else
                    echo -e "${YELLOW}⚠️  Not working${NC} - Authentication failed"
                fi
                
                echo ""
            fi
        fi
    fi
done

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Recommendation                                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "If you didn't find a working password grant app above,"
echo "create one with:"
echo ""
echo "  ./app_scripts/create_working_password_grant_app.sh"
echo ""
