"""
Banking Service - Main Application
Handles bank account linking via Mastercard Open Finance
"""
# Import standard library modules BEFORE modifying sys.path
import asyncio
import logging
import os
import sys
from typing import Optional

import boto3
from botocore.config import Config as BotoConfig
from botocore.exceptions import ClientError
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# Add common module to path AFTER importing stdlib to avoid shadowing
common_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'common'))
if os.path.exists(common_path):
    sys.path.insert(0, common_path)
else:
    sys.path.insert(0, '/app/common')

from utils import get_ddb_table, get_redis, prepare_endpoint
from middleware import add_cors_middleware

from app.config import settings
from app.api.v1 import bank_accounts
from app.schemas import HealthResponse

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Create FastAPI application
app = FastAPI(
    title="Banking Service",
    version=settings.SERVICE_VERSION,
    description="Bank account linking and management via Mastercard Open Finance",
    docs_url="/docs",
    redoc_url="/redoc"
)

add_cors_middleware(app)

# Redis cache (shared factory)
_redis = get_redis(settings.REDIS_URL)
_CACHE_TTL = settings.CACHE_TTL_SECONDS

# DynamoDB tables - singleton pattern
_DDB_ENDPOINT = prepare_endpoint(settings.DYNAMODB_ENDPOINT)
_CUSTOMERS_TABLE: Optional[any] = None
_ACCOUNTS_TABLE: Optional[any] = None
_LOGS_TABLE: Optional[any] = None


def _get_customers_table():
    """Get or create customers table singleton"""
    global _CUSTOMERS_TABLE
    if _CUSTOMERS_TABLE is None:
        _CUSTOMERS_TABLE = get_ddb_table(
            region="ap-south-1",
            endpoint=_DDB_ENDPOINT,
            table_name="mastercard_customers"
        )
    return _CUSTOMERS_TABLE


def _get_accounts_table():
    """Get or create accounts table singleton"""
    global _ACCOUNTS_TABLE
    if _ACCOUNTS_TABLE is None:
        _ACCOUNTS_TABLE = get_ddb_table(
            region="ap-south-1",
            endpoint=_DDB_ENDPOINT,
            table_name="linked_bank_accounts"
        )
    return _ACCOUNTS_TABLE


def _get_logs_table():
    """Get or create logs table singleton"""
    global _LOGS_TABLE
    if _LOGS_TABLE is None:
        _LOGS_TABLE = get_ddb_table(
            region="ap-south-1",
            endpoint=_DDB_ENDPOINT,
            table_name="account_connection_logs"
        )
    return _LOGS_TABLE


def _validate_ddb_tables() -> None:
    """
    Validate DynamoDB tables exist using client-style approach (AWS best practice).
    Uses describe_table + waiter pattern before using resource.Table for writes.
    """
    if not _DDB_ENDPOINT:
        logger.warning("DynamoDB endpoint not configured, skipping table validation")
        return

    try:
        # Create client with same relaxed config as resource
        boto_config = BotoConfig(
            connect_timeout=10,
            read_timeout=30,
            retries={"max_attempts": 0, "mode": "standard"},
        )
        
        access_key = os.getenv("AWS_ACCESS_KEY_ID", "dummy_access_key")
        secret_key = os.getenv("AWS_SECRET_ACCESS_KEY", "dummy_secret_key")
        
        client = boto3.client(
            "dynamodb",
            region_name="ap-south-1",
            endpoint_url=_DDB_ENDPOINT,
            config=boto_config,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
        )

        # Validate customers table
        logger.info(f"Validating DynamoDB table 'mastercard_customers' at {_DDB_ENDPOINT}")
        response = client.describe_table(TableName="mastercard_customers")
        table_status = response["Table"]["TableStatus"]
        logger.info(f"DynamoDB table 'mastercard_customers' found with status: {table_status}")

        if table_status == "CREATING":
            logger.info("Waiting for table 'mastercard_customers' to become ACTIVE...")
            waiter = client.get_waiter("table_exists")
            waiter.wait(TableName="mastercard_customers")
            logger.info("Table 'mastercard_customers' is now ACTIVE")
        elif table_status == "ACTIVE":
            logger.info("Table 'mastercard_customers' is ACTIVE and ready")

        # Validate accounts table
        logger.info(f"Validating DynamoDB table 'linked_bank_accounts' at {_DDB_ENDPOINT}")
        response = client.describe_table(TableName="linked_bank_accounts")
        table_status = response["Table"]["TableStatus"]
        logger.info(f"DynamoDB table 'linked_bank_accounts' found with status: {table_status}")

        if table_status == "CREATING":
            logger.info("Waiting for table 'linked_bank_accounts' to become ACTIVE...")
            waiter = client.get_waiter("table_exists")
            waiter.wait(TableName="linked_bank_accounts")
            logger.info("Table 'linked_bank_accounts' is now ACTIVE")
        elif table_status == "ACTIVE":
            logger.info("Table 'linked_bank_accounts' is ACTIVE and ready")

        # Validate logs table
        logger.info(f"Validating DynamoDB table 'account_connection_logs' at {_DDB_ENDPOINT}")
        response = client.describe_table(TableName="account_connection_logs")
        table_status = response["Table"]["TableStatus"]
        logger.info(f"DynamoDB table 'account_connection_logs' found with status: {table_status}")

        if table_status == "CREATING":
            logger.info("Waiting for table 'account_connection_logs' to become ACTIVE...")
            waiter = client.get_waiter("table_exists")
            waiter.wait(TableName="account_connection_logs")
            logger.info("Table 'account_connection_logs' is now ACTIVE")
        elif table_status == "ACTIVE":
            logger.info("Table 'account_connection_logs' is ACTIVE and ready")

    except ClientError as e:
        if e.response["Error"]["Code"] == "ResourceNotFoundException":
            logger.error("DynamoDB tables do not exist. Please run initialization script.")
            logger.error("Run: docker compose run --rm dynamodb-init")
        else:
            logger.error(f"DynamoDB table validation error: {e}")
    except Exception as e:
        logger.error(f"DynamoDB validation failed: {e}")


