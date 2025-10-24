#!/bin/bash
set -e

echo "🚀 Starting Complete Setup Test..."
echo ""

# Start services
echo "1. Starting services..."
docker compose up -d
sleep 120

# Health check
echo "2. Health check..."
./scripts/wso2-toolkit.sh health || exit 1

# Setup Key Manager
echo "3. Setting up Key Manager..."
./scripts/wso2-toolkit.sh setup-km || exit 1

# Disable Resident KM
echo "4. Disabling Resident KM..."
./scripts/wso2-toolkit.sh disable-resident-km || exit 1

# Fix MTLS
echo "5. Fixing MTLS..."
./scripts/wso2-toolkit.sh fix-mtls || exit 1
docker compose restart wso2am wso2is
sleep 120

# Create app
echo "6. Creating application..."
APP_OUTPUT=$(./scripts/wso2-toolkit.sh create-app TestApp http://localhost:8080/callback)
APP_ID=$(echo "$APP_OUTPUT" | grep "Application ID:" | awk '{print $3}')
CLIENT_ID=$(echo "$APP_OUTPUT" | grep "Client ID:" | awk '{print $3}')
CLIENT_SECRET=$(echo "$APP_OUTPUT" | grep "Client Secret:" | awk '{print $3}')

echo "   APP_ID: $APP_ID"
echo "   CLIENT_ID: $CLIENT_ID"

# Deploy API
echo "7. Deploying ForexAPI..."
API_OUTPUT=$(./scripts/api-manager.sh quick-deploy ForexAPI 1.0.0 /forex http://forex-service:8001)
API_ID=$(echo "$API_OUTPUT" | grep "API ID:" | head -1 | awk '{print $3}')
echo "   API_ID: $API_ID"

# Subscribe
echo "8. Subscribing..."
./scripts/api-manager.sh subscribe "$APP_ID" "$API_ID" || exit 1

# Register user
echo "9. Registering user..."
./scripts/wso2is-user.sh register testuser Test@1234 testuser@example.com Test User || exit 1

# Get token and test API
echo "10. Testing API call..."
TOKEN=$(./scripts/wso2is-user.sh login testuser Test@1234 "$CLIENT_ID" "$CLIENT_SECRET" 2>&1 | grep -A 100 '{' | grep -B 100 '}' | jq -r '.access_token')
echo "    Token: ${TOKEN:0:50}..."

RESPONSE=$(curl -k -H "Authorization: Bearer $TOKEN" -sS "https://localhost:8243/forex/1.0.0/")
echo "    Response: $RESPONSE"

if echo "$RESPONSE" | jq -e '.service' > /dev/null 2>&1; then
    echo ""
    echo "✅ SUCCESS! API is working!"
    exit 0
else
    echo ""
    echo "❌ FAILED! Got error: $RESPONSE"
    exit 1
fi
