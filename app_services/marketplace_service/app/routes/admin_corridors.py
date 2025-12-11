"""Admin API routes for Corridors"""
from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.corridor import Corridor
from ..schemas.corridor import CorridorCreate, CorridorUpdate, CorridorResponse
from ..repositories.base import BaseRepository

router = APIRouter(prefix="/admin/corridors", tags=["Admin - Corridors"])


@router.post("", response_model=CorridorResponse, status_code=status.HTTP_201_CREATED)
def create_corridor(corridor: CorridorCreate, db: Session = Depends(get_db)):
    """Create a new corridor"""
    repo = BaseRepository(Corridor, db)
    
    existing = repo.get(corridor.id)
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Corridor with id '{corridor.id}' already exists"
        )
    
    return repo.create(corridor.model_dump())


@router.get("", response_model=List[CorridorResponse])
def list_corridors(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    """List all corridors"""
    repo = BaseRepository(Corridor, db)
    return repo.get_all(skip=skip, limit=limit)


@router.get("/{corridor_id}", response_model=CorridorResponse)
def get_corridor(corridor_id: str, db: Session = Depends(get_db)):
    """Get a specific corridor"""
    repo = BaseRepository(Corridor, db)
    corridor = repo.get(corridor_id)
    if not corridor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Corridor with id '{corridor_id}' not found"
        )
    return corridor


@router.put("/{corridor_id}", response_model=CorridorResponse)
def update_corridor(corridor_id: str, corridor: CorridorUpdate, db: Session = Depends(get_db)):
    """Update a corridor"""
    repo = BaseRepository(Corridor, db)
    update_data = corridor.model_dump(exclude_unset=True)
    
    updated = repo.update(corridor_id, update_data)
    if not updated:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Corridor with id '{corridor_id}' not found"
        )
    return updated


@router.delete("/{corridor_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_corridor(corridor_id: str, db: Session = Depends(get_db)):
    """Delete a corridor"""
    repo = BaseRepository(Corridor, db)
    success = repo.delete(corridor_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Corridor with id '{corridor_id}' not found"
        )
