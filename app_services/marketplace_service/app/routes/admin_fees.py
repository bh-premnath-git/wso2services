"""Admin API routes for Fees"""
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.fee import Fee
from ..schemas.fee import FeeCreate, FeeUpdate, FeeResponse
from ..repositories.base import BaseRepository

router = APIRouter(prefix="/admin/fees", tags=["Admin - Fees"])


@router.post("", response_model=FeeResponse, status_code=status.HTTP_201_CREATED)
def create_fee(fee: FeeCreate, db: Session = Depends(get_db)):
    """Create a new fee configuration"""
    repo = BaseRepository(Fee, db)
    
    existing = repo.get(fee.id)
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Fee with id '{fee.id}' already exists"
        )
    
    return repo.create(fee.model_dump())


@router.get("", response_model=List[FeeResponse])
def list_fees(
    corridor_route_id: Optional[str] = Query(None),
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db)
):
    """List fees with optional filtering"""
    query = db.query(Fee)
    
    if corridor_route_id:
        query = query.filter(Fee.corridor_route_id == corridor_route_id)
    
    return query.offset(skip).limit(limit).all()


@router.get("/{fee_id}", response_model=FeeResponse)
def get_fee(fee_id: str, db: Session = Depends(get_db)):
    """Get a specific fee"""
    repo = BaseRepository(Fee, db)
    fee = repo.get(fee_id)
    if not fee:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Fee with id '{fee_id}' not found"
        )
    return fee


@router.put("/{fee_id}", response_model=FeeResponse)
def update_fee(fee_id: str, fee: FeeUpdate, db: Session = Depends(get_db)):
    """Update a fee"""
    repo = BaseRepository(Fee, db)
    update_data = fee.model_dump(exclude_unset=True)
    
    updated = repo.update(fee_id, update_data)
    if not updated:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Fee with id '{fee_id}' not found"
        )
    return updated


@router.delete("/{fee_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_fee(fee_id: str, db: Session = Depends(get_db)):
    """Delete a fee"""
    repo = BaseRepository(Fee, db)
    success = repo.delete(fee_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Fee with id '{fee_id}' not found"
        )