@app.on_event("startup")
async def startup_event():
    """Initialize application on startup"""
    logger.info(f"Starting {settings.SERVICE_NAME} v{settings.SERVICE_VERSION}")
    logger.info(f"Mastercard API: {settings.MASTERCARD_BASE_URL}")
    logger.info(f"DynamoDB Endpoint: {_DDB_ENDPOINT}")
    
    # Validate DynamoDB tables asynchronously
    await asyncio.to_thread(_validate_ddb_tables)


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    logger.info(f"Shutting down {settings.SERVICE_NAME}")


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """
    Health check endpoint
    
    Used by Docker health checks and monitoring systems
    """
    # Test DynamoDB connection
    database_status = "connected"
    try:
        customers_table = _get_customers_table()
        # Simple table scan to verify connection
        customers_table.scan(Limit=1)
    except Exception as e:
        logger.error(f"DynamoDB health check failed: {e}")
        database_status = "disconnected"
    
    # Test Redis connection
    cache_status = "connected"
    try:
        _redis.ping()
    except Exception as e:
        logger.error(f"Redis health check failed: {e}")
        cache_status = "disconnected"
    
    return HealthResponse(
        status="healthy",
        service=settings.SERVICE_NAME,
        version=settings.SERVICE_VERSION,
        database=database_status,
        cache=cache_status
    )


@app.get("/")
async def root():
    """
    Root endpoint with service information
    """
    return {
        "service": "Banking Service",
        "version": settings.SERVICE_VERSION,
        "description": "Bank account linking and management",
        "documentation": "/docs",
        "health": "/health",
        "endpoints": {
            "connect": "POST /api/v1/{user_id}/bank-accounts/connect",
            "callback": "GET /api/v1/{user_id}/bank-accounts/callback",
            "list": "GET /api/v1/{user_id}/bank-accounts",
            "get": "GET /api/v1/{user_id}/bank-accounts/{account_id}",
            "refresh": "POST /api/v1/{user_id}/bank-accounts/{account_id}/refresh",
            "unlink": "DELETE /api/v1/{user_id}/bank-accounts/{account_id}",
            "set_primary": "POST /api/v1/{user_id}/bank-accounts/{account_id}/set-primary"
        }
    }


# Include API routers
app.include_router(
    bank_accounts.router,
    prefix=f"{settings.API_V1_PREFIX}",
    tags=["bank-accounts"]
)

# Export singletons for use in other modules
__all__ = [
    "app",
    "_get_customers_table",
    "_get_accounts_table",
    "_get_logs_table",
    "_redis",
    "_CACHE_TTL"
]


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=settings.SERVICE_PORT,
        reload=False,
        log_level="info"
    )
