"""Fee schemas"""
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field
from ..models.fee import FeeType


class FeeBase(BaseModel):
    corridor_route_id: str = Field(..., min_length=1, max_length=100)
    fee_type: FeeType
    value_flat: Optional[float] = Field(None, ge=0)
    value_percent: Optional[float] = Field(None, ge=0)
    min_fee: Optional[float] = Field(None, ge=0)
    max_fee: Optional[float] = Field(None, ge=0)
    effective_from: Optional[datetime] = None
    effective_to: Optional[datetime] = None


class FeeCreate(FeeBase):
    id: str = Field(..., min_length=1, max_length=100)


class FeeUpdate(BaseModel):
    corridor_route_id: Optional[str] = Field(None, min_length=1, max_length=100)
    fee_type: Optional[FeeType] = None
    value_flat: Optional[float] = Field(None, ge=0)
    value_percent: Optional[float] = Field(None, ge=0)
    min_fee: Optional[float] = Field(None, ge=0)
    max_fee: Optional[float] = Field(None, ge=0)
    effective_from: Optional[datetime] = None
    effective_to: Optional[datetime] = None


class FeeResponse(FeeBase):
    id: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
