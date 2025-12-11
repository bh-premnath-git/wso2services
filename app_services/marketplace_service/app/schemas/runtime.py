"""Runtime API schemas for orchestrator consumption"""
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field


class RoutingRequest(BaseModel):
    """Request to get routing candidates"""
    source_country: str = Field(..., min_length=2, max_length=2)
    dest_country: str = Field(..., min_length=2, max_length=2)
    source_currency: str = Field(..., min_length=3, max_length=3)
    dest_currency: str = Field(..., min_length=3, max_length=3)
    channel_code: str = Field(..., min_length=1, max_length=100)
    amount: float = Field(..., gt=0)
    user_segment: Optional[str] = "STANDARD"
    partner_id: Optional[str] = None


class ConstraintsResponse(BaseModel):
    """Amount constraints for a PSP"""
    min_amount: Optional[float]
    max_amount: Optional[float]


class FeeDetailsResponse(BaseModel):
    """Fee details for a PSP"""
    type: str
    flat: Optional[float] = None
    percent: Optional[float] = None
    min_fee: Optional[float] = None
    max_fee: Optional[float] = None


class CandidateResponse(BaseModel):
    """Individual PSP candidate with configuration"""
    psp_id: str
    priority: int
    weight: int
    constraints: ConstraintsResponse
    fees: Optional[FeeDetailsResponse] = None
    metadata: Optional[Dict[str, Any]] = None


class CorridorInfoResponse(BaseModel):
    """Corridor information"""
    id: str
    status: str


class ChannelInfoResponse(BaseModel):
    """Channel information"""
    id: str
    description: Optional[str] = None


class RoutingResponse(BaseModel):
    """Response with routing candidates"""
    corridor: CorridorInfoResponse
    channel: ChannelInfoResponse
    candidates: List[CandidateResponse]
