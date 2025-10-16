#!/usr/bin/env bash

################################################################################
# Complete CLI Test Example for User "user"
#
# This script shows how to:
# 1. Create OAuth client in WSO2 IS
# 2. Get token for user "user"
# 3. Call APIs through WSO2 AM Gateway
#
# Usage: ./TEST_USER_EXAMPLE.sh
################################################################################

echo "════════════════════════════════════════════════════════════"
echo "  WSO2 Complete Flow Test - User: 'user'"
echo "════════════════════════════════════════════════════════════"
echo ""

# Step 1: Create OAuth Client in WSO2 IS
echo "Step 1: Creating OAuth client in WSO2 IS..."
echo ""
echo "Command:"
echo 'curl -sk -u "admin:admin" -X POST \'
echo '  https://localhost:9444/api/identity/oauth2/dcr/v1.1/register \'
echo '  -H "Content-Type: application/json" \'
echo '  -d '"'"'{
    "client_name": "TestApp_User",
    "grant_types": ["password", "client_credentials"],
    "redirect_uris": ["https://localhost/callback"]
  }'"'"

echo ""

DCR_RESPONSE=$(curl -sk -u "admin:admin" -X POST \
  https://localhost:9444/api/identity/oauth2/dcr/v1.1/register \
  -H "Content-Type: application/json" \
  -d '{
    "client_name": "TestApp_User",
    "grant_types": ["password", "client_credentials"],
    "redirect_uris": ["https://localhost/callback"]
  }')

CLIENT_ID=$(echo "$DCR_RESPONSE" | jq -r '.client_id')
CLIENT_SECRET=$(echo "$DCR_RESPONSE" | jq -r '.client_secret')

echo "Response:"
echo "$DCR_RESPONSE" | jq '.'
echo ""
echo "✅ CLIENT_ID:     $CLIENT_ID"
echo "✅ CLIENT_SECRET: $CLIENT_SECRET"
echo ""

# Step 2: Get Token for user "user"
echo "════════════════════════════════════════════════════════════"
echo "Step 2: User 'user' authenticates and gets token..."
echo ""
echo "User Credentials:"
echo "  Username: user"
echo "  Password: User1234!"
echo ""
echo "Command:"
echo "curl -sk -u \"${CLIENT_ID}:${CLIENT_SECRET}\" \\"
echo "  -d \"grant_type=password&username=user&password=User1234!\" \\"
echo "  https://localhost:9444/oauth2/token"
echo ""

TOKEN_RESPONSE=$(curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \
  -d "grant_type=password&username=user&password=User1234!" \
  https://localhost:9444/oauth2/token)

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

echo "Response:"
echo "$TOKEN_RESPONSE" | jq '.'
echo ""
echo "✅ ACCESS_TOKEN: $ACCESS_TOKEN"
echo ""

# Step 3: Test APIs with Token
echo "════════════════════════════════════════════════════════════"
echo "Step 3: Calling APIs through WSO2 AM Gateway..."
echo ""

# Test Forex API
echo "Test 1: Forex Service"
echo "Command:"
echo "curl -k -H \"Authorization: Bearer \$ACCESS_TOKEN\" \\"
echo "  https://localhost:8243/forex/v1/health"
echo ""
echo "Response:"
curl -sk -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  https://localhost:8243/forex/v1/health | jq '.'
echo ""

# Test Profile API
echo "Test 2: Profile Service"
echo "Command:"
echo "curl -k -H \"Authorization: Bearer \$ACCESS_TOKEN\" \\"
echo "  https://localhost:8243/profile/v1/health"
echo ""
echo "Response:"
curl -sk -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  https://localhost:8243/profile/v1/health | jq '.'
echo ""

# Test Wallet API
echo "Test 3: Wallet Service"
echo "Command:"
echo "curl -k -H \"Authorization: Bearer \$ACCESS_TOKEN\" \\"
echo "  https://localhost:8243/wallet/v1/health"
echo ""
echo "Response:"
curl -sk -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  https://localhost:8243/wallet/v1/health | jq '.'
echo ""

# Summary
echo "════════════════════════════════════════════════════════════"
echo "✅ COMPLETE FLOW SUCCESSFUL"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  1. OAuth client created in WSO2 IS"
echo "  2. User 'user' authenticated and received token"
echo "  3. APIs called successfully through WSO2 AM Gateway"
echo ""
echo "Save these for your application:"
echo ""
echo "# Environment Variables"
echo "export CLIENT_ID=\"${CLIENT_ID}\""
echo "export CLIENT_SECRET=\"${CLIENT_SECRET}\""
echo "export WSO2_IS_TOKEN_URL=\"https://localhost:9444/oauth2/token\""
echo "export WSO2_AM_GATEWAY_URL=\"https://localhost:8243\""
echo ""
echo "# Get Token"
echo "TOKEN=\$(curl -sk -u \"\${CLIENT_ID}:\${CLIENT_SECRET}\" \\"
echo "  -d \"grant_type=password&username=user&password=User1234!\" \\"
echo "  \${WSO2_IS_TOKEN_URL} | jq -r '.access_token')"
echo ""
echo "# Call API"
echo "curl -k -H \"Authorization: Bearer \$TOKEN\" \\"
echo "  \${WSO2_AM_GATEWAY_URL}/forex/v1/health"
echo ""
