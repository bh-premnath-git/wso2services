from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from datetime import datetime, timezone
from decimal import Decimal
import os
import sys
import httpx
import json
from typing import Optional, Any, Dict

import aioboto3
from botocore.config import Config as BotoConfig
from urllib.parse import urlparse

# Add common module to path BEFORE importing shared utils/config
common_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'common'))
if os.path.exists(common_path):
    sys.path.insert(0, common_path)
else:
    sys.path.insert(0, '/app/common')

from utils import get_redis, now_iso

from middleware import add_cors_middleware
from config import config

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


def _append_no_proxy(host: Optional[str]) -> None:
    if not host:
        return
    host = host.strip()
    if not host:
        return
    for key in ("NO_PROXY", "no_proxy"):
        current = os.environ.get(key, "")
        entries = [value.strip() for value in current.split(",") if value.strip()]
        if host not in entries:
            entries.append(host)
            os.environ[key] = ",".join(entries)


def _prepare_endpoint(url: Optional[str]) -> Optional[str]:
    if not url:
        return None
    endpoint = url.strip()
    if not endpoint:
        return None
    if "://" not in endpoint:
        endpoint = f"http://{endpoint}"
    parsed = urlparse(endpoint)
    if parsed.hostname:
        _append_no_proxy(parsed.hostname)
        if parsed.port:
            _append_no_proxy(f"{parsed.hostname}:{parsed.port}")
    return endpoint


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


_DDB_ENDPOINT = _prepare_endpoint(config.DDB_ENDPOINT)
_DDB_SESSION = aioboto3.Session(
    aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID", "local"),
    aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY", "local"),
    region_name=config.AWS_REGION,
)
_DDB_CONFIG = BotoConfig(connect_timeout=2, read_timeout=5, retries={"max_attempts": 2, "mode": "standard"})


def _cache_key(from_currency: str, to_currency: str, start_time: Optional[str], end_time: Optional[str]) -> str:
    f = (start_time or "").strip()
    t = (end_time or "").strip()
    return f"fx:rate:{from_currency.upper()}-{to_currency.upper()}:{f}:{t}"


async def ddb_put_rate(pair: str, rate: float, source: str, manual: bool = False) -> Dict[str, Any]:
    """Write the latest rate for a currency pair to DynamoDB using aioboto3."""

    async with _DDB_SESSION.resource(
        "dynamodb",
        region_name=config.AWS_REGION,
        endpoint_url=_DDB_ENDPOINT,
        config=_DDB_CONFIG,
    ) as dynamodb:
        table = await dynamodb.Table(config.DDB_TABLE)
        response = await table.update_item(
            Key={"pair": pair},
            UpdateExpression=(
                "SET #r = :r, updated_at = :ts, #s = :src, manual = :m, "
                "version = if_not_exists(version, :zero) + :one"
            ),
            ExpressionAttributeNames={"#r": "rate", "#s": "source"},
            ExpressionAttributeValues={
                ":r": Decimal(str(rate)),
                ":ts": now_iso(),
                ":src": source,
                ":m": bool(manual),
                ":zero": Decimal("0"),
                ":one": Decimal("1"),
            },
            ReturnValues="ALL_NEW",
        )

    attrs = _to_native(response.get("Attributes", {}))

    item: Dict[str, Any] = {
        "pair": attrs.get("pair", pair),
        "rate": attrs.get("rate", float(rate)),
        "updated_at": attrs.get("updated_at", now_iso()),
        "source": attrs.get("source", source),
        "manual": bool(attrs.get("manual", manual)),
        "version": int(attrs.get("version", 1)),
    }
    return item


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
    # Cache-aside fast path
    try:
        ckey = _cache_key(from_currency, to_currency, start_time, end_time)
        cached = _redis.get(ckey)
        if cached:
            data = json.loads(cached)
            return ExchangeRate(**data)
    except Exception:
        pass

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
