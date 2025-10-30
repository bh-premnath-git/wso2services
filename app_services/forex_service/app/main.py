import asyncio
import json
import logging
import os
import sys
from datetime import datetime
from decimal import Decimal
from typing import Any, Dict, Optional

import boto3
import httpx
from botocore.config import Config as BotoConfig
from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

# Add common module to path BEFORE importing shared utils/config
common_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'common'))
if os.path.exists(common_path):
    sys.path.insert(0, common_path)
else:
    sys.path.insert(0, '/app/common')

from utils import get_ddb_table, get_redis, now_iso, prepare_endpoint

from middleware import add_cors_middleware
from config import config

# Configure logging
logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

app = FastAPI(
    title="Forex Service",
    version="1.0.0",
    description="Currency exchange rate management and conversion"
)

add_cors_middleware(app)


class ExchangeRate(BaseModel):
    from_currency: str
    to_currency: str
    rate: float
    timestamp: datetime


def _to_native(value: Any) -> Any:
    if isinstance(value, Decimal):
        return int(value) if value % 1 == 0 else float(value)
    if isinstance(value, dict):
        return {k: _to_native(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_to_native(v) for v in value]
    return value


# Redis cache (shared factory)
_redis = get_redis(config.FOREX_REDIS_URL)
_TTL = config.CACHE_TTL_SECONDS


_DDB_ENDPOINT = prepare_endpoint(config.DDB_ENDPOINT)
# DynamoDB table - will be created on first write operation
_DDB_TABLE = get_ddb_table(config.AWS_REGION, _DDB_ENDPOINT, config.DDB_TABLE)


def _validate_ddb_table() -> None:
    """
    Validate DynamoDB table exists using client-style approach (AWS best practice).
    Uses describe_table + waiter pattern before using resource.Table for writes.
    """
    if not _DDB_ENDPOINT:
        log.warning("DynamoDB endpoint not configured, skipping table validation")
        return

    try:
        # Create client with same relaxed config as resource
        boto_config = BotoConfig(
            connect_timeout=10,
            read_timeout=30,
            retries={"max_attempts": 0, "mode": "standard"},
        )

        client = boto3.client(
            "dynamodb",
            region_name=config.AWS_REGION,
            endpoint_url=_DDB_ENDPOINT,
            aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID", "local"),
            aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY", "local"),
            config=boto_config,
        )

        # Describe table to check existence
        log.info(f"Validating DynamoDB table '{config.DDB_TABLE}' at {_DDB_ENDPOINT}")
        response = client.describe_table(TableName=config.DDB_TABLE)
        table_status = response["Table"]["TableStatus"]
        log.info(f"DynamoDB table '{config.DDB_TABLE}' found with status: {table_status}")

        # Wait for table to be active
        if table_status != "ACTIVE":
            log.info(f"Waiting for table '{config.DDB_TABLE}' to become ACTIVE...")
            waiter = client.get_waiter("table_exists")
            waiter.wait(TableName=config.DDB_TABLE)
            log.info(f"Table '{config.DDB_TABLE}' is now ACTIVE")
        else:
            log.info(f"Table '{config.DDB_TABLE}' is ACTIVE and ready")

    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        if error_code == "ResourceNotFoundException":
            log.error(f"DynamoDB table '{config.DDB_TABLE}' does not exist. Please run initialization script.")
        else:
            log.error(f"DynamoDB table validation failed: {error_code} - {e}")
    except Exception as e:
        log.error(f"Unexpected error during DynamoDB table validation: {e}")


@app.on_event("startup")
async def startup_event():
    """FastAPI startup event - validate DynamoDB connection."""
    log.info("Starting Forex Service...")
    await asyncio.to_thread(_validate_ddb_table)
    log.info("Forex Service startup complete")


def _cache_key(from_currency: str, to_currency: str, start_time: Optional[str], end_time: Optional[str]) -> str:
    f = (start_time or "").strip()
    t = (end_time or "").strip()
    return f"fx:rate:{from_currency.upper()}-{to_currency.upper()}:{f}:{t}"


async def ddb_put_rate(pair: str, rate: float, source: str, manual: bool = False) -> Dict[str, Any]:
    """Write the latest rate for a currency pair to DynamoDB using boto3."""

    if not _DDB_TABLE:
        raise RuntimeError("DynamoDB table configuration is missing")

    def _update_sync() -> Dict[str, Any]:
        timestamp = now_iso()
        try:
            response = _DDB_TABLE.update_item(
                Key={"pair": pair},
                UpdateExpression=(
                    "SET #r = :r, updated_at = :ts, #s = :src, manual = :m, "
                    "version = if_not_exists(version, :zero) + :one"
                ),
                ExpressionAttributeNames={"#r": "rate", "#s": "source"},
                ExpressionAttributeValues={
                    ":r": Decimal(str(rate)),
                    ":ts": timestamp,
                    ":src": source,
                    ":m": bool(manual),
                    ":zero": Decimal("0"),
                    ":one": Decimal("1"),
                },
                ReturnValues="ALL_NEW",
            )
        except ClientError as exc:
            raise RuntimeError(f"DynamoDB update failed for {pair}: {exc}") from exc

        native = _to_native(response.get("Attributes", {}))

        return {
            "pair": native.get("pair", pair),
            "rate": native.get("rate", float(rate)),
            "updated_at": native.get("updated_at", timestamp),
            "source": native.get("source", source),
            "manual": bool(native.get("manual", manual)),
            "version": int(native.get("version", 1)),
        }

    return await asyncio.to_thread(_update_sync)


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "forex_service",
        "version": "1.0.0"
    }


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "Forex Service",
        "message": "Currency exchange rate API",
        "endpoints": ["/health", "/rates/{from_currency}/{to_currency}"]
    }


