"""PSP schemas"""
from datetime import datetime
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field
from ..models.psp import PSPStatus, PSPType


class PSPBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    type: PSPType
    status: PSPStatus = PSPStatus.ACTIVE
    capabilities: Optional[List[str]] = None
    regions_supported: Optional[List[str]] = None
    metadata: Optional[Dict[str, Any]] = None


class PSPCreate(PSPBase):
    id: str = Field(..., min_length=1, max_length=100)


class PSPUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    type: Optional[PSPType] = None
    status: Optional[PSPStatus] = None
    capabilities: Optional[List[str]] = None
    regions_supported: Optional[List[str]] = None
    metadata: Optional[Dict[str, Any]] = None


class PSPResponse(PSPBase):
    id: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
