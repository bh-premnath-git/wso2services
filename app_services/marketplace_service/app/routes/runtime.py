"""Runtime API routes for orchestrator"""
from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..schemas.runtime import (
    RoutingRequest,
    RoutingResponse,
    CandidateResponse,
    ConstraintsResponse,
    FeeDetailsResponse,
    CorridorInfoResponse,
    ChannelInfoResponse
)
from ..repositories.routing import RoutingRepository

router = APIRouter(prefix="/runtime", tags=["Runtime"])


@router.post("/routing/candidates", response_model=RoutingResponse)
def get_routing_candidates(request: RoutingRequest, db: Session = Depends(get_db)):
    """
    Get routing candidates for a payment request.
    This is the main endpoint used by the orchestrator.
    """
    repo = RoutingRepository(db)
    
    # Find corridor
    corridor = repo.get_corridor(
        request.source_country,
        request.dest_country,
        request.source_currency,
        request.dest_currency
    )
    
    if not corridor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=(
                f"No corridor found for {request.source_country}->{request.dest_country} "
                f"({request.source_currency}->{request.dest_currency})"
            )
        )
    
    if corridor.status != "ACTIVE":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Corridor {corridor.id} is not active (status: {corridor.status})"
        )
    
    # Find channel
    channel = repo.get_channel_by_code(request.channel_code)
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Channel '{request.channel_code}' not found"
        )
    
    # Get corridor routes that match criteria
    routes = repo.get_corridor_routes(corridor.id, channel.id, request.amount)
    
    if not routes:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No active routes found for corridor {corridor.id} and channel {channel.code}"
        )
    
    # Build candidate responses
    candidates = []
    for route in routes:
        # Get active fee
        fee_data = None
        active_fee = repo.get_active_fee(route.id)
        if active_fee:
            fee_data = FeeDetailsResponse(
                type=active_fee.fee_type.value,
                flat=active_fee.value_flat,
                percent=active_fee.value_percent,
                min_fee=active_fee.min_fee,
                max_fee=active_fee.max_fee
            )
        
        candidate = CandidateResponse(
            psp_id=route.psp_id,
            priority=route.priority,
            weight=route.weight,
            constraints=ConstraintsResponse(
                min_amount=route.min_amount,
                max_amount=route.max_amount
            ),
            fees=fee_data,
            metadata=route.metadata
        )
        candidates.append(candidate)
    
    return RoutingResponse(
        corridor=CorridorInfoResponse(
            id=corridor.id,
            status=corridor.status.value
        ),
        channel=ChannelInfoResponse(
            id=channel.id,
            description=channel.description
        ),
        candidates=candidates
    )


@router.get("/corridors", response_model=List[CorridorInfoResponse])
def list_corridors(db: Session = Depends(get_db)):
    """List all active corridors for customer-facing apps"""
    repo = RoutingRepository(db)
    corridors = repo.get_all_corridors()
    
    return [
        CorridorInfoResponse(id=c.id, status=c.status.value)
        for c in corridors
    ]


@router.get("/channels", response_model=List[ChannelInfoResponse])
def list_channels(db: Session = Depends(get_db)):
    """List all consumer-visible channels"""
    repo = RoutingRepository(db)
    channels = repo.get_all_channels()
    
    return [
        ChannelInfoResponse(id=c.id, description=c.description)
        for c in channels
    ]
