"""
Common auth module for WSO2 IS integration
"""
from .models import (
    UserRegistrationRequest,
    UserRegistrationResponse,
    TokenRequest,
    TokenResponse,
    AddressInfo,
    PasswordResetRequest,
    PasswordResetResponse
)

__all__ = [
    "UserRegistrationRequest",
    "UserRegistrationResponse",
    "TokenRequest",
    "TokenResponse",
    "AddressInfo",
    "PasswordResetRequest",
    "PasswordResetResponse",
    "WSO2IdentityClient",
    "WSO2ClientError"
]
