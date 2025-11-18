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

# Export AWS credentials
export AWS_ACCESS_KEY_ID=local
export AWS_SECRET_ACCESS_KEY=local
export AWS_DEFAULT_REGION=ap-south-1
export AWS_PAGER=""

# Create fx_rates table
echo "Creating fx_rates table..."
aws dynamodb create-table \
    --table-name fx_rates \
    --attribute-definitions AttributeName=pair,AttributeType=S \
    --key-schema AttributeName=pair,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --endpoint-url http://dynamodb-local:8000 2>&1 || echo "Table may already exist"

# Create mastercard_customers table
echo "Creating mastercard_customers table..."
aws dynamodb create-table \
    --table-name mastercard_customers \
    --attribute-definitions \
        AttributeName=user_id,AttributeType=S \
        AttributeName=mastercard_customer_id,AttributeType=S \
    --key-schema AttributeName=user_id,KeyType=HASH \
    --global-secondary-indexes \
        "[{\"IndexName\":\"mastercard_customer_id_index\",\"KeySchema\":[{\"AttributeName\":\"mastercard_customer_id\",\"KeyType\":\"HASH\"}],\"Projection\":{\"ProjectionType\":\"ALL\"},\"ProvisionedThroughput\":{\"ReadCapacityUnits\":5,\"WriteCapacityUnits\":5}}]" \
    --billing-mode PROVISIONED \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --endpoint-url http://dynamodb-local:8000 2>&1 || echo "Table may already exist"

# Create linked_bank_accounts table
echo "Creating linked_bank_accounts table..."
aws dynamodb create-table \
    --table-name linked_bank_accounts \
    --attribute-definitions \
        AttributeName=user_id,AttributeType=S \
        AttributeName=account_id,AttributeType=S \
        AttributeName=mastercard_account_id,AttributeType=S \
    --key-schema \
        AttributeName=user_id,KeyType=HASH \
        AttributeName=account_id,KeyType=RANGE \
    --global-secondary-indexes \
        "[{\"IndexName\":\"mastercard_account_id_index\",\"KeySchema\":[{\"AttributeName\":\"mastercard_account_id\",\"KeyType\":\"HASH\"}],\"Projection\":{\"ProjectionType\":\"ALL\"},\"ProvisionedThroughput\":{\"ReadCapacityUnits\":5,\"WriteCapacityUnits\":5}}]" \
    --billing-mode PROVISIONED \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --endpoint-url http://dynamodb-local:8000 2>&1 || echo "Table may already exist"

# Create account_connection_logs table
echo "Creating account_connection_logs table..."
aws dynamodb create-table \
    --table-name account_connection_logs \
    --attribute-definitions \
        AttributeName=log_id,AttributeType=S \
        AttributeName=user_id,AttributeType=S \
        AttributeName=created_at,AttributeType=S \
    --key-schema \
        AttributeName=log_id,KeyType=HASH \
    --global-secondary-indexes \
        "[{\"IndexName\":\"user_id_created_at_index\",\"KeySchema\":[{\"AttributeName\":\"user_id\",\"KeyType\":\"HASH\"},{\"AttributeName\":\"created_at\",\"KeyType\":\"RANGE\"}],\"Projection\":{\"ProjectionType\":\"ALL\"},\"ProvisionedThroughput\":{\"ReadCapacityUnits\":5,\"WriteCapacityUnits\":5}}]" \
    --billing-mode PROVISIONED \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --endpoint-url http://dynamodb-local:8000 2>&1 || echo "Table may already exist"

# Verify table creation
echo "Verifying tables..."
aws dynamodb list-tables \
    --endpoint-url http://dynamodb-local:8000

echo "✓ DynamoDB initialization complete"
