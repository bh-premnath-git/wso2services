"""
WSO2 Identity Server API Client
Handles user registration, authentication, and token operations
"""
import httpx
import base64
import jwt
from typing import Optional, Dict, Any
from .models import (
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


class WSO2ClientError(Exception):
    """WSO2 API client errors"""
    def __init__(self, status_code: int, detail: Any):
        self.status_code = status_code
        self.detail = detail
        super().__init__(f"WSO2 Error {status_code}: {detail}")


class WSO2IdentityClient:
    """
    WSO2 Identity Server API Client
    Handles user registration, authentication, and token operations
    """
    
    def __init__(
        self,
        base_url: str = "https://wso2is:9443",
        admin_user: str = "admin",
        admin_pass: str = "admin",
        verify_ssl: bool = False
    ):
        self.base_url = base_url
        self.admin_user = admin_user
        self.admin_pass = admin_pass
        self.verify_ssl = verify_ssl
        self.auth_header = self._create_basic_auth()
    
    def _create_basic_auth(self) -> str:
        """Create Basic Auth header"""
        credentials = f"{self.admin_user}:{self.admin_pass}"
        encoded = base64.b64encode(credentials.encode()).decode()
        return f"Basic {encoded}"
    
    async def register_user(
        self, 
        user: UserRegistrationRequest
    ) -> UserRegistrationResponse:
        """
        Register new user via SCIM2 API.
        Phone and address stored as user attributes - appear in JWT when scopes requested.
        
        Args:
            user: User registration details
            
        Returns:
            UserRegistrationResponse with user_id and available claims
            
        Raises:
            WSO2ClientError: If registration fails
        """
        
        # Build SCIM2 payload
        scim_user = {
            "schemas": ["urn:ietf:params:scim:schemas:core:2.0:User"],
            "userName": user.username,
            "password": user.password,
            "active": True,  # CRITICAL: Activate user immediately for OAuth password grant
            "name": {
                "givenName": user.first_name,
                "familyName": user.last_name,
                "formatted": f"{user.first_name} {user.last_name}"
            },
            "emails": [
                {
                    "value": user.email,
                    "primary": True
                }
            ]
        }
        
        # Add phone if provided (maps to http://wso2.org/claims/mobile)
        if user.phone:
            scim_user["phoneNumbers"] = [
                {
                    "type": "mobile",
                    "value": user.phone
                }
            ]
        
        # Add address if provided (maps to http://wso2.org/claims/addresses.*)
        if user.address:
            address_data = {}
            
            if user.address.street:
                address_data["streetAddress"] = user.address.street
            if user.address.locality:
                address_data["locality"] = user.address.locality
            if user.address.region:
                address_data["region"] = user.address.region
            if user.address.postal_code:
                address_data["postalCode"] = user.address.postal_code
            if user.address.country:
                address_data["country"] = user.address.country
            
            # Add formatted address
            formatted = user.address.to_formatted()
            if formatted:
                address_data["formatted"] = formatted
            
            if address_data:
                scim_user["addresses"] = [address_data]
        
        # Send request to WSO2 IS
        async with httpx.AsyncClient(verify=self.verify_ssl) as client:
            try:
                response = await client.post(
                    f"{self.base_url}/scim2/Users",
                    json=scim_user,
                    headers={
                        "Authorization": self.auth_header,
                        "Content-Type": "application/scim+json",
                        "Accept": "application/scim+json"
                    },
                    timeout=30.0
                )
                
                if response.status_code == 201:
                    user_data = response.json()
                    
                    # Build claims availability info
                    claims_available = {
                        "profile": ["given_name", "family_name", "email"],
                        "phone": ["phone_number"] if user.phone else [],
                        "address": [
                            "street_address", "locality", "region", 
                            "postal_code", "country", "formatted"
                        ] if user.address else []
                    }
                    
                    return UserRegistrationResponse(
                        status="success",
                        message="User registered successfully",
                        user_id=user_data.get("id"),
                        username=user_data.get("userName"),
                        claims_available=claims_available,
                        jwt_scopes_hint="Use scopes: openid profile email phone address"
                    )
                
                elif response.status_code == 409:
                    raise WSO2ClientError(
                        409,
                        {"error": "User already exists", "username": user.username}
                    )
                
                else:
                    error_data = response.json() if "application/json" in response.headers.get("content-type", "") else response.text
                    raise WSO2ClientError(response.status_code, error_data)
            
            except httpx.RequestError as e:
                raise WSO2ClientError(503, f"Failed to connect to WSO2 IS: {str(e)}")
    
    async def authenticate(
        self,
        token_request: TokenRequest
    ) -> TokenResponse:
        """
        Authenticate user and get JWT tokens.
        
        Supports email-to-username resolution: if username contains '@',
        it will be resolved to the actual username via SCIM API.
        
        Args:
            token_request: Username (or email), password, client credentials, and scopes
            
        Returns:
            TokenResponse with access_token, id_token, and decoded claims
            
        Raises:
            WSO2ClientError: If authentication fails
        """
        
        scope_string = " ".join(token_request.scopes)
        username = token_request.username
        
        # Email-to-username resolution
        if "@" in username:
            try:
                async with httpx.AsyncClient(verify=self.verify_ssl) as scim_client:
                    scim_response = await scim_client.get(
                        f"{self.base_url}/scim2/Users",
                        params={"filter": f"emails eq {username}"},
                        headers={
                            "Authorization": self.auth_header,
                            "Accept": "application/scim+json"
                        },
                        timeout=10.0
                    )
                    
                    if scim_response.status_code == 200:
                        data = scim_response.json()
                        if data.get("totalResults", 0) > 0:
                            actual_username = data["Resources"][0].get("userName")
                            if actual_username:
                                username = actual_username
            except Exception:
                # If resolution fails, continue with original username
                pass
        
        async with httpx.AsyncClient(verify=self.verify_ssl) as client:
            try:
                response = await client.post(
                    f"{self.base_url}/oauth2/token",
                    data={
                        "grant_type": "password",
                        "username": username,
                        "password": token_request.password,
                        "scope": scope_string
                    },
                    auth=(token_request.client_id, token_request.client_secret),
                    headers={"Content-Type": "application/x-www-form-urlencoded"},
                    timeout=30.0
                )
                
                if response.status_code == 200:
                    token_data = response.json()
                    
                    # Decode ID token to show claims (without verification for inspection)
                    id_token = token_data.get("id_token")
                    decoded_claims = None
                    if id_token:
                        try:
                            decoded_claims = jwt.decode(
                                id_token,
                                options={"verify_signature": False}
                            )
                        except Exception:
                            decoded_claims = None
                    
                    return TokenResponse(
                        access_token=token_data.get("access_token"),
                        id_token=id_token,
                        refresh_token=token_data.get("refresh_token"),
                        expires_in=token_data.get("expires_in"),
                        token_type=token_data.get("token_type"),
                        scope=token_data.get("scope"),
                        decoded_claims=decoded_claims
                    )
                
                elif response.status_code == 401:
                    raise WSO2ClientError(401, "Invalid credentials")
                
                else:
                    error_data = response.json() if "application/json" in response.headers.get("content-type", "") else response.text
                    raise WSO2ClientError(response.status_code, error_data)
            
            except httpx.RequestError as e:
                raise WSO2ClientError(503, f"Failed to connect to WSO2 IS: {str(e)}")
    
    async def get_userinfo(self, access_token: str) -> Dict[str, Any]:
        """
        Get user info from /userinfo endpoint.
        Returns claims based on scopes used during authentication.
        
        Args:
            access_token: OAuth2 access token
            
        Returns:
            User info dict with claims
            
        Raises:
            WSO2ClientError: If request fails
        """
        async with httpx.AsyncClient(verify=self.verify_ssl) as client:
            try:
                response = await client.get(
                    f"{self.base_url}/oauth2/userinfo",
                    headers={"Authorization": f"Bearer {access_token}"}
                )
                
                if response.status_code == 200:
                    return response.json()
                else:
                    raise WSO2ClientError(
                        response.status_code,
                        "Failed to fetch user info"
                    )
            
            except httpx.RequestError as e:
                raise WSO2ClientError(503, f"Failed to connect to WSO2 IS: {str(e)}")
    
    async def refresh_token(
        self,
        refresh_token: str,
        client_id: str,
        client_secret: str
    ) -> TokenResponse:
        """
        Refresh access token using refresh token.
        
        Args:
            refresh_token: OAuth2 refresh token
            client_id: OAuth2 client ID
            client_secret: OAuth2 client secret
            
        Returns:
            TokenResponse with new tokens
            
        Raises:
            WSO2ClientError: If refresh fails
        """
        async with httpx.AsyncClient(verify=self.verify_ssl) as client:
            try:
                response = await client.post(
                    f"{self.base_url}/oauth2/token",
                    data={
                        "grant_type": "refresh_token",
                        "refresh_token": refresh_token
                    },
                    auth=(client_id, client_secret),
                    headers={"Content-Type": "application/x-www-form-urlencoded"}
                )
                
                if response.status_code == 200:
                    token_data = response.json()
                    
                    return TokenResponse(
                        access_token=token_data.get("access_token"),
                        id_token=token_data.get("id_token", ""),
                        refresh_token=token_data.get("refresh_token"),
                        expires_in=token_data.get("expires_in"),
                        token_type=token_data.get("token_type"),
                        scope=token_data.get("scope"),
                        decoded_claims=None
                    )
                else:
                    raise WSO2ClientError(
                        response.status_code,
                        "Failed to refresh token"
                    )
            
            except httpx.RequestError as e:
                raise WSO2ClientError(503, f"Failed to connect to WSO2 IS: {str(e)}")
    
    async def reset_password(
        self,
        reset_request: PasswordResetRequest
    ) -> PasswordResetResponse:
        """
        Reset user password via SCIM2 API.
        
        Args:
            reset_request: Username and new password
            
        Returns:
            PasswordResetResponse confirming the reset
            
        Raises:
            WSO2ClientError: If password reset fails
        """
        async with httpx.AsyncClient(verify=self.verify_ssl) as client:
            try:
                # First, get user ID by username
                response = await client.get(
                    f"{self.base_url}/scim2/Users",
                    params={"filter": f"userName eq {reset_request.username}"},
                    headers={
                        "Authorization": self.auth_header,
                        "Accept": "application/scim+json"
                    },
                    timeout=30.0
                )
                
                if response.status_code != 200:
                    raise WSO2ClientError(response.status_code, "Failed to find user")
                
                users = response.json().get("Resources", [])
                if not users:
                    raise WSO2ClientError(404, f"User '{reset_request.username}' not found")
                
                user_id = users[0].get("id")
                
                # Update password via SCIM2 PATCH
                patch_response = await client.patch(
                    f"{self.base_url}/scim2/Users/{user_id}",
                    json={
                        "schemas": ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
                        "Operations": [{
                            "op": "replace",
                            "value": {
                                "password": reset_request.new_password,
                                "active": True
                            }
                        }]
                    },
                    headers={
                        "Authorization": self.auth_header,
                        "Content-Type": "application/scim+json",
                        "Accept": "application/scim+json"
                    },
                    timeout=30.0
                )
                
                if patch_response.status_code == 200:
                    return PasswordResetResponse(
                        status="success",
                        message="Password reset successfully",
                        username=reset_request.username
                    )
                else:
                    error_data = patch_response.json() if "application/json" in patch_response.headers.get("content-type", "") else patch_response.text
                    raise WSO2ClientError(patch_response.status_code, error_data)
            
            except httpx.RequestError as e:
                raise WSO2ClientError(503, f"Failed to connect to WSO2 IS: {str(e)}")
    
    async def update_profile(
        self,
        username: str,
        update_request: UserProfileUpdateRequest
    ) -> UserProfileUpdateResponse:
        """
        Update user profile via SCIM2 API.
        
        Args:
            username: Username to update
            update_request: Fields to update (all optional)
            
        Returns:
            UserProfileUpdateResponse with updated fields
            
        Raises:
            WSO2ClientError: If update fails
        """
        async with httpx.AsyncClient(verify=self.verify_ssl) as client:
            try:
                # First, get user ID by username
                response = await client.get(
                    f"{self.base_url}/scim2/Users",
                    params={"filter": f"userName eq {username}"},
                    headers={
                        "Authorization": self.auth_header,
                        "Accept": "application/scim+json"
                    },
                    timeout=30.0
                )
                
                if response.status_code != 200:
                    raise WSO2ClientError(response.status_code, "Failed to find user")
                
                users = response.json().get("Resources", [])
                if not users:
                    raise WSO2ClientError(404, f"User '{username}' not found")
                
                user_id = users[0].get("id")
                
                # Build PATCH operations for provided fields
                operations = []
                updated_fields = []
                
                if update_request.email is not None:
                    operations.append({
                        "op": "replace",
                        "path": "emails",
                        "value": [update_request.email]
                    })
                    updated_fields.append("email")
                
                if update_request.first_name is not None or update_request.last_name is not None:
                    name_value = {}
                    if update_request.first_name is not None:
                        name_value["givenName"] = update_request.first_name
                        updated_fields.append("first_name")
                    if update_request.last_name is not None:
                        name_value["familyName"] = update_request.last_name
                        updated_fields.append("last_name")
                    
                    operations.append({
                        "op": "replace",
                        "path": "name",
                        "value": name_value
                    })
                
                if update_request.phone is not None:
                    operations.append({
                        "op": "replace",
                        "path": "phoneNumbers",
                        "value": [update_request.phone]
                    })
                    updated_fields.append("phone")
                
                if update_request.address is not None:
                    address_value = {
                        "formatted": update_request.address.to_formatted()
                    }
                    if update_request.address.street:
                        address_value["streetAddress"] = update_request.address.street
                    if update_request.address.locality:
                        address_value["locality"] = update_request.address.locality
                    if update_request.address.region:
                        address_value["region"] = update_request.address.region
                    if update_request.address.postal_code:
                        address_value["postalCode"] = update_request.address.postal_code
                    if update_request.address.country:
                        address_value["country"] = update_request.address.country
                    
                    operations.append({
                        "op": "replace",
                        "path": "addresses",
                        "value": [address_value]
                    })
                    updated_fields.append("address")
                
                if not operations:
                    return UserProfileUpdateResponse(
                        status="success",
                        message="No fields to update",
                        username=username,
                        updated_fields=[]
                    )
                
                # Update via SCIM2 PATCH
                patch_response = await client.patch(
                    f"{self.base_url}/scim2/Users/{user_id}",
                    json={
                        "schemas": ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
                        "Operations": operations
                    },
                    headers={
                        "Authorization": self.auth_header,
                        "Content-Type": "application/scim+json",
                        "Accept": "application/scim+json"
                    },
                    timeout=30.0
                )
                
                if patch_response.status_code == 200:
                    return UserProfileUpdateResponse(
                        status="success",
                        message="Profile updated successfully",
                        username=username,
                        updated_fields=updated_fields
                    )
                else:
                    error_data = patch_response.json() if "application/json" in patch_response.headers.get("content-type", "") else patch_response.text
                    raise WSO2ClientError(patch_response.status_code, error_data)
            
            except httpx.RequestError as e:
                raise WSO2ClientError(503, f"Failed to connect to WSO2 IS: {str(e)}")
    
    async def self_register_user(
        self,
        user: SelfRegistrationRequest
    ) -> SelfRegistrationResponse:
        """
        Self-register user with email verification.
        User will receive verification email and account will be locked until verified.
        
        Args:
            user: User registration details
            
        Returns:
            SelfRegistrationResponse indicating verification email sent
            
        Raises:
            WSO2ClientError: If registration fails
        """
        
        # Build self-registration payload for WSO2 IS
        # This uses the /api/identity/user/v1.0/me endpoint
        registration_payload = {
            "user": {
                "username": user.username,
                "realm": "PRIMARY",
                "password": user.password,
                "claims": [
                    {
                        "uri": "http://wso2.org/claims/givenname",
                        "value": user.first_name
                    },
                    {
                        "uri": "http://wso2.org/claims/lastname",
                        "value": user.last_name
                    },
                    {
                        "uri": "http://wso2.org/claims/emailaddress",
                        "value": user.email
                    }
                ]
            },
            "properties": []
        }
        
        # Add phone if provided
        if user.phone:
            registration_payload["user"]["claims"].append({
                "uri": "http://wso2.org/claims/mobile",
                "value": user.phone
            })
        
        # Add address claims if provided
        if user.address:
            if user.address.street:
                registration_payload["user"]["claims"].append({
                    "uri": "http://wso2.org/claims/streetaddress",
                    "value": user.address.street
                })
            if user.address.locality:
                registration_payload["user"]["claims"].append({
                    "uri": "http://wso2.org/claims/locality",
                    "value": user.address.locality
                })
            if user.address.region:
                registration_payload["user"]["claims"].append({
                    "uri": "http://wso2.org/claims/region",
                    "value": user.address.region
                })
            if user.address.postal_code:
                registration_payload["user"]["claims"].append({
                    "uri": "http://wso2.org/claims/postalcode",
                    "value": user.address.postal_code
                })
            if user.address.country:
                registration_payload["user"]["claims"].append({
                    "uri": "http://wso2.org/claims/country",
                    "value": user.address.country
                })
        
        # Send request to WSO2 IS self-registration endpoint
        async with httpx.AsyncClient(verify=self.verify_ssl) as client:
            try:
                response = await client.post(
                    f"{self.base_url}/api/identity/user/v1.0/me",
                    json=registration_payload,
                    headers={
                        "Content-Type": "application/json",
                        "Accept": "application/json"
                    },
                    timeout=30.0
                )
                
                if response.status_code == 201:
                    # Registration successful - verification email sent
                    return SelfRegistrationResponse(
                        status="success",
                        message="Registration successful. Please check your email for verification code.",
                        username=user.username,
                        email=user.email,
                        confirmation_required=True,
                        code_sent_to=user.email
                    )
                
                elif response.status_code == 409:
                    raise WSO2ClientError(
                        409,
                        {"error": "User already exists", "username": user.username}
                    )
                
                else:
                    error_data = response.json() if "application/json" in response.headers.get("content-type", "") else response.text
                    raise WSO2ClientError(response.status_code, error_data)
            
            except httpx.RequestError as e:
                raise WSO2ClientError(503, f"Failed to connect to WSO2 IS: {str(e)}")
    
    async def verify_email(
        self,
        verification: EmailVerificationRequest
    ) -> EmailVerificationResponse:
        """
        Verify user email with confirmation code.
        Activates the user account after successful verification.
        
        Args:
            verification: Username and verification code from email
            
        Returns:
            EmailVerificationResponse confirming account activation
            
        Raises:
            WSO2ClientError: If verification fails
        """
        
        # Build verification payload
        verification_payload = {
            "code": verification.code,
            "properties": []
        }
        
        # Send verification request
        async with httpx.AsyncClient(verify=self.verify_ssl) as client:
            try:
                response = await client.post(
                    f"{self.base_url}/api/identity/user/v1.0/me/validate-code",
                    json=verification_payload,
                    headers={
                        "Content-Type": "application/json",
                        "Accept": "application/json"
                    },
                    timeout=30.0
                )
                
                if response.status_code == 202 or response.status_code == 200:
                    # Verification successful
                    return EmailVerificationResponse(
                        status="success",
                        message="Email verified successfully. Account is now active.",
                        username=verification.username,
                        account_activated=True
                    )
                
                elif response.status_code == 400:
                    raise WSO2ClientError(
                        400,
                        {"error": "Invalid or expired verification code"}
                    )
                
                else:
                    error_data = response.json() if "application/json" in response.headers.get("content-type", "") else response.text
                    raise WSO2ClientError(response.status_code, error_data)
            
            except httpx.RequestError as e:
                raise WSO2ClientError(503, f"Failed to connect to WSO2 IS: {str(e)}")
