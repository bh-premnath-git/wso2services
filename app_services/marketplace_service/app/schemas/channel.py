"""Channel schemas"""
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class ChannelBase(BaseModel):
    code: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = None
    is_consumer_visible: bool = True


class ChannelCreate(ChannelBase):
    id: str = Field(..., min_length=1, max_length=100)


class ChannelUpdate(BaseModel):
    code: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = None
    is_consumer_visible: Optional[bool] = None


class ChannelResponse(ChannelBase):
    id: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
