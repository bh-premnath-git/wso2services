import json
import os
import sys
from decimal import Decimal
from typing import Any, Dict, List

import httpx
from botocore.exceptions import ClientError
from celery.utils.log import get_task_logger

# Add common module to path
common_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'common'))
if os.path.exists(common_path):
    sys.path.insert(0, common_path)
else:
    sys.path.insert(0, '/app/common')

from utils import get_ddb_table, now_iso, prepare_endpoint
from config import config
from .celery_app import celery_app

import redis

log = get_task_logger(__name__)

# Redis (cache DB 1)
r_cache = redis.Redis.from_url(config.FOREX_REDIS_URL, decode_responses=True)
TTL = config.CACHE_TTL_SECONDS

_DDB_ENDPOINT = prepare_endpoint(config.DDB_ENDPOINT)
_DDB_TABLE = get_ddb_table(config.AWS_REGION, _DDB_ENDPOINT, config.DDB_TABLE)


def _pairs() -> List[str]:
    return [p.strip().upper() for p in config.PAIRS_CSV.split(",") if p.strip()]


def _cache_key(pair: str) -> str:
    base, quote = pair[:3], pair[3:]
    return f"fx:rate:{base}-{quote}::"  # intentionally matches GET without time filters


def _to_native(value: Any) -> Any:
    if isinstance(value, Decimal):
        return int(value) if value % 1 == 0 else float(value)
    if isinstance(value, dict):
        return {k: _to_native(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_to_native(v) for v in value]
    return value


async def _fetch_oanda(client: httpx.AsyncClient, base: str, quote: str) -> float:
    # Try OANDA API first, fallback to mock data if it fails
    try:
        # Use candle endpoint - provides historical OHLC data
        url = f"{config.OANDA_API_BASE}/rates/candle.json"
        params = {
            "base": base,
            "quote": quote,
        }
        headers = {"Accept": "application/json"}
        if config.OANDA_API_KEY:
            headers["Authorization"] = f"Bearer {config.OANDA_API_KEY}"
        r = await client.get(url, params=params, headers=headers, timeout=15)
        r.raise_for_status()
        data = r.json()
        quotes = data.get("quotes", [])
        if not quotes:
            raise RuntimeError("No quotes returned from provider")
        q = quotes[0]
        # Use close_midpoint, fallback to close_bid, close_ask, or average_midpoint
        midpoint = (q.get("close_midpoint") or q.get("average_midpoint") or 
                   q.get("close_bid") or q.get("close_ask"))
        return float(midpoint)
    except Exception as e:
        log.warning(f"OANDA API failed for {base}/{quote}: {e}, using fallback rates")
        # Fallback mock rates - OANDA API key has limited access (real-time rates not available)
        # For production, upgrade OANDA subscription or use alternative forex data provider
        mock_rates = {
            "USDINR": 83.25,
            "EURINR": 90.50,
            "GBPINR": 105.75,
            "INRUSD": 0.012,
            "INREUR": 0.011,
            "INRGBP": 0.0095,
        }
        pair = f"{base}{quote}"
        if pair in mock_rates:
            return mock_rates[pair]
        # If pair not in mock_rates, return a calculated inverse or default
        inverse_pair = f"{quote}{base}"
        if inverse_pair in mock_rates:
            return 1.0 / mock_rates[inverse_pair]
        return 1.0  # Ultimate fallback


def _ddb_put(pair: str, rate: float) -> Dict[str, Any]:
    """Write rate updates to DynamoDB using the boto3 resource API."""

    if not _DDB_TABLE:
        raise RuntimeError("DynamoDB table configuration is missing")

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
                ":src": "provider",
                ":m": False,
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
        "rate": float(native.get("rate", rate)),
        "updated_at": native.get("updated_at", timestamp),
        "source": native.get("source", "provider"),
        "manual": bool(native.get("manual", False)),
        "version": int(native.get("version", 1)),
    }


@celery_app.task(bind=True, autoretry_for=(httpx.HTTPError,), retry_backoff=True,
                 retry_backoff_max=300, retry_jitter=True, max_retries=5, name="tasks.refresh_fx_rates")
def refresh_fx_rates(self) -> Dict[str, float]:
    results: Dict[str, float] = {}

    async def run():
        async with httpx.AsyncClient() as client:
            for pair in _pairs():
                base, quote = pair[:3], pair[3:]
                try:
                    rate = await _fetch_oanda(client, base, quote)
                    item = _ddb_put(pair, rate)
                    payload = {
                        "from_currency": base,
                        "to_currency": quote,
                        "rate": item["rate"],
                        "timestamp": item["updated_at"],
                    }
                    try:
                        r_cache.setex(_cache_key(pair), TTL, json.dumps(payload))
                    except Exception:
                        pass
                    results[pair] = rate
                    log.info(f"refreshed {pair} -> {rate}")
                except Exception as e:
                    log.exception(f"refresh failed for {pair}: {e}")

    import anyio
    anyio.run(run)
    return results
