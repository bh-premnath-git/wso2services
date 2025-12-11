#!/bin/bash
set -e

echo "Initializing Marketplace Service database..."

# Wait for marketplace service to be ready
echo "Waiting for marketplace service to be healthy..."
for i in {1..60}; do
    if curl -s http://marketplace-service:8009/health > /dev/null 2>&1; then
        echo "✓ Marketplace service is ready"
        break
    fi
    echo "Waiting... ($i/60)"
    sleep 2
done

# Initialize database with tables and sample data
echo "Initializing database tables and sample data..."
docker exec -it marketplace-service python -m app.init_db

echo "✓ Marketplace service initialization complete"
