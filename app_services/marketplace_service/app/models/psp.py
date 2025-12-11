"""PSP (Payment Service Provider) model"""
from sqlalchemy import Column, String, Enum as SQLEnum, JSON, DateTime
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
import enum
from ..database import Base


class PSPStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"
    SANDBOX = "SANDBOX"


class PSPType(str, enum.Enum):
    CARD = "CARD"
    BANK = "BANK"
    WALLET = "WALLET"
    CASH = "CASH"
    BLOCKCHAIN = "BLOCKCHAIN"
    MIXED = "MIXED"


class PSP(Base):
    """Payment Service Provider"""
    __tablename__ = "psps"

    id = Column(String(100), primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    type = Column(SQLEnum(PSPType), nullable=False)
    status = Column(SQLEnum(PSPStatus), nullable=False, default=PSPStatus.ACTIVE)
    capabilities = Column(JSON, nullable=True)  # e.g., ["payouts", "collections", "card-only"]
    regions_supported = Column(JSON, nullable=True)  # e.g., ["IN", "US", "GB"]
    metadata = Column(JSON, nullable=True)  # Additional PSP-specific configuration
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    # Relationships
    corridor_routes = relationship("CorridorRoute", back_populates="psp", cascade="all, delete-orphan")
