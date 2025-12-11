"""RouteOverride schemas"""
from datetime import datetime
from typing import Optional, Dict, Any
from pydantic import BaseModel, Field
from ..models.route_override import SegmentType


class RouteOverrideBase(BaseModel):
    corridor_route_id: str = Field(..., min_length=1, max_length=100)
    segment_type: SegmentType
    segment_value: str = Field(..., min_length=1, max_length=100)
    override_priority: Optional[int] = Field(None, ge=1)
    override_weight: Optional[int] = Field(None, ge=0, le=100)
    override_status: Optional[str] = Field(None, max_length=50)
    override_metadata: Optional[Dict[str, Any]] = None


class RouteOverrideCreate(RouteOverrideBase):
    id: str = Field(..., min_length=1, max_length=100)


class RouteOverrideUpdate(BaseModel):
    corridor_route_id: Optional[str] = Field(None, min_length=1, max_length=100)
    segment_type: Optional[SegmentType] = None
    segment_value: Optional[str] = Field(None, min_length=1, max_length=100)
    override_priority: Optional[int] = Field(None, ge=1)
    override_weight: Optional[int] = Field(None, ge=0, le=100)
    override_status: Optional[str] = Field(None, max_length=50)
    override_metadata: Optional[Dict[str, Any]] = None


class RouteOverrideResponse(RouteOverrideBase):
    id: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