@app.get("/rates/{from_currency}/{to_currency}")
async def get_exchange_rate(from_currency: str, to_currency: str, start_time: Optional[str] = None, end_time: Optional[str] = None):
    # Cache hierarchy: Redis → DynamoDB → OANDA API
    
    # 1. Try Redis cache first (fastest)
    try:
        ckey = _cache_key(from_currency, to_currency, start_time, end_time)
        cached = _redis.get(ckey)
        if cached:
            data = json.loads(cached)
            return ExchangeRate(**data)
    except Exception:
        pass

    # 2. Try DynamoDB (if no time filters - only latest rates are in DDB)
    if not start_time and not end_time:
        try:
            pair = f"{from_currency.upper()}{to_currency.upper()}"
            response = await asyncio.to_thread(
                lambda: _DDB_TABLE.get_item(Key={"pair": pair})
            )
            if "Item" in response:
                item = _to_native(response["Item"])
                payload = ExchangeRate(
                    from_currency=from_currency.upper(),
                    to_currency=to_currency.upper(),
                    rate=float(item["rate"]),
                    timestamp=datetime.fromisoformat(item["updated_at"].replace("Z", "+00:00"))
                )
                # Warm Redis cache
                try:
                    _redis.setex(ckey, _TTL, payload.model_dump_json())
                except Exception:
                    pass
                return payload
        except Exception as e:
            log.warning(f"DynamoDB lookup failed for {pair}: {e}")

    # 3. Fallback to OANDA API or default
    if not config.OANDA_API_KEY:
        return ExchangeRate(
            from_currency=from_currency.upper(),
            to_currency=to_currency.upper(),
            rate=1.0,
            timestamp=datetime.now()
        )

    now_iso = datetime.utcnow().replace(microsecond=0).isoformat() + "Z"
    start_iso = start_time or now_iso
    end_iso = end_time or now_iso

    url = f"{config.OANDA_API_BASE}/rates/aggregated.json"
    params = {
        "base": from_currency.upper(),
        "quote": to_currency.upper(),
        "start_time": start_iso,
        "end_time": end_iso,
        "fields": "close",
    }
    headers = {
        "Accept": "application/json",
        "Authorization": f"Bearer {config.OANDA_API_KEY}",
    }

    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(url, params=params, headers=headers)
        if resp.status_code != 200:
            return ExchangeRate(
                from_currency=from_currency.upper(),
                to_currency=to_currency.upper(),
                rate=1.0,
                timestamp=datetime.now()
            )
        data = resp.json()
        quotes = data.get("quotes", [])
        if not quotes:
            return ExchangeRate(
                from_currency=from_currency.upper(),
                to_currency=to_currency.upper(),
                rate=1.0,
                timestamp=datetime.now()
            )
        q = quotes[0]
        midpoint = q.get("close_midpoint") or q.get("close_bid") or q.get("close_ask")
        try:
            rate_val = float(midpoint)
        except Exception:
            rate_val = 1.0
        ts = q.get("end_time") or q.get("start_time") or now_iso
        try:
            ts_dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        except Exception:
            ts_dt = datetime.utcnow()
        payload = ExchangeRate(
            from_currency=from_currency.upper(),
            to_currency=to_currency.upper(),
            rate=rate_val,
            timestamp=ts_dt
        )

        # Warm cache
        try:
            _redis.setex(ckey, _TTL, payload.model_dump_json())
        except Exception:
            pass

        return payload


class RateWrite(BaseModel):
    rate: float = Field(gt=0)
    note: Optional[str] = None


@app.put("/rates/{pair}")
async def write_rate(pair: str, body: RateWrite):
    """
    Write-through: update DynamoDB and refresh Redis for the base GET key without time filters.
    """
    try:
        pair_up = pair.upper()
        item = await ddb_put_rate(pair_up, rate=body.rate, source="user", manual=True)
        # Build a minimal payload for cache consumers of GET without time filters
        base, quote = pair_up[:3], pair_up[3:]
        updated_at = item.get("updated_at")
        if isinstance(updated_at, str):
            try:
                ts_dt = datetime.fromisoformat(updated_at.replace("Z", "+00:00"))
            except ValueError:
                ts_dt = datetime.utcnow()
        elif isinstance(updated_at, datetime):
            ts_dt = updated_at
        else:
            ts_dt = datetime.utcnow()
        payload = ExchangeRate(
            from_currency=base,
            to_currency=quote,
            rate=float(item["rate"]),
            timestamp=ts_dt,
        )
        try:
            _redis.setex(_cache_key(base, quote, None, None), _TTL, payload.model_dump_json())
        except Exception:
            pass
        return payload
    except Exception as e:
        # Invalidate cache on error to avoid stale values
        try:
            base, quote = pair.upper()[:3], pair.upper()[3:]
            _redis.delete(_cache_key(base, quote, None, None))
        except Exception:
            pass
        raise HTTPException(status_code=500, detail=f"Failed to write rate for {pair}: {e}")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
