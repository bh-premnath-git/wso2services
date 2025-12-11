"""CorridorRoute model - ties corridor + channel to PSP"""
from sqlalchemy import Column, String, Integer, Float, Enum as SQLEnum, JSON, DateTime, ForeignKey
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
import enum
from ..database import Base


class RouteStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    DISABLED = "DISABLED"
    MAINTENANCE = "MAINTENANCE"


class CorridorRoute(Base):
    """Links corridor + channel to specific PSP with routing configuration"""
    __tablename__ = "corridor_routes"

    id = Column(String(100), primary_key=True, index=True)
    corridor_id = Column(String(100), ForeignKey("corridors.id", ondelete="CASCADE"), nullable=False, index=True)
    channel_id = Column(String(100), ForeignKey("channels.id", ondelete="CASCADE"), nullable=False, index=True)
    psp_id = Column(String(100), ForeignKey("psps.id", ondelete="CASCADE"), nullable=False, index=True)
    priority = Column(Integer, nullable=False, default=1)  # 1 = highest priority
    weight = Column(Integer, nullable=False, default=100)  # For weighted random selection
    min_amount = Column(Float, nullable=True)
    max_amount = Column(Float, nullable=True)
    min_fx_margin = Column(Float, nullable=True)
    max_fx_margin = Column(Float, nullable=True)
    status = Column(SQLEnum(RouteStatus), nullable=False, default=RouteStatus.ACTIVE)
    metadata = Column(JSON, nullable=True)  # PSP-specific hints/config
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    # Relationships
    corridor = relationship("Corridor", back_populates="corridor_routes")
    channel = relationship("Channel", back_populates="corridor_routes")
    psp = relationship("PSP", back_populates="corridor_routes")
    fees = relationship("Fee", back_populates="corridor_route", cascade="all, delete-orphan")
    overrides = relationship("RouteOverride", back_populates="corridor_route", cascade="all, delete-orphan")
