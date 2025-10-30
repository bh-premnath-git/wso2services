"""
Auth models for user registration and JWT token handling
"""
from pydantic import BaseModel, EmailStr, Field, validator
from typing import Optional
import re


class AddressInfo(BaseModel):
    """Address information - all fields optional"""
    street: Optional[str] = Field(None, max_length=255)
    locality: Optional[str] = Field(None, max_length=100, description="City")
    region: Optional[str] = Field(None, max_length=100, description="State/Province")
    postal_code: Optional[str] = Field(None, max_length=20)
    country: Optional[str] = Field(None, max_length=100)
    
    def to_formatted(self) -> str:
        """Generate formatted address string for JWT"""
        parts = []
        if self.street:
            parts.append(self.street)
        if self.locality:
            parts.append(self.locality)
        if self.region or self.postal_code:
            region_postal = " ".join(filter(None, [self.region, self.postal_code]))
            parts.append(region_postal)
        if self.country:
            parts.append(self.country)
        return ", ".join(parts) if parts else ""


class UserRegistrationRequest(BaseModel):
    """User registration request with optional phone and address"""
    username: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=8)
    email: EmailStr
    first_name: str = Field(..., min_length=1, max_length=100)
    last_name: str = Field(..., min_length=1, max_length=100)
    
    # Optional fields - will appear in JWT when appropriate scopes requested
    phone: Optional[str] = Field(
        None, 
        description="Phone number in E.164 format (+1234567890)"
    )
    address: Optional[AddressInfo] = Field(
        None, 
        description="User address - all subfields optional"
    )
    
    @validator('password')
    def validate_password_strength(cls, v):
        """Enforce strong password policy"""
        errors = []
        if not re.search(r'[A-Z]', v):
            errors.append("at least one uppercase letter")
        if not re.search(r'[a-z]', v):
            errors.append("at least one lowercase letter")
        if not re.search(r'\d', v):
            errors.append("at least one digit")
        if not re.search(r'[!@#$%^&*()_+\-=\[\]{};:\'",.<>?/\\|`~]', v):
            errors.append("at least one special character")
        
        if errors:
            raise ValueError(f"Password must contain {', '.join(errors)}")
        return v
    
    @validator('phone')
    def validate_phone_format(cls, v):
        """Validate E.164 phone format"""
        if v and not re.match(r'^\+[1-9]\d{1,14}$', v):
            raise ValueError(
                "Phone must be in E.164 format: +[country][number] (e.g., +12025551234)"
            )
        return v
    
    @validator('username')
    def validate_username(cls, v):
        """Username: alphanumeric, underscore, hyphen only"""
        if not re.match(r'^[a-zA-Z0-9_-]+$', v):
            raise ValueError(
                "Username can only contain letters, numbers, underscore, and hyphen"
            )
        return v


class UserRegistrationResponse(BaseModel):
    """Response after successful user registration"""
    status: str
    message: str
    user_id: str
    username: str
    claims_available: dict
    jwt_scopes_hint: str


class TokenRequest(BaseModel):
    """OAuth2 token request"""
    username: str
    password: str
    client_id: str
    client_secret: str
    scopes: Optional[list[str]] = Field(
        default=["openid", "profile", "email", "phone", "address"],
        description="OIDC scopes to request"
    )


class TokenResponse(BaseModel):
    """OAuth2 token response with decoded claims"""
    access_token: str
    id_token: str
    refresh_token: Optional[str]
    expires_in: int
    token_type: str
    scope: str
    decoded_claims: Optional[dict] = None


class PasswordResetRequest(BaseModel):
    """Password reset request"""
    username: str = Field(..., min_length=3, max_length=50)
    new_password: str = Field(..., min_length=8)
    
    @validator('new_password')
    def validate_password_strength(cls, v):
        """Enforce strong password policy"""
        errors = []
        if not re.search(r'[A-Z]', v):
            errors.append("at least one uppercase letter")
        if not re.search(r'[a-z]', v):
            errors.append("at least one lowercase letter")
        if not re.search(r'\d', v):
            errors.append("at least one digit")
        if not re.search(r'[!@#$%^&*()_+\-=\[\]{};:\'",.<>?/\\|`~]', v):
            errors.append("at least one special character")
        
        if errors:
            raise ValueError(f"Password must contain {', '.join(errors)}")
        return v


class PasswordResetResponse(BaseModel):
    """Response after password reset"""
    status: str
    message: str
    username: str


class UserProfileUpdateRequest(BaseModel):
    """Update user profile - all fields optional"""
    email: Optional[EmailStr] = None
    first_name: Optional[str] = Field(None, min_length=1, max_length=100)
    last_name: Optional[str] = Field(None, min_length=1, max_length=100)
    phone: Optional[str] = Field(
        None,
        description="Phone number in E.164 format (+1234567890)"
    )
    address: Optional[AddressInfo] = Field(
        None,
        description="User address - all subfields optional"
    )
    
    @validator('phone')
    def validate_phone_format(cls, v):
        """Validate E.164 phone format"""
        if v and not re.match(r'^\+[1-9]\d{1,14}$', v):
            raise ValueError(
                "Phone must be in E.164 format: +[country][number] (e.g., +12025551234)"
            )
        return v


class UserProfileUpdateResponse(BaseModel):
    """Response after profile update"""
    status: str
    message: str
    username: str
    updated_fields: list


class SelfRegistrationRequest(BaseModel):
    """Self-registration request with email verification"""
    username: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=8)
    email: EmailStr
    first_name: str = Field(..., min_length=1, max_length=100)
    last_name: str = Field(..., min_length=1, max_length=100)
    
    # Optional fields
    phone: Optional[str] = Field(
        None, 
        description="Phone number in E.164 format (+1234567890)"
    )
    address: Optional[AddressInfo] = Field(
        None, 
        description="User address - all subfields optional"
    )
    
    @validator('password')
    def validate_password_strength(cls, v):
        """Enforce strong password policy"""
        errors = []
        if not re.search(r'[A-Z]', v):
            errors.append("at least one uppercase letter")
        if not re.search(r'[a-z]', v):
            errors.append("at least one lowercase letter")
        if not re.search(r'\d', v):
            errors.append("at least one digit")
        if not re.search(r'[!@#$%^&*()_+\-=\[\]{};:\'",.<>?/\\|`~]', v):
            errors.append("at least one special character")
        
        if errors:
            raise ValueError(f"Password must contain {', '.join(errors)}")
        return v
    
    @validator('phone')
    def validate_phone_format(cls, v):
        """Validate E.164 phone format"""
        if v and not re.match(r'^\+[1-9]\d{1,14}$', v):
            raise ValueError(
                "Phone must be in E.164 format: +[country][number] (e.g., +12025551234)"
            )
        return v
    
    @validator('username')
    def validate_username(cls, v):
        """Username: alphanumeric, underscore, hyphen only"""
        if not re.match(r'^[a-zA-Z0-9_-]+$', v):
            raise ValueError(
                "Username can only contain letters, numbers, underscore, and hyphen"
            )
        return v


class SelfRegistrationResponse(BaseModel):
    """Response after self-registration (requires email verification)"""
    status: str
    message: str
    username: str
    email: str
    confirmation_required: bool = True
    code_sent_to: str


class EmailVerificationRequest(BaseModel):
    """Email verification with code"""
    username: str
    code: str = Field(..., min_length=4, description="Verification code from email")


class EmailVerificationResponse(BaseModel):
    """Response after email verification"""
    status: str
    message: str
    username: str
    account_activated: bool
