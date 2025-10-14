from fastapi import FastAPI
from pydantic import BaseModel, EmailStr
from datetime import datetime
from typing import Optional

app = FastAPI(
    title="Profile Service",
    version="1.0.0",
    description="User profile and KYC management service"
)


class UserProfile(BaseModel):
    user_id: str
    email: EmailStr
    full_name: str
    phone: Optional[str] = None
    kyc_status: str
    created_at: datetime


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "profile_service",
        "version": "1.0.0"
    }


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "Profile Service",
        "message": "User profile and KYC management API",
        "endpoints": ["/health", "/profiles/{user_id}", "/profiles/{user_id}/kyc"]
    }


@app.get("/profiles/{user_id}", response_model=UserProfile)
async def get_profile(user_id: str):
    """Get user profile (dummy data)"""
    return UserProfile(
        user_id=user_id,
        email="user@example.com",
        full_name="John Doe",
        phone="+1234567890",
        kyc_status="verified",
        created_at=datetime.now()
    )


@app.get("/profiles/{user_id}/kyc")
async def get_kyc_status(user_id: str):
    """Get KYC status for user (dummy data)"""
    return {
        "user_id": user_id,
        "kyc_status": "verified",
        "verification_date": datetime.now().isoformat(),
        "documents_submitted": ["passport", "proof_of_address"]
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8004)