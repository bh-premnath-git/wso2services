from fastapi import FastAPI, HTTPException, Request, Header
from pydantic import BaseModel, EmailStr
from datetime import datetime
from typing import Optional, Dict, Any
import logging
import hmac
import hashlib
import os
import sys
import httpx
import base64

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

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

from .email_service import email_service

app = FastAPI(
    title="Profile Service",
    version="1.0.0",
    description="User profile, registration, and authentication service"
)

add_cors_middleware(app)

try:
    from complycube import ComplyCubeClient
    from .config import settings
    
    COMPLYCUBE_API_KEY = os.getenv("COMPLYCUBE_API_KEY", "")
    complycube_client = ComplyCubeClient(api_key=COMPLYCUBE_API_KEY) if COMPLYCUBE_API_KEY else None
    
    if not complycube_client:
        logger.warning("ComplyCube API key not configured. KYC features will not work.")
    
    # In-memory user_id -> client_id mapping (replace with database)
    user_client_mapping = {}
except ImportError as e:
    logger.warning(f"ComplyCube integration not available: {e}")
    complycube_client = None
    user_client_mapping = {}

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

class KYCInitiateRequest(BaseModel):
    verification_level: str = "basic"  # "basic" or "enhanced"

class KYCInitiateResponse(BaseModel):
    session_id: str
    redirect_url: str
    status: str
    message: str


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
                params={"filter": f'userName eq "{username.replace(chr(34), chr(92)+chr(34))}"'},
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


