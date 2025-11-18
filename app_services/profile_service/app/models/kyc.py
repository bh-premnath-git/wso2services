"""
Pydantic models for KYC API (simplified for current implementation)
"""
from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import datetime
from enum import Enum


class KYCStatus(str, Enum):
    """KYC verification status"""
    NOT_STARTED = "not_started"
    PENDING = "pending"
    VERIFIED = "verified"
    REJECTED = "rejected"


class UserProfile(BaseModel):
    """User profile model"""
    user_id: str
    email: EmailStr
    full_name: str
    phone: Optional[str] = None
    kyc_status: str
    created_at: datetime


class KYCInitiateRequest(BaseModel):
    """Request to initiate KYC verification"""
    user_id: str
    email: EmailStr
    first_name: str
    last_name: str
    phone: Optional[str] = None
    verification_level: str = "basic"  # basic or enhanced


class KYCInitiateResponse(BaseModel):
    """Response after initiating KYC verification"""
    session_id: str
    redirect_url: str
    status: str
    message: str