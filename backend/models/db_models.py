"""
SQLAlchemy Database Models for KalaSetu.

Two core tables:
  - ArtisanDB: Registered artisan profiles (phone-verified owners).
  - ProductDB: Product catalog listings owned by artisans.
"""

import json
from datetime import datetime
from sqlalchemy import Column, String, Float, DateTime, Text, ForeignKey
from sqlalchemy.orm import relationship
from ..database import Base


class ArtisanDB(Base):
    """Registered artisan profile."""

    __tablename__ = "artisans"

    id = Column(String(64), primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    phone = Column(String(15), unique=True, nullable=False, index=True)
    craft_type = Column(String(128), default="")
    location_cluster = Column(String(255), default="")
    state = Column(String(128), default="")
    experience_years = Column(String(16), default="")
    pehchan_id = Column(String(64), nullable=True)
    preferred_language = Column(String(8), default="en")
    created_at = Column(DateTime, default=datetime.now)

    # Relationship: one artisan owns many products
    products = relationship("ProductDB", back_populates="artisan", lazy="dynamic")


class ProductDB(Base):
    """Product catalog item owned by an artisan."""

    __tablename__ = "products"

    id = Column(String(64), primary_key=True, index=True)
    artisan_id = Column(
        String(64),
        ForeignKey("artisans.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    title = Column(String(255), nullable=False)
    title_hi = Column(String(255), default="")
    description = Column(Text, default="")
    description_hi = Column(Text, default="")
    price = Column(Float, nullable=False, default=0.0)
    image_url = Column(String(512), default="")
    category = Column(String(128), default="General", index=True)
    tags = Column(Text, default="[]")  # JSON encoded list of strings
    status = Column(String(32), default="live", index=True)  # live, draft, archived
    created_at = Column(DateTime, default=datetime.now)
    updated_at = Column(DateTime, default=datetime.now, onupdate=datetime.now)

    # Relationship back to artisan
    artisan = relationship("ArtisanDB", back_populates="products")

    @property
    def tags_list(self) -> list[str]:
        """Deserialize tags from JSON."""
        try:
            return json.loads(self.tags) if self.tags else []
        except Exception:
            return []
