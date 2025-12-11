"""Corridor schemas"""
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field
from ..models.corridor import CorridorStatus, RoutePolicy


class CorridorBase(BaseModel):
    source_country: str = Field(..., min_length=2, max_length=2, pattern="^[A-Z]{2}$")
    dest_country: str = Field(..., min_length=2, max_length=2, pattern="^[A-Z]{2}$")
    source_currency: str = Field(..., min_length=3, max_length=3, pattern="^[A-Z]{3}$")
    dest_currency: str = Field(..., min_length=3, max_length=3, pattern="^[A-Z]{3}$")
    status: CorridorStatus = CorridorStatus.ACTIVE
    default_route_policy: RoutePolicy = RoutePolicy.PRIORITY


class CorridorCreate(CorridorBase):
    id: str = Field(..., min_length=1, max_length=100)


class CorridorUpdate(BaseModel):
    source_country: Optional[str] = Field(None, min_length=2, max_length=2, pattern="^[A-Z]{2}$")
    dest_country: Optional[str] = Field(None, min_length=2, max_length=2, pattern="^[A-Z]{2}$")
    source_currency: Optional[str] = Field(None, min_length=3, max_length=3, pattern="^[A-Z]{3}$")
    dest_currency: Optional[str] = Field(None, min_length=3, max_length=3, pattern="^[A-Z]{3}$")
    status: Optional[CorridorStatus] = None
    default_route_policy: Optional[RoutePolicy] = None


class CorridorResponse(CorridorBase):
    id: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
