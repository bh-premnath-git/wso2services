"""
Pydantic schemas for API requests and responses
"""
from pydantic import BaseModel, Field, field_validator
from typing import Optional
from datetime import datetime
from decimal import Decimal
from uuid import UUID


class ConnectRequest(BaseModel):
    """Request to generate Connect URL"""
    redirect_uri: str = Field(..., description="URL to redirect after account linking")
    institution_id: Optional[str] = Field(None, description="Pre-select specific institution")
    webhook_url: Optional[str] = Field(None, description="Webhook URL for notifications")


class ConnectResponse(BaseModel):
    """Response with Connect URL"""
    connect_url: str = Field(..., description="Mastercard Connect URL")
    session_id: str = Field(..., description="Session identifier")
    expires_at: Optional[datetime] = Field(None, description="URL expiration time")


class BankAccount(BaseModel):
    """Bank account details"""
    id: str
    user_id: str
    account_name: Optional[str] = None
    account_number_masked: str
    account_type: str
    institution_name: str
    institution_logo_url: Optional[str] = None
    current_balance: Optional[Decimal] = None
    available_balance: Optional[Decimal] = None
    currency: str = "USD"
    status: str
    is_primary: bool = False
    is_verified: bool = False
    created_at: datetime
    updated_at: datetime
    
    @field_validator('id', mode='before')
    @classmethod
    def convert_uuid_to_str(cls, v):
        """Convert UUID to string"""
        if isinstance(v, UUID):
            return str(v)
        return v
    
    class Config:
        from_attributes = True


class BankAccountListResponse(BaseModel):
    """List of bank accounts"""
    accounts: list[BankAccount]
    total: int


class BankAccountDetails(BankAccount):
    """Detailed bank account information"""
    routing_number: Optional[str] = None
    account_holder_name: Optional[str] = None
    last_updated_at: Optional[datetime] = None
    consent_granted_at: Optional[datetime] = None
    consent_expires_at: Optional[datetime] = None


class UnlinkAccountResponse(BaseModel):
    """Response after unlinking account"""
    status: str = "unlinked"
    message: str
    account_id: str
    
    @field_validator('account_id', mode='before')
    @classmethod
    def convert_uuid_to_str(cls, v):
        """Convert UUID to string"""
        if isinstance(v, UUID):
            return str(v)
        return v


class SetPrimaryAccountResponse(BaseModel):
    """Response after setting primary account"""
    status: str = "updated"
    account_id: str
    is_primary: bool = True
    
    @field_validator('account_id', mode='before')
    @classmethod
    def convert_uuid_to_str(cls, v):
        """Convert UUID to string"""
        if isinstance(v, UUID):
            return str(v)
        return v


class HealthResponse(BaseModel):
    """Health check response"""
    status: str
    service: str
    version: str
    database: str
    cache: str
