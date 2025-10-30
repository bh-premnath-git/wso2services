from fastapi import FastAPI
from pydantic import BaseModel
from typing import List, Dict, Any
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
    title="Rule Engine Service",
    version="1.0.0",
    description="Business rules and compliance engine"
)

add_cors_middleware(app)


class RuleRequest(BaseModel):
    transaction_amount: float
    transaction_type: str
    user_id: str
    country: str


class RuleResponse(BaseModel):
    allowed: bool
    rules_applied: List[str]
    risk_score: float
    message: str


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "rule_engine_service",
        "version": "1.0.0"
    }


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "Rule Engine Service",
        "message": "Business rules and compliance API",
        "endpoints": ["/health", "/evaluate", "/rules"]
    }


@app.post("/evaluate", response_model=RuleResponse)
async def evaluate_rules(request: RuleRequest):
    """Evaluate business rules for a transaction (dummy logic)"""
    # Dummy rule evaluation
    allowed = request.transaction_amount <= 10000
    risk_score = 0.2 if allowed else 0.8
    
    return RuleResponse(
        allowed=allowed,
        rules_applied=["amount_limit", "country_check", "kyc_verification"],
        risk_score=risk_score,
        message="Transaction approved" if allowed else "Amount exceeds limit"
    )


@app.get("/rules")
async def list_rules():
    """List all active rules (dummy data)"""
    return {
        "rules": [
            {"id": "rule_001", "name": "Amount Limit", "type": "transaction", "active": True},
            {"id": "rule_002", "name": "Country Restrictions", "type": "compliance", "active": True},
            {"id": "rule_003", "name": "KYC Verification", "type": "compliance", "active": True}
        ]
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8005)