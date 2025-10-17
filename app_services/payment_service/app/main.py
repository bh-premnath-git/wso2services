from fastapi import FastAPI
from pydantic import BaseModel
from datetime import datetime
from typing import Optional
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
    title="Payment Service",
    version="1.0.0",
    description="Payment processing and orchestration service"
)

add_cors_middleware(app)


class PaymentRequest(BaseModel):
    amount: float
    currency: str
    from_account: str
    to_account: str
    description: Optional[str] = None


class PaymentResponse(BaseModel):
    payment_id: str
    status: str
    amount: float
    currency: str
    timestamp: datetime


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "payment_service",
        "version": "1.0.0"
    }


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "Payment Service",
        "message": "Payment processing and orchestration API",
        "endpoints": ["/health", "/payments", "/payments/{payment_id}"]
    }


@app.post("/payments", response_model=PaymentResponse)
async def create_payment(payment: PaymentRequest):
    """Process a payment (dummy implementation)"""
    return PaymentResponse(
        payment_id="pay_12345",
        status="completed",
        amount=payment.amount,
        currency=payment.currency,
        timestamp=datetime.now()
    )


@app.get("/payments/{payment_id}", response_model=PaymentResponse)
async def get_payment(payment_id: str):
    """Get payment details (dummy data)"""
    return PaymentResponse(
        payment_id=payment_id,
        status="completed",
        amount=100.00,
        currency="USD",
        timestamp=datetime.now()
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8003)