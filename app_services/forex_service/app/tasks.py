from typing import List, Dict
import os
import sys
import json
import httpx
from celery.utils.log import get_task_logger

# Add common module to path
common_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'common'))
if os.path.exists(common_path):
    sys.path.insert(0, common_path)
else:
    sys.path.insert(0, '/app/common')

from config import config
from .celery_app import celery_app

import redis
from datetime import datetime, timezone
from decimal import Decimal

log = get_task_logger(__name__)

# Redis (cache DB 1)
r_cache = redis.Redis.from_url(config.FOREX_REDIS_URL, decode_responses=True)
TTL = config.CACHE_TTL_SECONDS


def _pairs() -> List[str]:
    return [p.strip().upper() for p in config.PAIRS_CSV.split(",") if p.strip()]


def _now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _cache_key(pair: str) -> str:
    base, quote = pair[:3], pair[3:]
    return f"fx:rate:{base}-{quote}::"  # intentionally matches GET without time filters


async def _fetch_oanda(client: httpx.AsyncClient, base: str, quote: str) -> float:
    # Your existing API base is used for aggregated quotes elsewhere; for periodic refresh, use a simple endpoint
    url = f"{config.OANDA_API_BASE}/rates/aggregated.json"
    now_iso = _now_iso() + "Z"
    params = {
        "base": base,
        "quote": quote,
        "start_time": now_iso,
        "end_time": now_iso,
        "fields": "close",
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
    midpoint = q.get("close_midpoint") or q.get("close_bid") or q.get("close_ask")
    return float(midpoint)


def _ddb_put(pair: str, rate: float) -> Dict:
    """Write rate to DynamoDB using direct HTTP (bypasses boto3)"""
    endpoint = (config.DDB_ENDPOINT or "http://dynamodb-local:8000").strip()
    if "://" not in endpoint:
        endpoint = f"http://{endpoint}"
    
    payload = {
        "TableName": config.DDB_TABLE,
        "Key": {"pair": {"S": pair}},
        "UpdateExpression": "SET #r = :r, updated_at = :ts, #s = :src, manual = :m, version = if_not_exists(version, :zero) + :one",
        "ExpressionAttributeNames": {"#r": "rate", "#s": "source"},
        "ExpressionAttributeValues": {
            ":r": {"N": str(Decimal(str(rate)))},
            ":ts": {"S": _now_iso()},
            ":src": {"S": "provider"},
            ":m": {"BOOL": False},
            ":zero": {"N": "0"},
            ":one": {"N": "1"}
        },
        "ReturnValues": "ALL_NEW"
    }
    
    headers = {
        "X-Amz-Target": "DynamoDB_20120810.UpdateItem",
        "Content-Type": "application/x-amz-json-1.0",
    }
    
    # Synchronous httpx call (Celery task context)
    with httpx.Client(timeout=5.0) as client:
        resp = client.post(
            endpoint.rstrip('/') + '/',
            json=payload,
            headers=headers,
        )
    resp.raise_for_status()
    data = resp.json()
    attrs = data["Attributes"]
    
    # Convert DynamoDB JSON back to plain dict
    item = {
        "pair": attrs["pair"]["S"],
        "rate": float(attrs["rate"]["N"]),
        "updated_at": attrs["updated_at"]["S"],
        "source": attrs["source"]["S"],
        "manual": attrs["manual"]["BOOL"],
        "version": int(attrs["version"]["N"]),
    }
    return item


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