@app.get("/auth/profile")
async def get_current_user_profile(authorization: str = Header(None)):
    """
    Get full user profile for the authenticated user using access token.
    
    **Authentication:**
    Include the access token in the Authorization header:
    `Authorization: Bearer <access_token>`
    
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
    curl http://localhost:8004/auth/profile \\
      -H "Authorization: Bearer <your_access_token>"
    ```
    
    This endpoint extracts the user identity from the access token
    and returns their complete profile from SCIM2.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="Missing or invalid Authorization header. Expected format: 'Bearer <token>'"
        )
    
    access_token = authorization.replace("Bearer ", "")
    
    try:
        # Get userinfo to extract subject (sub claim)
        userinfo = await wso2_client.get_userinfo(access_token)
        sub = userinfo.get("sub")
        
        if not sub:
            raise HTTPException(
                status_code=401,
                detail="Unable to extract subject from access token"
            )
        
        # Fetch full profile from SCIM
        async with httpx.AsyncClient(verify=False) as client:
            # 1) Try SCIM by ID (preferred - sub is the SCIM user ID)
            scim_by_id = await client.get(
                f"https://wso2is:9443/scim2/Users/{sub}",
                headers={
                    "Authorization": wso2_client.auth_header,
                    "Accept": "application/scim+json"
                },
                timeout=30.0
            )
            
            if scim_by_id.status_code == 200:
                user = scim_by_id.json()
            else:
                # 2) Fallback: try by username-style claims if present
                candidate = (
                    userinfo.get("username")
                    or userinfo.get("preferred_username")
                    or userinfo.get("email")
                )
                if not candidate:
                    raise HTTPException(status_code=404, detail="User not found for provided subject")
                
                # Quote the value in SCIM filter and escape embedded quotes
                filter_value = candidate.replace('"', r'\"')
                scim_search = await client.get(
                    f"https://wso2is:9443/scim2/Users",
                    params={"filter": f'userName eq "{filter_value}"'},
                    headers={
                        "Authorization": wso2_client.auth_header,
                        "Accept": "application/scim+json"
                    },
                    timeout=30.0
                )
                if scim_search.status_code != 200 or scim_search.json().get("totalResults", 0) == 0:
                    raise HTTPException(status_code=404, detail="User not found")
                
                user = scim_search.json()["Resources"][0]
            
            # Normalize profile fields
            emails = user.get("emails", [])
            phone_numbers = user.get("phoneNumbers", [])
            email_val = (emails[0].get("value") if emails and isinstance(emails[0], dict) else (emails[0] if emails else None))
            phone_val = (phone_numbers[0].get("value") if phone_numbers and isinstance(phone_numbers[0], dict) else (phone_numbers[0] if phone_numbers else None))
            
            profile = {
                "username": user.get("userName"),
                "id": user.get("id"),
                "active": user.get("active", False),
                "email": email_val,
                "given_name": user.get("name", {}).get("givenName"),
                "family_name": user.get("name", {}).get("familyName"),
                "full_name": user.get("name", {}).get("formatted"),
                "phone": phone_val,
                "roles": [r.get("display") for r in user.get("roles", [])],
            }
            return profile
                
    except WSO2ClientError as e:
        raise HTTPException(status_code=e.status_code, detail=e.detail)
    except httpx.RequestError as e:
        raise HTTPException(status_code=503, detail=f"Failed to connect to WSO2 IS: {str(e)}")


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


@app.post("/oauth2/token")
async def oauth2_token_endpoint(request: Request):
    """
    OAuth2 token endpoint proxy - handles standard OAuth2 flows.
    
    This endpoint acts as a proxy to WSO2 IS's /oauth2/token endpoint,
    bypassing SSL certificate issues for frontend applications.
    
    **Supported Grant Types:**
    - `password` - Resource Owner Password Credentials Grant
    - `refresh_token` - Refresh Token Grant
    - `authorization_code` - Authorization Code Grant
    - `client_credentials` - Client Credentials Grant
    
    **Email-to-Username Resolution:**
    The endpoint automatically resolves email addresses to usernames for password grant.
    You can use either username or email in the `username` field.
    
    **Usage for Password Grant (with username):**
    ```bash
    curl -X POST http://localhost:8004/oauth2/token \\
      -H "Content-Type: application/x-www-form-urlencoded" \\
      -d "grant_type=password" \\
      -d "username=johndoe" \\
      -d "password=SecurePass123!" \\
      -d "client_id=your_client_id" \\
      -d "client_secret=your_client_secret" \\
      -d "scope=openid profile email"
    ```
    
    **Usage for Password Grant (with email):**
    ```bash
    curl -X POST http://localhost:8004/oauth2/token \\
      -H "Content-Type: application/x-www-form-urlencoded" \\
      -d "grant_type=password" \\
      -d "username=john@example.com" \\
      -d "password=SecurePass123!" \\
      -d "client_id=your_client_id" \\
      -d "client_secret=your_client_secret" \\
      -d "scope=openid profile email"
    ```
    
    **Frontend JavaScript Example:**
    ```javascript
    const response = await fetch('http://localhost:8004/oauth2/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        grant_type: 'password',
        username: email,  // Can be username or email address
        password: password,
        client_id: clientId,
        client_secret: clientSecret,
        scope: 'openid profile email'
      })
    });
    ```
    """
    try:
        # Get form data from request
        form_data = await request.form()
        
        # Convert to dict for forwarding
        token_data = dict(form_data)
        
        # Email-to-username resolution for password grant
        # If username looks like an email, resolve it to actual username via SCIM
        if token_data.get("grant_type") == "password" and "username" in token_data:
            username = token_data["username"]
            if "@" in username:
                # Username is an email, need to resolve to actual username
                try:
                    async with httpx.AsyncClient(verify=False) as scim_client:
                        scim_response = await scim_client.get(
                            f"https://wso2is:9443/scim2/Users",
                            params={"filter": f'emails eq "{username.replace("\"" , r"\\\"")}"'},
                            headers={
                                "Authorization": wso2_client.auth_header,
                                "Accept": "application/scim+json"
                            },
                            timeout=10.0
                        )
                        
                        if scim_response.status_code == 200:
                            data = scim_response.json()
                            if data.get("totalResults", 0) > 0:
                                actual_username = data["Resources"][0].get("userName")
                                if actual_username:
                                    logger.info(f"Resolved email {username} to username {actual_username}")
                                    token_data["username"] = actual_username
                                else:
                                    logger.warning(f"No username found for email {username}")
                            else:
                                logger.warning(f"No user found with email {username}")
                except Exception as e:
                    logger.warning(f"Failed to resolve email to username: {e}")
                    # Continue with original username - WSO2 will handle the error
        
        # Extract auth from Authorization header if present (for client_credentials)
        auth_header = request.headers.get("Authorization")
        auth = None
        if auth_header and auth_header.startswith("Basic "):
            auth_str = base64.b64decode(auth_header.split(" ")[1]).decode()
            client_id, client_secret = auth_str.split(":", 1)
            auth = (client_id, client_secret)
        elif "client_id" in token_data and "client_secret" in token_data:
            auth = (token_data.pop("client_id"), token_data.pop("client_secret"))
        
        # Forward request to WSO2 IS
        wso2_token_url = f"{os.getenv('WSO2_IS_BASE', 'https://wso2is:9443')}/oauth2/token"
        
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.post(
                wso2_token_url,
                data=token_data,
                auth=auth,
                headers={"Content-Type": "application/x-www-form-urlencoded"},
                timeout=30.0
            )
            
            # Return the response from WSO2 IS
            if response.status_code == 200:
                return response.json()
            else:
                error_detail = response.json() if "application/json" in response.headers.get("content-type", "") else {"error": response.text}
                raise HTTPException(status_code=response.status_code, detail=error_detail)
                
    except httpx.RequestError as e:
        raise HTTPException(status_code=503, detail=f"Failed to connect to WSO2 IS: {str(e)}")
    except Exception as e:
        logger.error(f"OAuth2 token endpoint error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/auth/refresh")
async def refresh_access_token(
    refresh_token: str,
    client_id: str,
    client_secret: str
):
    """Refresh access token using refresh token"""
    try:
        return await wso2_client.refresh_token(refresh_token, client_id, client_secret)
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


@app.get("/profiles/{username}", response_model=UserProfile)
async def get_profile(username: str):
    """
    Get user profile with KYC status.
    
    Fetches user data from WSO2 IS and includes KYC verification status.
    
    **Path Parameter:**
    - username: The username to fetch profile for
    
    **Example:**
    ```bash
    curl http://localhost:8004/profiles/johndoe
    ```
    
    **Returns:** Complete user profile with KYC status
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
                    
                    # Extract user data
                    user_id = user.get("id")
                    emails = user.get("emails", [])
                    email = emails[0].get("value") if emails and isinstance(emails[0], dict) else (emails[0] if emails else "unknown@example.com")
                    phone_numbers = user.get("phoneNumbers", [])
                    phone = phone_numbers[0].get("value") if phone_numbers and isinstance(phone_numbers[0], dict) else (phone_numbers[0] if phone_numbers else None)
                    
                    given_name = user.get("name", {}).get("givenName", "")
                    family_name = user.get("name", {}).get("familyName", "")
                    full_name = f"{given_name} {family_name}".strip() or username
                    
                    # Get KYC status
                    kyc_status = "not_started"
                    client_id = user_client_mapping.get(username)
                    if client_id:
                        # Session has been created
                        kyc_status = "pending"
                        if complycube_client:
                            try:
                                checks_list = complycube_client.checks.list(clientId=client_id)
                                checks = list(checks_list) if checks_list else []
                                
                                if checks:
                                    passed = sum(1 for c in checks if getattr(getattr(c, 'result', None), 'outcome', None) == 'clear')
                                    failed = sum(1 for c in checks if getattr(getattr(c, 'result', None), 'outcome', None) in ['attention', 'rejected'])
                                    
                                    if failed > 0:
                                        kyc_status = "rejected"
                                    elif passed == len(checks):
                                        kyc_status = "verified"
                                    else:
                                        kyc_status = "pending"
                            except:
                                pass
                    
                    # Get creation date
                    created_at = user.get("meta", {}).get("created")
                    if created_at:
                        try:
                            created_at = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
                        except:
                            created_at = datetime.now()
                    else:
                        created_at = datetime.now()
                    
                    return UserProfile(
                        user_id=username,
                        email=email,
                        full_name=full_name,
                        phone=phone,
                        kyc_status=kyc_status,
                        created_at=created_at
                    )
                else:
                    raise HTTPException(status_code=404, detail=f"User '{username}' not found")
            else:
                raise HTTPException(status_code=response.status_code, detail="Failed to fetch user profile")
                
    except httpx.RequestError as e:
        raise HTTPException(status_code=503, detail=f"Failed to connect to WSO2 IS: {str(e)}")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching profile: {str(e)}")


