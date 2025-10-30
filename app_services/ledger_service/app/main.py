from fastapi import FastAPI
from pydantic import BaseModel
from datetime import datetime
from typing import List
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
    title="Ledger Service",
    version="1.0.0",
    description="Transaction ledger and accounting service"
)

add_cors_middleware(app)


class Transaction(BaseModel):
    transaction_id: str
    account_id: str
    amount: float
    currency: str
    type: str  # debit or credit
    timestamp: datetime


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "ledger_service",
        "version": "1.0.0"
    }


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "Ledger Service",
        "message": "Transaction ledger and accounting API",
        "endpoints": ["/health", "/transactions/{account_id}"]
    }


@app.get("/transactions/{account_id}", response_model=List[Transaction])
async def get_transactions(account_id: str):
    """Get transaction history for an account (dummy data)"""
    return [
        Transaction(
            transaction_id="txn_001",
            account_id=account_id,
            amount=100.00,
            currency="USD",
            type="credit",
            timestamp=datetime.now()
        )
    ]


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8002)