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

from middleware import add_cors_middleware
from auth.wso2_client import WSO2IdentityClient, WSO2ClientError
from auth.models import (
    UserRegistrationRequest,
    UserRegistrationResponse,
    TokenRequest,
    TokenResponse,
    PasswordResetRequest,
    PasswordResetResponse,
    UserProfileUpdateRequest,
    UserProfileUpdateResponse,
    SelfRegistrationRequest,
    SelfRegistrationResponse,
    EmailVerificationRequest,
    EmailVerificationResponse
)
from .email_service import email_service

app = FastAPI(
    title="Profile Service",
    version="1.0.0",
    description="User profile, registration, and authentication service"
)

add_cors_middleware(app)

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


@app.post("/register")
async def register_user(user: UserRegistrationRequest, mode: str = "instant"):
    """
    Register new user with optional phone and address.
    
    **Registration Modes:**
    - `instant` (default): Admin-based registration, user active immediately, no email verification
    - `email`: Self-registration with email verification, account locked until verified
    
    **Required:** username, password, email, first_name, last_name
    
    **Optional:** phone, address (street, locality, region, postal_code, country)
    
    **Mode Parameter:** Add `?mode=email` or `?mode=instant` to the URL
    
    **Example - Instant registration:**
    ```bash
    POST /register?mode=instant
    ```
    
    **Example - Email verification:**
    ```bash
    POST /register?mode=email
    ```
    
    **Example payload:**
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
        # Always use instant registration (admin-based)
        registration_response = await wso2_client.register_user(user)
        
        if mode == "email":
            # Send verification email
            try:
                code = await email_service.send_verification_email(
                    recipient_email=user.email,
                    username=user.username,
                    first_name=user.first_name
                )
                
                # Return response indicating email was sent
                return {
                    "status": "success",
                    "message": f"User registered. Verification email sent to {user.email}",
                    "user_id": registration_response.user_id,
                    "username": registration_response.username,
                    "email": user.email,
                    "verification_required": True,
                    "verification_code_sent": True
                }
            except Exception as e:
                # User is still registered, just email failed
                return {
                    "status": "partial_success",
                    "message": f"User registered but email failed: {str(e)}",
                    "user_id": registration_response.user_id,
                    "username": registration_response.username,
                    "verification_required": True,
                    "verification_code_sent": False
                }
        else:
            # Instant mode - no email required
            return registration_response
    except WSO2ClientError as e:
        raise HTTPException(status_code=e.status_code, detail=e.detail)


@app.post("/verify-email", response_model=EmailVerificationResponse)
async def verify_email(verification: EmailVerificationRequest):
    """
    Verify user email with confirmation code.
    
    After registration (mode=email), users receive a verification code via email.
    Submit the code here to verify the email address.
    
    **Request body:**
    ```json
    {
      "username": "johndoe",
      "code": "123456"
    }
    ```
    
    **Example:**
    ```bash
    curl -X POST http://localhost:8004/verify-email \\
      -H "Content-Type: application/json" \\
      -d '{"username": "johndoe", "code": "123456"}'
    ```
    
    **Returns:** Email verification confirmation
    """
    # Verify the code using email service
    is_valid = email_service.verify_code(verification.username, verification.code)
    
    if is_valid:
        return EmailVerificationResponse(
            status="success",
            message="Email verified successfully.",
            username=verification.username,
            account_activated=True
        )
    else:
        raise HTTPException(
            status_code=400,
            detail="Invalid or expired verification code"
        )


@app.post("/resend-verification-email")
async def resend_verification_email(username: str):
    """
    Resend verification email to user.
    
    If the user didn't receive the verification email or the code expired,
    use this endpoint to send a new verification code.
    
    **Query Parameter:**
    - username: The username to resend verification email for
    
    **Example:**
    ```bash
    curl -X POST "http://localhost:8004/resend-verification-email?username=johndoe"
    ```
    
    **Returns:** Confirmation that email was sent
    """
    import httpx
    
    try:
        # Get user info from SCIM to get email and name
        async with httpx.AsyncClient(verify=False) as client:
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
                    emails = user.get("emails", [])
                    if not emails:
                        raise HTTPException(status_code=404, detail="User email not found")
                    
                    email = emails[0].get("value") if isinstance(emails[0], dict) else emails[0]
                    first_name = user.get("name", {}).get("givenName", username)
                    
                    # Send verification email
                    try:
                        code = await email_service.send_verification_email(
                            recipient_email=email,
                            username=username,
                            first_name=first_name
                        )
                        
                        return {
                            "status": "success",
                            "message": f"Verification email resent to {email}",
                            "username": username,
                            "email": email
                        }
                    except Exception as e:
                        raise HTTPException(status_code=500, detail=f"Failed to send email: {str(e)}")
                else:
                    raise HTTPException(status_code=404, detail=f"User '{username}' not found")
            else:
                raise HTTPException(status_code=response.status_code, detail="Failed to fetch user info")
                
    except httpx.RequestError as e:
        raise HTTPException(status_code=503, detail=f"Failed to connect to WSO2 IS: {str(e)}")


@app.get("/verification-status/{username}")
async def get_verification_status(username: str):
    """
    Check email verification status for a user.
    
    Returns whether the user account is active (verified) or locked (pending verification).
    
    **Path Parameter:**
    - username: The username to check status for
    
    **Example:**
    ```bash
    curl http://localhost:8004/verification-status/johndoe
    ```
    
    **Returns:**
    ```json
    {
      "username": "johndoe",
      "account_active": true,
      "account_locked": false,
      "email_verified": true,
      "status": "verified"
    }
    ```
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
                    is_active = user.get("active", False)
                    
                    # Check if there's a pending verification code
                    has_pending = email_service.has_pending_verification(username)
                    
                    return {
                        "username": username,
                        "account_active": is_active,
                        "account_locked": False,  # Always false since we use instant registration
                        "email_verified": not has_pending,
                        "pending_email_verification": has_pending,
                        "status": "pending_email_verification" if has_pending else "verified"
                    }
                else:
                    raise HTTPException(status_code=404, detail=f"User '{username}' not found")
            else:
                raise HTTPException(status_code=response.status_code, detail="Failed to fetch user status")
                
    except httpx.RequestError as e:
        raise HTTPException(status_code=503, detail=f"Failed to connect to WSO2 IS: {str(e)}")


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
            "User registration with instant or email verification modes",
            "Email verification with resend capability",
            "JWT authentication with custom claims",
            "Token refresh",
            "User info endpoint",
            "User profile management",
            "Password reset",
            "KYC status tracking"
        ],
        "endpoints": {
            "register": "POST /register?mode=instant|email",
            "verify_email": "POST /verify-email",
            "resend_verification": "POST /resend-verification-email",
            "verification_status": "GET /verification-status/{username}",
            "login": "POST /auth/login",
            "userinfo": "GET /auth/userinfo",
            "profile_get": "GET /auth/profile/{username}",
            "profile_update": "PATCH /auth/profile/{username}",
            "reset_password": "POST /auth/reset-password",
            "refresh": "POST /auth/refresh",
            "credentials": "GET /auth/credentials",
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