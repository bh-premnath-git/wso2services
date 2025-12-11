"""RouteOverride model for segment-specific routing"""
from sqlalchemy import Column, String, Integer, Enum as SQLEnum, JSON, DateTime, ForeignKey
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
import enum
from ..database import Base


class SegmentType(str, enum.Enum):
    USER_TIER = "USER_TIER"
    PARTNER_ID = "PARTNER_ID"
    TENANT_ID = "TENANT_ID"
    RISK_BUCKET = "RISK_BUCKET"


class RouteOverride(Base):
    """Segment-specific overrides for routing configuration"""
    __tablename__ = "route_overrides"

    id = Column(String(100), primary_key=True, index=True)
    corridor_route_id = Column(String(100), ForeignKey("corridor_routes.id", ondelete="CASCADE"), nullable=False, index=True)
    segment_type = Column(SQLEnum(SegmentType), nullable=False)
    segment_value = Column(String(100), nullable=False, index=True)  # e.g., "VIP", "partner_abc"
    override_priority = Column(Integer, nullable=True)
    override_weight = Column(Integer, nullable=True)
    override_status = Column(String(50), nullable=True)
    override_metadata = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    # Relationships
    corridor_route = relationship("CorridorRoute", back_populates="overrides")