@app.post("/profiles/{username}/kyc/initiate", response_model=KYCInitiateResponse)
async def initiate_kyc_verification(username: str, request: KYCInitiateRequest):
    """
    Initiate KYC verification using ComplyCube Flow hosted solution.
    
    Fetches user data from WSO2 IS and creates a ComplyCube verification session.
    
    **Path Parameter:**
    - username: The username to initiate KYC for
    
    **Request body:**
    ```json
    {
      "verification_level": "basic"  // or "enhanced"
    }
    ```
    
    **Example:**
    ```bash
    curl -X POST http://localhost:8004/profiles/johndoe/kyc/initiate \\
      -H "Content-Type: application/json" \\
      -d '{"verification_level": "basic"}'
    ```
    
    **Returns:** KYC session with redirect URL for user to complete verification
    """
    import httpx
    
    try:
        if not complycube_client:
            raise HTTPException(
                status_code=500,
                detail={
                    "error": "KYC_NOT_CONFIGURED",
                    "message": "ComplyCube API key is not configured",
                    "user_id": username
                }
            )
        
        logger.info(f"Initiating KYC verification for user: {username}")
        
        # Fetch user data from WSO2 IS
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(
                f"https://wso2is:9443/scim2/Users",
                params={"filter": f'userName eq "{username.replace(chr(34), chr(92)+chr(34))}"'},
                headers={
                    "Authorization": wso2_client.auth_header,
                    "Accept": "application/scim+json"
                },
                timeout=30.0
            )
            
            if response.status_code != 200:
                raise HTTPException(
                    status_code=404,
                    detail=f"User '{username}' not found in identity server"
                )
            
            data = response.json()
            if data.get("totalResults", 0) == 0:
                raise HTTPException(
                    status_code=404,
                    detail=f"User '{username}' not found"
                )
            
            user = data["Resources"][0]
            
            # Extract user details
            emails = user.get("emails", [])
            if not emails:
                raise HTTPException(
                    status_code=400,
                    detail="User email is required for KYC verification"
                )
            
            email = emails[0].get("value") if isinstance(emails[0], dict) else emails[0]
            given_name = user.get("name", {}).get("givenName", "")
            family_name = user.get("name", {}).get("familyName", "")
            
            if not given_name or not family_name:
                raise HTTPException(
                    status_code=400,
                    detail="User first name and last name are required for KYC verification"
                )
        
        # Create ComplyCube client
        cc_client = complycube_client.clients.create(
            type='person',
            email=email,
            personDetails={
                'firstName': given_name,
                'lastName': family_name
            }
        )
        
        client_id = cc_client.id
        logger.info(f"ComplyCube client created: {client_id}")
        
        user_client_mapping[username] = client_id
        
        # Use configured check types based on verification level
        check_types = settings.KYC_BASIC_CHECKS if request.verification_level == 'basic' else settings.KYC_ENHANCED_CHECKS
        
        success_url = settings.KYC_SUCCESS_URL
        cancel_url = settings.KYC_CANCEL_URL
        
        session = complycube_client.flow.create(
            clientId=client_id,
            checkTypes=check_types,
            successUrl=success_url,
            cancelUrl=cancel_url
        )
        
        redirect_url = session.redirect_url
        session_token = redirect_url.split('/')[-1] if redirect_url else "unknown"
        
        logger.info(f"Flow session created: {redirect_url}")
        
        return KYCInitiateResponse(
            session_id=session_token,
            redirect_url=redirect_url,
            status="active",
            message="KYC verification session created successfully"
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error initiating KYC for user {username}: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "error": "KYC_INITIATION_FAILED",
                "message": f"Failed to initiate KYC verification: {str(e)}",
                "user_id": username
            }
        )


