#!/bin/bash

################################################################################
# Get User Token - Simple & Working Script
#
# Usage: ./get_user_token.sh USERNAME PASSWORD
# Example: ./get_user_token.sh admin admin
################################################################################

# Working OAuth Credentials (Password Grant App)
CLIENT_ID="eV6gdOIlD8XmYGZd7fuK47A4jmsa"
CLIENT_SECRET="dL60GCNtzxJUn1a2NAO7f6C5AjRHfjZRYXEGUzw059Ma"

USERNAME=${1:-admin}
PASSWORD=${2:-admin}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 Getting token for user: $USERNAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get token
RESPONSE=$(curl -sk -u "${CLIENT_ID}:${CLIENT_SECRET}" \
  -X POST "https://localhost:9444/oauth2/token" \
  -d "grant_type=password&username=${USERNAME}&password=${PASSWORD}")

TOKEN=$(echo "$RESPONSE" | jq -r '.access_token // empty')

if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
  echo "✅ Token obtained successfully!"
  echo ""
  echo "Access Token:"
  echo "$TOKEN"
  echo ""
  echo "Token expires in: $(echo "$RESPONSE" | jq -r '.expires_in') seconds"
  echo ""
  
  # Test API call
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🧪 Testing API Gateway with token..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  API_RESPONSE=$(curl -sk -H "Authorization: Bearer $TOKEN" \
    "https://localhost:8243/forex/v1/health")
  
  if echo "$API_RESPONSE" | jq -e '.status' >/dev/null 2>&1; then
    echo "✅ API call successful!"
    echo "$API_RESPONSE" | jq '.'
  else
    echo "⚠️ API response:"
    echo "$API_RESPONSE"
  fi
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📋 Usage Example:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "# Export token:"
  echo "export TOKEN=\"$TOKEN\""
  echo ""
  echo "# Call any API:"
  echo "curl -sk -H \"Authorization: Bearer \$TOKEN\" \\"
  echo "  https://localhost:8243/forex/v1/health"
  echo ""
  
else
  echo "❌ Failed to get token"
  echo ""
  ERROR=$(echo "$RESPONSE" | jq -r '.error // empty')
  ERROR_DESC=$(echo "$RESPONSE" | jq -r '.error_description // empty')
  
  if [ -n "$ERROR" ]; then
    echo "Error: $ERROR"
    [ -n "$ERROR_DESC" ] && echo "Description: $ERROR_DESC"
  else
    echo "Response:"
    echo "$RESPONSE" | jq '.'
  fi
  
  echo ""
  echo "💡 Tip: To create a new user:"
  echo "   1. Go to https://localhost:9444/console"
  echo "   2. Login as admin/admin"
  echo "   3. Users → Add User"
  echo "   4. Create user and test with this script"
  echo ""
  
  exit 1
fi
