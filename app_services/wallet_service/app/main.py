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
    title="Wallet Service",
    version="1.0.0",
    description="Digital wallet management service"
)

add_cors_middleware(app)


class Wallet(BaseModel):
    wallet_id: str
    user_id: str
    balance: float
    currency: str
    status: str
    created_at: datetime


class WalletTransaction(BaseModel):
    transaction_id: str
    wallet_id: str
    amount: float
    type: str  # deposit or withdrawal
    timestamp: datetime


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "wallet_service",
        "version": "1.0.0"
    }


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "Wallet Service",
        "message": "Digital wallet management API",
        "endpoints": ["/health", "/wallets/{wallet_id}", "/wallets/{wallet_id}/balance"]
    }


@app.get("/wallets/{wallet_id}", response_model=Wallet)
async def get_wallet(wallet_id: str):
    """Get wallet details (dummy data)"""
    return Wallet(
        wallet_id=wallet_id,
        user_id="user_123",
        balance=1000.00,
        currency="USD",
        status="active",
        created_at=datetime.now()
    )


@app.get("/wallets/{wallet_id}/balance")
async def get_balance(wallet_id: str):
    """Get wallet balance (dummy data)"""
    return {
        "wallet_id": wallet_id,
        "balance": 1000.00,
        "currency": "USD",
        "available_balance": 950.00,
        "pending_balance": 50.00
    }


@app.get("/wallets/{wallet_id}/transactions", response_model=List[WalletTransaction])
async def get_wallet_transactions(wallet_id: str):
    """Get wallet transaction history (dummy data)"""
    return [
        WalletTransaction(
            transaction_id="txn_001",
            wallet_id=wallet_id,
            amount=100.00,
            type="deposit",
            timestamp=datetime.now()
        )
    ]


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8006)