"""Corridor model for country-to-country payment routes"""
from sqlalchemy import Column, String, Enum as SQLEnum, DateTime
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
import enum
from ..database import Base


class CorridorStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    DISABLED = "DISABLED"
    SANDBOX = "SANDBOX"


class RoutePolicy(str, enum.Enum):
    PRIORITY = "PRIORITY"
    ROUND_ROBIN = "ROUND_ROBIN"
    COST_BASED_HINT = "COST_BASED_HINT"
    WEIGHTED = "WEIGHTED"


class Corridor(Base):
    """Payment corridor between two countries"""
    __tablename__ = "corridors"

    id = Column(String(100), primary_key=True, index=True)
    source_country = Column(String(2), nullable=False, index=True)  # ISO3166 alpha-2
    dest_country = Column(String(2), nullable=False, index=True)
    source_currency = Column(String(3), nullable=False)  # ISO4217
    dest_currency = Column(String(3), nullable=False)
    status = Column(SQLEnum(CorridorStatus), nullable=False, default=CorridorStatus.ACTIVE)
    default_route_policy = Column(SQLEnum(RoutePolicy), nullable=False, default=RoutePolicy.PRIORITY)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    # Relationships
    corridor_routes = relationship("CorridorRoute", back_populates="corridor", cascade="all, delete-orphan")
