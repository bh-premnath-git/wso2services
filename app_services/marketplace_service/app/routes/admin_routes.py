"""Admin API routes for Corridor Routes"""
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.corridor_route import CorridorRoute
from ..schemas.corridor_route import CorridorRouteCreate, CorridorRouteUpdate, CorridorRouteResponse
from ..repositories.base import BaseRepository

router = APIRouter(prefix="/admin/routes", tags=["Admin - Routes"])


@router.post("", response_model=CorridorRouteResponse, status_code=status.HTTP_201_CREATED)
def create_route(route: CorridorRouteCreate, db: Session = Depends(get_db)):
    """Create a new corridor route"""
    repo = BaseRepository(CorridorRoute, db)
    
    existing = repo.get(route.id)
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Route with id '{route.id}' already exists"
        )
    
    return repo.create(route.model_dump())


@router.get("", response_model=List[CorridorRouteResponse])
def list_routes(
    corridor_id: Optional[str] = Query(None),
    channel_id: Optional[str] = Query(None),
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db)
):
    """List corridor routes with optional filtering"""
    query = db.query(CorridorRoute)
    
    if corridor_id:
        query = query.filter(CorridorRoute.corridor_id == corridor_id)
    if channel_id:
        query = query.filter(CorridorRoute.channel_id == channel_id)
    
    return query.offset(skip).limit(limit).all()


@router.get("/{route_id}", response_model=CorridorRouteResponse)
def get_route(route_id: str, db: Session = Depends(get_db)):
    """Get a specific corridor route"""
    repo = BaseRepository(CorridorRoute, db)
    route = repo.get(route_id)
    if not route:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Route with id '{route_id}' not found"
        )
    return route


@router.put("/{route_id}", response_model=CorridorRouteResponse)
def update_route(route_id: str, route: CorridorRouteUpdate, db: Session = Depends(get_db)):
    """Update a corridor route"""
    repo = BaseRepository(CorridorRoute, db)
    update_data = route.model_dump(exclude_unset=True)
    
    updated = repo.update(route_id, update_data)
    if not updated:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Route with id '{route_id}' not found"
        )
    return updated


@router.delete("/{route_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_route(route_id: str, db: Session = Depends(get_db)):
    """Delete a corridor route"""
    repo = BaseRepository(CorridorRoute, db)
    success = repo.delete(route_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Route with id '{route_id}' not found"
        )
