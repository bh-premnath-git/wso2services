"""Admin API routes for Channels"""
from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.channel import Channel
from ..schemas.channel import ChannelCreate, ChannelUpdate, ChannelResponse
from ..repositories.base import BaseRepository

router = APIRouter(prefix="/admin/channels", tags=["Admin - Channels"])


@router.post("", response_model=ChannelResponse, status_code=status.HTTP_201_CREATED)
def create_channel(channel: ChannelCreate, db: Session = Depends(get_db)):
    """Create a new channel"""
    repo = BaseRepository(Channel, db)
    
    existing = repo.get(channel.id)
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Channel with id '{channel.id}' already exists"
        )
    
    return repo.create(channel.model_dump())


@router.get("", response_model=List[ChannelResponse])
def list_channels(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    """List all channels"""
    repo = BaseRepository(Channel, db)
    return repo.get_all(skip=skip, limit=limit)


@router.get("/{channel_id}", response_model=ChannelResponse)
def get_channel(channel_id: str, db: Session = Depends(get_db)):
    """Get a specific channel"""
    repo = BaseRepository(Channel, db)
    channel = repo.get(channel_id)
    if not channel:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Channel with id '{channel_id}' not found"
        )
    return channel


@router.put("/{channel_id}", response_model=ChannelResponse)
def update_channel(channel_id: str, channel: ChannelUpdate, db: Session = Depends(get_db)):
    """Update a channel"""
    repo = BaseRepository(Channel, db)
    update_data = channel.model_dump(exclude_unset=True)
    
    updated = repo.update(channel_id, update_data)
    if not updated:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Channel with id '{channel_id}' not found"
        )
    return updated


@router.delete("/{channel_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_channel(channel_id: str, db: Session = Depends(get_db)):
    """Delete a channel"""
    repo = BaseRepository(Channel, db)
    success = repo.delete(channel_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Channel with id '{channel_id}' not found"
        )
