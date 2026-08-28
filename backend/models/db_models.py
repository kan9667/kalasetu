"""
SQLAlchemy Database Models for KalaSetu.
"""

import json
from datetime import datetime
from sqlalchemy import Column, String, Float, DateTime, Text
from ..database import Base


class ProductDB(Base):
    """Product catalog item stored in the database."""

    __tablename__ = "products"

    id = Column(String(64), primary_key=True, index=True)
    title = Column(String(255), nullable=False)
    title_hi = Column(String(255), default="")
    description = Column(Text, default="")
    description_hi = Column(Text, default="")
    price = Column(Float, nullable=False, default=0.0)
    image_url = Column(String(512), default="")
    category = Column(String(128), default="General", index=True)
    tags = Column(Text, default="[]")  # JSON encoded list of strings
    status = Column(String(32), default="live", index=True)  # live, pendingSync, draft
    created_at = Column(DateTime, default=datetime.now)
    updated_at = Column(DateTime, default=datetime.now, onupdate=datetime.now)

    @property
    def tags_list(self) -> list[str]:
        """Deserialize tags from JSON."""
        try:
            return json.loads(self.tags) if self.tags else []
        except Exception:
            return []


class PriceAuditDB(Base):
    """Audit record of AI pricing requests and recommendations."""

    __tablename__ = "price_audits"

    id = Column(String(64), primary_key=True, index=True)
    category = Column(String(128), default="")
    description = Column(Text, default="")
    materials_cost = Column(Float, default=0.0)
    labor_hours = Column(Float, default=0.0)
    hourly_rate = Column(Float, default=0.0)
    calculated_floor = Column(Float, default=0.0)
    suggested_price = Column(Float, default=0.0)
    min_price = Column(Float, default=0.0)
    max_price = Column(Float, default=0.0)
    confidence = Column(Float, default=0.0)
    market_position = Column(String(64), default="")
    reasoning = Column(Text, default="")
    reasoning_hi = Column(Text, default="")
    created_at = Column(DateTime, default=datetime.now)
