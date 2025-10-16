"""
Common auth module for WSO2 IS integration
"""
from .models import (
    UserRegistrationRequest,
    UserRegistrationResponse,
    TokenRequest,
    TokenResponse,
    AddressInfo
)
from .wso2_client import WSO2IdentityClient, WSO2ClientError

__all__ = [
    "UserRegistrationRequest",
    "UserRegistrationResponse",
    "TokenRequest",
    "TokenResponse",
    "AddressInfo",
    "WSO2IdentityClient",
    "WSO2ClientError"
]
