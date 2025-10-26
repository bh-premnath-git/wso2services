import redis
import boto3
import aioboto3
from typing import Optional, AsyncIterator
from datetime import datetime, timezone
from urllib.parse import urlparse
from botocore.config import Config as BotoConfig
from contextlib import asynccontextmanager
import os


def _append_no_proxy(host: Optional[str]):
    """Ensure local hosts bypass corporate HTTP proxies."""

    if not host:
        return

    # Normalize host component (strip surrounding whitespace)
    host = host.strip()
    if not host:
        return

    for key in ("NO_PROXY", "no_proxy"):
        current = os.environ.get(key, "")
        entries = [value.strip() for value in current.split(",") if value.strip()]
        if host in entries:
            continue
        entries.append(host)
        os.environ[key] = ",".join(entries)


def get_redis(url: str) -> "redis.Redis":
    """Create a Redis client from a URL (no side effects)."""
    return redis.Redis.from_url(url, decode_responses=True)


def _with_scheme(url: Optional[str]) -> Optional[str]:
    """Ensure URL has a scheme (http:// or https://)"""
    if not url:
        return url
    url = url.strip()
    return url if "://" in url else f"http://{url}"


def _credentials() -> dict[str, str]:
    """Return explicit AWS credentials to avoid metadata lookups."""

    return {
        "aws_access_key_id": os.getenv("AWS_ACCESS_KEY_ID", "local"),
        "aws_secret_access_key": os.getenv("AWS_SECRET_ACCESS_KEY", "local"),
    }


def _boto_session(region: str) -> boto3.Session:
    """Create boto3 session with explicit creds to avoid metadata lookups"""
    return boto3.Session(region_name=region, **_credentials())


def _aioboto_session(region: str) -> aioboto3.Session:
    """Create aioboto3 session with explicit credentials."""

    return aioboto3.Session(region_name=region, **_credentials())


def get_ddb(region: str, endpoint: Optional[str] = None):
    """Create a boto3 DynamoDB resource with short timeouts (no side effects)."""
    endpoint = _with_scheme(endpoint)
    parsed = urlparse(endpoint) if endpoint else None
    if parsed:
        _append_no_proxy(parsed.hostname)
        # Also add host:port so urllib3 fully bypasses proxies when ports are used
        if parsed.port:
            _append_no_proxy(f"{parsed.hostname}:{parsed.port}")
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


@asynccontextmanager
async def get_async_ddb_table(
    region: str, endpoint: Optional[str], table_name: str
) -> AsyncIterator["aioboto3.resource.Table"]:
    """Async context manager yielding an aioboto3 DynamoDB table."""

    endpoint = _with_scheme(endpoint)
    parsed = urlparse(endpoint) if endpoint else None
    if parsed:
        _append_no_proxy(parsed.hostname)
        if parsed.port:
            _append_no_proxy(f"{parsed.hostname}:{parsed.port}")

    session = _aioboto_session(region)
    resource = session.resource(
        "dynamodb",
        endpoint_url=endpoint,
        config=BotoConfig(
            connect_timeout=2,
            read_timeout=5,
            retries={"max_attempts": 2, "mode": "standard"},
        ),
    )

    async with resource as dynamodb:
        table = dynamodb.Table(table_name)
        yield table


def now_iso() -> str:
    """UTC ISO8601 timestamp with seconds precision."""
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()
