from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, EmailStr
from datetime import datetime
from typing import Optional
import os
import sys

# Add common module to path (works in Docker container)
common_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'common'))
if os.path.exists(common_path):
    sys.path.insert(0, common_path)
else:
    # Fallback for Docker container where common is at /app/common
    sys.path.insert(0, '/app/common')

from auth.wso2_client import WSO2IdentityClient, WSO2ClientError
from auth.models import (
    UserRegistrationRequest,
    UserRegistrationResponse,
    TokenRequest,
    TokenResponse
)

app = FastAPI(
    title="Profile Service",
    version="1.0.0",
    description="User profile, registration, and authentication service"
)

# Initialize WSO2 client
wso2_client = WSO2IdentityClient(
    base_url=os.getenv("WSO2_IS_BASE", "https://wso2is:9443"),
    admin_user=os.getenv("ADMIN_USER", "admin"),
    admin_pass=os.getenv("ADMIN_PASS", "admin"),
    verify_ssl=False
)


class UserProfile(BaseModel):
    user_id: str
    email: EmailStr
    full_name: str
    phone: Optional[str] = None
    kyc_status: str
    created_at: datetime


@app.post("/register", response_model=UserRegistrationResponse)
async def register_user(user: UserRegistrationRequest):
    """
    Register new user with optional phone and address.
    
    **Required:** username, password, email, first_name, last_name
    
    **Optional:** phone, address (street, locality, region, postal_code, country)
    
    **JWT Claims:**
    - Scope `phone`: Adds phone_number to JWT
    - Scope `address`: Adds full address object to JWT
    - Scope `profile`: Adds name and email to JWT
    
    **Example with all fields:**
    ```json
    {
      "username": "johndoe",
      "password": "SecurePass123!",
      "email": "john@example.com",
      "first_name": "John",
      "last_name": "Doe",
      "phone": "+12025551234",
      "address": {
        "street": "123 Main St",
        "locality": "New York",
        "region": "NY",
        "postal_code": "10001",
        "country": "USA"
      }
    }
    ```
    """
    try:
        return await wso2_client.register_user(user)
    except WSO2ClientError as e:
        raise HTTPException(status_code=e.status_code, detail=e.detail)


@app.post("/auth/login", response_model=TokenResponse)
async def login(token_request: TokenRequest):
    """
    Authenticate user and get JWT tokens with claims.
    
    **Scopes control which claims appear in JWT:**
    - `openid`: Required for OIDC
    - `profile`: Adds given_name, family_name, email
    - `email`: Adds email
    - `phone`: Adds phone_number (if user has phone)
    - `address`: Adds address object (if user has address)
    
    **Example request:**
    ```json
    {
      "username": "johndoe",
      "password": "SecurePass123!",
      "client_id": "YOUR_CLIENT_ID",
      "client_secret": "YOUR_CLIENT_SECRET",
      "scopes": ["openid", "profile", "phone", "address"]
    }
    ```
    
    **Response includes decoded JWT claims showing:**
    - User identity (sub, email)
    - Profile info (given_name, family_name)
    - Phone number (if phone scope requested and user has phone)
    - Address object (if address scope requested and user has address)
    """
    try:
        return await wso2_client.authenticate(token_request)
    except WSO2ClientError as e:
        raise HTTPException(status_code=e.status_code, detail=e.detail)


@app.get("/auth/userinfo")
async def get_userinfo(access_token: str):
    """
    Get user info using access token.
    Returns claims based on scopes used during authentication.
    """
    try:
        return await wso2_client.get_userinfo(access_token)
    except WSO2ClientError as e:
        raise HTTPException(status_code=e.status_code, detail=e.detail)


@app.post("/auth/refresh")
async def refresh_access_token(
    refresh_token: str,
    client_id: str,
    client_secret: str
):
    """Refresh access token using refresh token"""
    try:
        return await wso2_client.refresh_token(
            refresh_token, client_id, client_secret
        )
    except WSO2ClientError as e:
        raise HTTPException(status_code=e.status_code, detail=e.detail)


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
    """API information"""
    return {
        "service": "Profile Service",
        "version": "1.0.0",
        "features": [
            "User registration with optional phone/address",
            "JWT authentication with custom claims",
            "Token refresh",
            "User info endpoint",
            "User profile management",
            "KYC status tracking"
        ],
        "endpoints": {
            "register": "POST /register",
            "login": "POST /auth/login",
            "userinfo": "GET /auth/userinfo",
            "refresh": "POST /auth/refresh",
            "profile": "GET /profiles/{user_id}",
            "kyc": "GET /profiles/{user_id}/kyc",
            "health": "GET /health"
        }
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