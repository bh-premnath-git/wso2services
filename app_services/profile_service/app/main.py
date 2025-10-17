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
    TokenResponse,
    PasswordResetRequest,
    PasswordResetResponse,
    UserProfileUpdateRequest,
    UserProfileUpdateResponse
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
    
    **Request body:**
    ```json
    {
      "username": "johndoe",
      "password": "SecurePass123!",
      "client_id": "your_client_id",
      "client_secret": "your_client_secret",
      "scopes": ["openid", "profile", "email"]
    }
    ```
    
    **Scopes:**
    - `openid` - Required for OIDC
    - `profile` - Get name, username
    - `email` - Get email address
    - `phone` - Get phone number (if provided during registration)
    - `address` - Get address details (if provided during registration)
    
    **Example:**
    ```bash
    curl -X POST http://localhost:8004/auth/login \\
      -H "Content-Type: application/json" \\
      -d '{
        "username": "johndoe",
        "password": "SecurePass123!",
        "client_id": "your_client_id",
        "client_secret": "your_client_secret",
        "scopes": ["openid", "profile", "email", "phone", "address"]
      }'
    ```
    
    **Returns:**
    - `access_token` - Use this to call protected APIs
    - `id_token` - Contains user identity claims (JWT)
    - `refresh_token` - Use to get new access tokens
    - `decoded_claims` - Enhanced with full user info from SCIM
    
    **Note:** ID tokens from DCR apps have limited claims. Full user info
    is retrieved from SCIM and included in `decoded_claims`.
    """
    try:
        token_response = await wso2_client.authenticate(token_request)
        
        # Enhance decoded_claims with full user info from SCIM
        if token_response.access_token:
            try:
                userinfo = await wso2_client.get_userinfo(token_response.access_token)
                if token_response.decoded_claims:
                    token_response.decoded_claims["userinfo"] = userinfo
            except:
                pass  # If userinfo fails, still return the tokens
        
        return token_response
    except WSO2ClientError as e:
        raise HTTPException(status_code=e.status_code, detail=e.detail)


@app.get("/auth/userinfo")
async def get_userinfo(access_token: str):
    """
    Get user info using access token from OAuth2 /userinfo endpoint.
    
    **Note:** Due to WSO2 IS DCR limitations, this only returns 'sub' claim.
    Use `/auth/profile/{username}` for full user data.
    """
    try:
        return await wso2_client.get_userinfo(access_token)
    except WSO2ClientError as e:
        raise HTTPException(status_code=e.status_code, detail=e.detail)


@app.get("/auth/profile/{username}")
async def get_user_profile(username: str):
    """
    Get full user profile from SCIM2 API.
    
    **Returns complete user information:**
    - username
    - email
    - given_name (first name)
    - family_name (last name) 
    - full_name
    - phone (if available)
    - address (if available)
    - active status
    - roles
    
    **Example:**
    ```bash
    curl http://localhost:8004/auth/profile/ops_user
    ```
    
    This is the recommended way to get full user data when using
    OAuth apps created via DCR (Dynamic Client Registration).
    """
    import httpx
    
    try:
        async with httpx.AsyncClient(verify=False) as client:
            # Query SCIM for user
            response = await client.get(
                f"https://wso2is:9443/scim2/Users",
                params={"filter": f"userName eq {username}"},
                headers={
                    "Authorization": wso2_client.auth_header,
                    "Accept": "application/scim+json"
                },
                timeout=30.0
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get("totalResults", 0) > 0:
                    user = data["Resources"][0]
                    
                    # Extract user profile
                    emails = user.get("emails", [])
                    phone_numbers = user.get("phoneNumbers", [])
                    
                    profile = {
                        "username": user.get("userName"),
                        "id": user.get("id"),
                        "active": user.get("active", False),
                        "email": emails[0] if emails else None,
                        "given_name": user.get("name", {}).get("givenName"),
                        "family_name": user.get("name", {}).get("familyName"),
                        "full_name": user.get("name", {}).get("formatted"),
                        "phone": phone_numbers[0] if phone_numbers else None,
                        "roles": [r.get("display") for r in user.get("roles", [])],
                    }
                    
                    return profile
                else:
                    raise HTTPException(status_code=404, detail=f"User '{username}' not found")
            else:
                raise HTTPException(status_code=response.status_code, detail="Failed to fetch user profile")
                
    except httpx.RequestError as e:
        raise HTTPException(status_code=503, detail=f"Failed to connect to WSO2 IS: {str(e)}")


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


@app.post("/auth/reset-password", response_model=PasswordResetResponse)
async def reset_password(reset_request: PasswordResetRequest):
    """
    Reset user password.
    
    **Request body:**
    ```json
    {
      "username": "johndoe",
      "new_password": "NewSecurePass123!"
    }
    ```
    
    **Password requirements:**
    - Minimum 8 characters
    - At least one uppercase letter
    - At least one lowercase letter
    - At least one digit
    - At least one special character
    
    **Example:**
    ```bash
    curl -X POST http://localhost:8004/auth/reset-password \\
      -H "Content-Type: application/json" \\
      -d '{"username": "johndoe", "new_password": "NewPass123!"}'
    ```
    """
    try:
        return await wso2_client.reset_password(reset_request)
    except WSO2ClientError as e:
        raise HTTPException(status_code=e.status_code, detail=e.detail)


@app.patch("/auth/profile/{username}", response_model=UserProfileUpdateResponse)
async def update_user_profile(username: str, update_request: UserProfileUpdateRequest):
    """
    Update user profile information.
    
    **All fields are optional** - only provide fields you want to update.
    
    **Request body:**
    ```json
    {
      "email": "newemail@example.com",
      "first_name": "John",
      "last_name": "Doe",
      "phone": "+12025551234",
      "address": {
        "street": "123 Main St",
        "locality": "Springfield",
        "region": "IL",
        "postal_code": "62701",
        "country": "USA"
      }
    }
    ```
    
    **Example - Update only phone:**
    ```bash
    curl -X PATCH http://localhost:8004/auth/profile/ops_user \\
      -H "Content-Type: application/json" \\
      -d '{"phone": "+12025551234"}'
    ```
    
    **Example - Update name and email:**
    ```bash
    curl -X PATCH http://localhost:8004/auth/profile/ops_user \\
      -H "Content-Type: application/json" \\
      -d '{
        "first_name": "John",
        "last_name": "Smith",
        "email": "john.smith@example.com"
      }'
    ```
    
    **Example - Update address:**
    ```bash
    curl -X PATCH http://localhost:8004/auth/profile/ops_user \\
      -H "Content-Type: application/json" \\
      -d '{
        "address": {
          "street": "456 Oak Ave",
          "locality": "Chicago",
          "region": "IL",
          "postal_code": "60601",
          "country": "USA"
        }
      }'
    ```
    
    **Returns:**
    - Status and message
    - List of fields that were updated
    """
    try:
        return await wso2_client.update_profile(username, update_request)
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


@app.get("/auth/credentials")
async def get_oauth_credentials():
    """
    Get OAuth2 client credentials for frontend applications.
    
    Returns CLIENT_ID and CLIENT_SECRET needed for login/registration.
    These credentials are stored in .oauth_credentials file.
    """
    credentials_file = os.getenv("OAUTH_CREDENTIALS_FILE", "/app/.oauth_credentials")
    
    # Try multiple possible locations
    possible_locations = [
        credentials_file,
        "/app/.oauth_credentials",
        "/.oauth_credentials",
        ".oauth_credentials"
    ]
    
    for filepath in possible_locations:
        if os.path.exists(filepath):
            try:
                with open(filepath, 'r') as f:
                    client_id = None
                    client_secret = None
                    app_id = None
                    
                    for line in f:
                        line = line.strip()
                        if line.startswith('CLIENT_ID='):
                            client_id = line.split('=', 1)[1]
                        elif line.startswith('CLIENT_SECRET='):
                            client_secret = line.split('=', 1)[1]
                        elif line.startswith('APP_ID='):
                            app_id = line.split('=', 1)[1]
                    
                    if client_id and client_secret:
                        return {
                            "client_id": client_id,
                            "client_secret": client_secret,
                            "app_id": app_id,
                            "token_endpoint": "http://localhost:8004/auth/login",
                            "register_endpoint": "http://localhost:8004/register"
                        }
            except Exception as e:
                continue
    
    # If no credentials found, return error
    raise HTTPException(
        status_code=503,
        detail="OAuth credentials not available. Run complete_startup.sh to generate credentials."
    )


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