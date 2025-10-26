import redis
import boto3
from typing import Optional
from datetime import datetime, timezone
from urllib.parse import urlparse
from botocore.config import Config as BotoConfig
import os


def get_redis(url: str) -> "redis.Redis":
    """Create a Redis client from a URL (no side effects)."""
    return redis.Redis.from_url(url, decode_responses=True)


def _with_scheme(url: Optional[str]) -> Optional[str]:
    """Ensure URL has a scheme (http:// or https://)"""
    if not url:
        return url
    url = url.strip()
    return url if "://" in url else f"http://{url}"


def _boto_session(region: str) -> boto3.Session:
    """Create boto3 session with explicit creds to avoid metadata lookups"""
    return boto3.Session(
        aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID", "local"),
        aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY", "local"),
        region_name=region,
    )


def get_ddb(region: str, endpoint: Optional[str] = None):
    """Create a boto3 DynamoDB resource with short timeouts (no side effects)."""
    endpoint = _with_scheme(endpoint)
    sess = _boto_session(region)
    return sess.resource(
        "dynamodb",
        endpoint_url=endpoint,
        config=BotoConfig(
            connect_timeout=2,
            read_timeout=5,
            retries={"max_attempts": 1, "mode": "standard"}
        ),
    )


def get_ddb_table(region: str, endpoint: Optional[str], table_name: str):
    """Convenience to return a DynamoDB Table handle."""
    ddb = get_ddb(region, endpoint)
    return ddb.Table(table_name)


def now_iso() -> str:
    """UTC ISO8601 timestamp with seconds precision."""
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()
