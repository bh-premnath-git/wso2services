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
    TokenResponse
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
        
        Args:
            token_request: Username, password, client credentials, and scopes
            
        Returns:
            TokenResponse with access_token, id_token, and decoded claims
            
        Raises:
            WSO2ClientError: If authentication fails
        """
        
        scope_string = " ".join(token_request.scopes)
        
        async with httpx.AsyncClient(verify=self.verify_ssl) as client:
            try:
                response = await client.post(
                    f"{self.base_url}/oauth2/token",
                    data={
                        "grant_type": "password",
                        "username": token_request.username,
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
