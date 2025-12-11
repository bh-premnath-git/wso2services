"""Channel/Flow Type model"""
from sqlalchemy import Column, String, Boolean, DateTime, Text
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from ..database import Base


class Channel(Base):
    """Payment channel or flow type (e.g., CARD_TO_BANK, BANK_TO_BANK)"""
    __tablename__ = "channels"

    id = Column(String(100), primary_key=True, index=True)
    code = Column(String(100), unique=True, nullable=False, index=True)
    description = Column(Text, nullable=True)
    is_consumer_visible = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    # Relationships
    corridor_routes = relationship("CorridorRoute", back_populates="channel", cascade="all, delete-orphan")
