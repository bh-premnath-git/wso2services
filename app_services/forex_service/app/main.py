from fastapi import FastAPI
from pydantic import BaseModel
from datetime import datetime
import os
import sys

# Add common module to path
common_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'common'))
if os.path.exists(common_path):
    sys.path.insert(0, common_path)
else:
    sys.path.insert(0, '/app/common')

from middleware import add_cors_middleware

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
async def get_exchange_rate(from_currency: str, to_currency: str):
    """Get exchange rate between two currencies (dummy data)"""
    return ExchangeRate(
        from_currency=from_currency.upper(),
        to_currency=to_currency.upper(),
        rate=1.23,  # Dummy rate
        timestamp=datetime.now()
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)