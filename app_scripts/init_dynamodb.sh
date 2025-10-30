#!/bin/bash
set -e

echo "Initializing DynamoDB tables..."

# Install dependencies first
echo "Installing dependencies..."
apt-get update -qq > /dev/null 2>&1
apt-get install -y -qq curl > /dev/null 2>&1
pip install --no-cache-dir awscli > /dev/null 2>&1

# Wait for DynamoDB Local to be ready
echo "Waiting for DynamoDB Local..."
for i in {1..30}; do
    if curl -s http://dynamodb-local:8000/ > /dev/null 2>&1; then
        echo "DynamoDB Local is ready"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 1
done

# Create fx_rates table
echo "Creating fx_rates table..."
export AWS_ACCESS_KEY_ID=local
export AWS_SECRET_ACCESS_KEY=local
export AWS_DEFAULT_REGION=ap-south-1
export AWS_PAGER=""

aws dynamodb create-table \
    --table-name fx_rates \
    --attribute-definitions AttributeName=pair,AttributeType=S \
    --key-schema AttributeName=pair,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --endpoint-url http://dynamodb-local:8000 2>&1 || echo "Table may already exist"

# Verify table creation
echo "Verifying tables..."
aws dynamodb list-tables \
    --endpoint-url http://dynamodb-local:8000

echo "✓ DynamoDB initialization complete"
