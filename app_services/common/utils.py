import os
from datetime import datetime, timezone
from typing import Optional
from urllib.parse import urlparse

import boto3
from botocore.config import Config as BotoConfig
import redis


def ensure_no_proxy(host: Optional[str]) -> None:
    """Ensure local hosts bypass corporate HTTP proxies."""

    if not host:
        return

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


def prepare_endpoint(url: Optional[str]) -> Optional[str]:
    """Normalize a DynamoDB endpoint URL and ensure proxy bypass for the host."""

    if not url:
        return None

    endpoint = url.strip()
    if not endpoint:
        return None

    if "://" not in endpoint:
        endpoint = f"http://{endpoint}"

    parsed = urlparse(endpoint)
    if parsed.hostname:
        ensure_no_proxy(parsed.hostname)
        if parsed.port:
            ensure_no_proxy(f"{parsed.hostname}:{parsed.port}")

    return endpoint


def _credential_kwargs() -> dict[str, str]:
    """Return explicit AWS credential keyword arguments for boto3."""

    access_key = os.getenv("AWS_ACCESS_KEY_ID", "dummy_access_key")
    secret_key = os.getenv("AWS_SECRET_ACCESS_KEY", "dummy_secret_key")
    if not access_key or not secret_key:
        raise RuntimeError("AWS credentials must be provided for DynamoDB access")

    creds: dict[str, str] = {
        "aws_access_key_id": access_key,
        "aws_secret_access_key": secret_key,
    }

    session_token = os.getenv("AWS_SESSION_TOKEN")
    if session_token:
        creds["aws_session_token"] = session_token

    return creds


def get_ddb_table(region: str, endpoint: Optional[str], table_name: str):
    """Return a DynamoDB table resource configured with relaxed timeouts for DynamoDB Local."""

    kwargs = _credential_kwargs()
    resource = boto3.resource(
        "dynamodb",
        region_name=region,
        endpoint_url=endpoint,
        config=BotoConfig(
            connect_timeout=10,
            read_timeout=30,
            retries={"max_attempts": 0, "mode": "standard"},
        ),
        **kwargs,
    )
    return resource.Table(table_name)


def get_redis(url: str) -> "redis.Redis":
    """Create a Redis client from a URL (no side effects)."""
    return redis.Redis.from_url(url, decode_responses=True)


def now_iso() -> str:
    """UTC ISO8601 timestamp with seconds precision."""
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()
