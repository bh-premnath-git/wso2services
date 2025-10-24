from fastapi import FastAPI
from pydantic import BaseModel
from datetime import datetime
import os
import sys
import httpx

# Add common module to path
common_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'common'))
if os.path.exists(common_path):
    sys.path.insert(0, common_path)
else:
    sys.path.insert(0, '/app/common')

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
async def get_exchange_rate(from_currency: str, to_currency: str, start_time: str | None = None, end_time: str | None = None):
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
        return ExchangeRate(
            from_currency=from_currency.upper(),
            to_currency=to_currency.upper(),
            rate=rate_val,
            timestamp=ts_dt
        )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)