@app.get("/profiles/{username}/kyc/status")
async def get_detailed_kyc_status(username: str):
    """
    Retrieve KYC verification status with check results and document URLs.
    
    **Path Parameter:**
    - username: The username to check KYC status for
    
    **Example:**
    ```bash
    curl http://localhost:8004/profiles/johndoe/kyc/status
    ```
    
    **Returns:** Complete KYC status including checks, documents, and verification results
    """
    try:
        client_id = user_client_mapping.get(username)
        
        if not client_id:
            logger.info(f"No ComplyCube client found for user: {username}")
            return {
                "user_id": username,
                "overall_status": "not_started",
                "verification_level": None,
                "last_verification_date": None,
                "total_sessions": 0,
                "completed_sessions": 0,
                "total_checks": 0,
                "passed_checks": 0,
                "failed_checks": 0,
                "checks": [],
                "documents": [],
                "sessions": [],
                "message": "KYC verification not yet initiated"
            }
        
        if not complycube_client:
            raise HTTPException(status_code=500, detail="ComplyCube client not configured")
        
        logger.info(f"Fetching KYC status for user: {username}, client_id: {client_id}")
        
        client = complycube_client.clients.get(client_id)
        checks_list = complycube_client.checks.list(clientId=client_id)
        checks = list(checks_list) if checks_list else []
        documents_list = complycube_client.documents.list(clientId=client_id)
        documents = list(documents_list) if documents_list else []
        
        total_checks = len(checks)
        passed_checks = 0
        failed_checks = 0
        
        for check in checks:
            result = getattr(check, 'result', None)
            if result:
                outcome = None
                if isinstance(result, dict):
                    outcome = result.get('outcome')
                elif isinstance(result, str):
                    outcome = result
                else:
                    outcome = getattr(result, 'outcome', None)
                
                if outcome == 'clear':
                    passed_checks += 1
                elif outcome in ['attention', 'rejected']:
                    failed_checks += 1
        
        if total_checks == 0:
            overall_status = "pending"
        elif failed_checks > 0:
            overall_status = "rejected"
        elif passed_checks == total_checks:
            overall_status = "verified"
        else:
            overall_status = "pending"
        
        last_verification_date = None
        if checks:
            latest_check = max(checks, key=lambda c: getattr(c, 'updatedAt', getattr(c, 'createdAt', '')))
            last_verification_date = getattr(latest_check, 'updatedAt', getattr(latest_check, 'createdAt', None))
        
        checks_data = []
        for check in checks:
            created_at = getattr(check, 'createdAt', None) or getattr(check, 'created_at', None)
            updated_at = getattr(check, 'updatedAt', None) or getattr(check, 'updated_at', None)
            
            checks_data.append({
                "id": getattr(check, 'id', None),
                "type": getattr(check, 'type', None),
                "status": getattr(check, 'status', None),
                "result": getattr(check, 'result', None),
                "created_at": created_at,
                "updated_at": updated_at
            })
        
        documents_data = []
        for doc in documents:
            doc_id = getattr(doc, 'id', None)
            created_at = getattr(doc, 'createdAt', None) or getattr(doc, 'created_at', None)
            
            doc_data = {
                "id": doc_id,
                "type": getattr(doc, 'type', None),
                "uploaded_at": created_at
            }
            
            if doc_id:
                doc_data["download_url"] = f"https://api.complycube.com/v1/documents/{doc_id}/download"
                
                images = getattr(doc, 'images', [])
                if images:
                    doc_data["images"] = []
                    for idx, image in enumerate(images):
                        image_id = getattr(image, 'id', None)
                        if image_id:
                            doc_data["images"].append({
                                "id": image_id,
                                "type": getattr(image, 'type', 'unknown'),
                                "url": f"https://api.complycube.com/v1/documents/{doc_id}/images/{image_id}"
                            })
            
            documents_data.append(doc_data)
        
        return {
            "user_id": username,
            "overall_status": overall_status,
            "verification_level": "basic",  # TODO: Get from stored data
            "last_verification_date": last_verification_date,
            "total_sessions": 1,  # TODO: Track actual sessions
            "completed_sessions": 1 if total_checks > 0 else 0,
            "total_checks": total_checks,
            "passed_checks": passed_checks,
            "failed_checks": failed_checks,
            "checks": checks_data,
            "documents": documents_data,
            "sessions": [],  # TODO: Track session history
            "complycube_client_id": client_id,
            "message": "KYC status retrieved from ComplyCube"
        }
        
    except Exception as e:
        logger.error(f"Error fetching KYC status for user {username}: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "error": "STATUS_FETCH_FAILED",
                "message": f"Failed to fetch KYC status: {str(e)}",
                "user_id": username
            }
        )


