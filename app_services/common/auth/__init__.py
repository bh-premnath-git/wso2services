"""
Common auth module for WSO2 IS integration
"""
from .wso2_client import WSO2IdentityClient, WSO2ClientError
from .models import (
    UserRegistrationRequest,
    UserRegistrationResponse,
    TokenRequest,
    TokenResponse,
    AddressInfo,
    PasswordResetRequest,
    PasswordResetResponse,
    UserProfileUpdateRequest,
    UserProfileUpdateResponse,
    SelfRegistrationRequest,
    SelfRegistrationResponse,
    EmailVerificationRequest,
    EmailVerificationResponse
)

__all__ = [
    "UserRegistrationRequest",
    "UserRegistrationResponse",
    "TokenRequest",
    "TokenResponse",
    "AddressInfo",
    "PasswordResetRequest",
    "PasswordResetResponse",
    "UserProfileUpdateRequest",
    "UserProfileUpdateResponse",
    "SelfRegistrationRequest",
    "SelfRegistrationResponse",
    "EmailVerificationRequest",
    "EmailVerificationResponse",
    "WSO2IdentityClient",
    "WSO2ClientError"
]
