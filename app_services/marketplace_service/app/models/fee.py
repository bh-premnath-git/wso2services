"""Fee/Pricing model"""
from sqlalchemy import Column, String, Float, Enum as SQLEnum, DateTime, ForeignKey
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
import enum
from ..database import Base


class FeeType(str, enum.Enum):
    FLAT = "FLAT"
    PERCENTAGE = "PERCENTAGE"
    MIXED = "MIXED"
    FX_MARGIN = "FX_MARGIN"


class Fee(Base):
    """Pricing configuration for a corridor route"""
    __tablename__ = "fees"

    id = Column(String(100), primary_key=True, index=True)
    corridor_route_id = Column(String(100), ForeignKey("corridor_routes.id", ondelete="CASCADE"), nullable=False, index=True)
    fee_type = Column(SQLEnum(FeeType), nullable=False)
    value_flat = Column(Float, nullable=True)
    value_percent = Column(Float, nullable=True)
    min_fee = Column(Float, nullable=True)
    max_fee = Column(Float, nullable=True)
    effective_from = Column(DateTime(timezone=True), nullable=True)
    effective_to = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    # Relationships
    corridor_route = relationship("CorridorRoute", back_populates="fees")