@app.post("/webhooks/complycube")
async def complycube_webhook(
    request: Request,
    x_complycube_signature: Optional[str] = Header(None)
):
    """Webhook endpoint for ComplyCube real-time events (validates HMAC-SHA256 signature)"""
    try:
        body = await request.body()
        payload = await request.json()
        
        webhook_secret = os.getenv("COMPLYCUBE_WEBHOOK_SECRET", "")
        if webhook_secret and x_complycube_signature:
            expected_signature = hmac.new(
                webhook_secret.encode(),
                body,
                hashlib.sha256
            ).hexdigest()
            
            if not hmac.compare_digest(expected_signature, x_complycube_signature):
                logger.warning("Webhook signature validation failed")
                raise HTTPException(status_code=401, detail="Invalid signature")
        
        event_type = payload.get("type")
        event_id = payload.get("id")
        logger.info(f"Received webhook: {event_type} (ID: {event_id})")
        logger.info(f"Payload: {payload}")
        if event_type == "check.completed":
            await handle_check_completed(payload)
        elif event_type == "check.pending":
            await handle_check_pending(payload)
        elif event_type == "document.uploaded":
            await handle_document_uploaded(payload)
        elif event_type == "client.updated":
            await handle_client_updated(payload)
        else:
            logger.info(f"Unhandled event type: {event_type}")
        
        return {"status": "received", "event_type": event_type}
        
    except Exception as e:
        logger.error(f"Webhook processing error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


async def handle_check_completed(payload: Dict[str, Any]):
    data = payload.get("data", {})
    check_id = data.get("id")
    check_type = data.get("type")
    result = data.get("result")
    client_id = data.get("clientId")
    
    logger.info(f"Check completed: {check_type} for client {client_id}, result: {result}")
    # TODO: db.update_kyc_check(client_id, check_id, check_type, result)


async def handle_check_pending(payload: Dict[str, Any]):
    data = payload.get("data", {})
    check_id = data.get("id")
    check_type = data.get("type")
    client_id = data.get("clientId")
    
    logger.info(f"Check pending: {check_type} for client {client_id}")
    # TODO: db.update_kyc_check_status(client_id, check_id, "pending")


async def handle_document_uploaded(payload: Dict[str, Any]):
    data = payload.get("data", {})
    document_id = data.get("id")
    document_type = data.get("type")
    client_id = data.get("clientId")
    
    logger.info(f"Document uploaded: {document_type} for client {client_id}")
    # TODO: db.add_kyc_document(client_id, document_id, document_type)


async def handle_client_updated(payload: Dict[str, Any]):
    data = payload.get("data", {})
    client_id = data.get("id")
    
    logger.info(f"Client updated: {client_id}")
    # TODO: db.update_client_info(client_id, data)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8004)