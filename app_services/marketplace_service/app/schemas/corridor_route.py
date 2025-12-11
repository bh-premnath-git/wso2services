"""CorridorRoute schemas"""
from datetime import datetime
from typing import Optional, Dict, Any
from pydantic import BaseModel, Field
from ..models.corridor_route import RouteStatus


class CorridorRouteBase(BaseModel):
    corridor_id: str = Field(..., min_length=1, max_length=100)
    channel_id: str = Field(..., min_length=1, max_length=100)
    psp_id: str = Field(..., min_length=1, max_length=100)
    priority: int = Field(1, ge=1)
    weight: int = Field(100, ge=0, le=100)
    min_amount: Optional[float] = Field(None, ge=0)
    max_amount: Optional[float] = Field(None, ge=0)
    min_fx_margin: Optional[float] = None
    max_fx_margin: Optional[float] = None
    status: RouteStatus = RouteStatus.ACTIVE
    metadata: Optional[Dict[str, Any]] = None


class CorridorRouteCreate(CorridorRouteBase):
    id: str = Field(..., min_length=1, max_length=100)


class CorridorRouteUpdate(BaseModel):
    corridor_id: Optional[str] = Field(None, min_length=1, max_length=100)
    channel_id: Optional[str] = Field(None, min_length=1, max_length=100)
    psp_id: Optional[str] = Field(None, min_length=1, max_length=100)
    priority: Optional[int] = Field(None, ge=1)
    weight: Optional[int] = Field(None, ge=0, le=100)
    min_amount: Optional[float] = Field(None, ge=0)
    max_amount: Optional[float] = Field(None, ge=0)
    min_fx_margin: Optional[float] = None
    max_fx_margin: Optional[float] = None
    status: Optional[RouteStatus] = None
    metadata: Optional[Dict[str, Any]] = None


class CorridorRouteResponse(CorridorRouteBase):
    id: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
