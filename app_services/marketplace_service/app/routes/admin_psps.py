"""Admin API routes for PSPs"""
from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.psp import PSP
from ..schemas.psp import PSPCreate, PSPUpdate, PSPResponse
from ..repositories.base import BaseRepository

router = APIRouter(prefix="/admin/psps", tags=["Admin - PSPs"])


@router.post("", response_model=PSPResponse, status_code=status.HTTP_201_CREATED)
def create_psp(psp: PSPCreate, db: Session = Depends(get_db)):
    """Create a new PSP"""
    repo = BaseRepository(PSP, db)
    
    # Check if PSP already exists
    existing = repo.get(psp.id)
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"PSP with id '{psp.id}' already exists"
        )
    
    return repo.create(psp.model_dump())


@router.get("", response_model=List[PSPResponse])
def list_psps(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    """List all PSPs"""
    repo = BaseRepository(PSP, db)
    return repo.get_all(skip=skip, limit=limit)


@router.get("/{psp_id}", response_model=PSPResponse)
def get_psp(psp_id: str, db: Session = Depends(get_db)):
    """Get a specific PSP"""
    repo = BaseRepository(PSP, db)
    psp = repo.get(psp_id)
    if not psp:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"PSP with id '{psp_id}' not found"
        )
    return psp


@router.put("/{psp_id}", response_model=PSPResponse)
def update_psp(psp_id: str, psp: PSPUpdate, db: Session = Depends(get_db)):
    """Update a PSP"""
    repo = BaseRepository(PSP, db)
    
    # Filter out None values
    update_data = psp.model_dump(exclude_unset=True)
    
    updated = repo.update(psp_id, update_data)
    if not updated:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"PSP with id '{psp_id}' not found"
        )
    return updated


@router.delete("/{psp_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_psp(psp_id: str, db: Session = Depends(get_db)):
    """Delete a PSP"""
    repo = BaseRepository(PSP, db)
    success = repo.delete(psp_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"PSP with id '{psp_id}' not found"
        )
