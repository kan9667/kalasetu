"""
SQLAlchemy Database Models for KalaSetu.

Core tables:
  - ArtisanDB: Registered artisan profiles (phone-verified owners).
  - ProductDB: Product catalog listings owned by artisans.
  - MediaAssetDB: Validated, server-owned immutable media assets.
  - OtpChallengeDB: Cryptographic challenge records for phone OTP verification.
  - SocialDraftDB: AI-generated social media drafts.
"""

import enum
import json
from datetime import datetime
from sqlalchemy import Column, String, Float, Integer, DateTime, Text, ForeignKey, Boolean, UniqueConstraint
from sqlalchemy.orm import relationship
from ..database import Base


class ProductStatus(str, enum.Enum):
    DRAFT = "draft"
    AWAITING_APPROVAL = "awaiting_approval"
    APPROVED = "approved"
    PUBLISHED = "published"
    SUPERSEDED = "superseded"
    REJECTED = "rejected"
    LEGACY_UNVERIFIED = "legacy_unverified"
    ARCHIVED = "archived"
    DELETED = "deleted"
    PENDING_APPROVAL_SYNC = "pending_approval_sync"


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
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationship: one artisan owns many products
    products = relationship("ProductDB", back_populates="artisan", lazy="dynamic")
    media_assets = relationship("MediaAssetDB", back_populates="artisan", lazy="dynamic")


class OtpChallengeDB(Base):
    """Cryptographic challenge record for phone OTP verification."""

    __tablename__ = "otp_challenges"

    id = Column(String(64), primary_key=True, index=True)
    phone = Column(String(15), nullable=False, index=True)
    otp_hash = Column(String(128), nullable=False)
    salt = Column(String(32), nullable=False)
    expires_at = Column(DateTime, nullable=False)
    attempts = Column(Integer, default=0, nullable=False)
    max_attempts = Column(Integer, default=3, nullable=False)
    used = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)


class MediaAssetDB(Base):
    """Validated, server-owned immutable media asset."""

    __tablename__ = "media_assets"

    id = Column(String(64), primary_key=True, index=True)
    artisan_id = Column(
        String(64),
        ForeignKey("artisans.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    file_path = Column(String(512), nullable=False)
    file_url = Column(String(512), nullable=False)
    mime_type = Column(String(64), nullable=False)
    byte_size = Column(Integer, nullable=False)
    sha256_checksum = Column(String(64), nullable=False)
    processing_provenance = Column(String(128), default="raw_upload")
    source_media_id = Column(
        String(64),
        ForeignKey("media_assets.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    is_degraded = Column(Boolean, default=False, nullable=False)
    degraded_reason = Column(String(255), nullable=True)
    status = Column(String(32), default="ready", index=True)  # ready, pending, failed
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    artisan = relationship("ArtisanDB", back_populates="media_assets")


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

    # Dual-read price fields: legacy float column mapped explicitly to avoid shadowing
    legacy_price = Column("price", Float, nullable=True, default=0.0)
    price_paise = Column(Integer, nullable=False, default=0)

    # Cost breakdown and floor price in integer paise
    floor_price_paise = Column(Integer, nullable=False, default=0)
    materials_paise = Column(Integer, nullable=False, default=0)
    labor_hours = Column(Float, nullable=False, default=0.0)
    hourly_rate_paise = Column(Integer, nullable=False, default=5000)  # default ₹50/hr
    transport_paise = Column(Integer, nullable=False, default=0)
    overhead_paise = Column(Integer, nullable=False, default=0)

    # Media tracking: verified server-owned media asset
    image_url = Column(String(512), default="")
    media_id = Column(
        String(64),
        ForeignKey("media_assets.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    category = Column(String(128), default="General", index=True)
    tags = Column(Text, default="[]")  # JSON encoded list of strings

    # Lifecycle & status: default must be 'draft', never 'live'
    status = Column(String(32), default=ProductStatus.DRAFT.value, index=True, nullable=False)

    # Approval and revision metadata
    revision = Column(Integer, default=1, nullable=False)
    approved_revision = Column(Integer, nullable=True)
    approved_at = Column(DateTime, nullable=True)
    approved_by_artisan_id = Column(String(64), nullable=True)
    published_at = Column(DateTime, nullable=True)
    content_hash = Column(String(64), default="", nullable=False)
    is_deleted = Column(Boolean, default=False, nullable=False, index=True)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    artisan = relationship("ArtisanDB", back_populates="products")
    media_asset = relationship("MediaAssetDB", lazy="joined")
    revisions = relationship(
        "ProductRevisionDB",
        back_populates="product",
        cascade="all, delete-orphan",
        order_by="ProductRevisionDB.revision.desc()",
    )

    @property
    def tags_list(self) -> list[str]:
        """Deserialize tags from JSON."""
        try:
            return json.loads(self.tags) if self.tags else []
        except Exception:
            return []

    # Non-shadowing rupee conversion helpers
    def get_price_rupees(self) -> float:
        if self.price_paise is not None and self.price_paise > 0:
            return round(self.price_paise / 100.0, 2)
        if self.legacy_price is not None:
            return round(float(self.legacy_price), 2)
        return 0.0

    def set_price_rupees(self, val: float):
        cents = int(round(float(val) * 100))
        self.price_paise = cents
        self.legacy_price = float(val)

    def get_floor_price_rupees(self) -> float:
        if self.floor_price_paise is not None:
            return round(self.floor_price_paise / 100.0, 2)
        return 0.0

    def set_floor_price_rupees(self, val: float):
        self.floor_price_paise = int(round(float(val) * 100))

    def get_materials_rupees(self) -> float:
        return round((self.materials_paise or 0) / 100.0, 2)

    def set_materials_rupees(self, val: float):
        self.materials_paise = int(round(float(val) * 100))

    def get_hourly_rate_rupees(self) -> float:
        return round((self.hourly_rate_paise or 5000) / 100.0, 2)

    def set_hourly_rate_rupees(self, val: float):
        self.hourly_rate_paise = int(round(float(val) * 100))

    def get_transport_rupees(self) -> float:
        return round((self.transport_paise or 0) / 100.0, 2)

    def set_transport_rupees(self, val: float):
        self.transport_paise = int(round(float(val) * 100))

    def get_overhead_rupees(self) -> float:
        return round((self.overhead_paise or 0) / 100.0, 2)

    def set_overhead_rupees(self, val: float):
        self.overhead_paise = int(round(float(val) * 100))


class SocialDraftDB(Base):
    """
    AI-generated social media caption + hashtag draft for a product listing.

    Upsert key:
      - Catalogue flow:  (listing_id, image_url)
      - Add-product flow: (draft_key, image_url)
    """

    __tablename__ = "social_drafts"

    id = Column(String(64), primary_key=True, index=True)
    artisan_id = Column(
        String(64),
        ForeignKey("artisans.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    listing_id = Column(
        String(64),
        ForeignKey("products.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    # Used when the listing hasn't been saved yet (add-flow).
    # Matches AddProductDraft.draftId on the Flutter side.
    draft_key = Column(String(128), nullable=True, index=True)
    image_url = Column(String(512), nullable=False)
    caption = Column(Text, default="")
    hashtags = Column(Text, default="[]")  # JSON-encoded list of strings
    # Target channel: 'whatsapp', 'instagram', or 'facebook'
    channel = Column(String(32), default="instagram", index=True)
    # Source of the generation: 'add_flow' or 'catalogue'
    source = Column(String(32), default="catalogue")
    # True once the user has manually edited caption / hashtags after generation
    edited_by_user = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    @property
    def hashtags_list(self) -> list[str]:
        """Deserialize hashtags from JSON."""
        try:
            return json.loads(self.hashtags) if self.hashtags else []
        except Exception:
            return []


class ProductRevisionDB(Base):
    """Immutable server-owned snapshot of an approved product revision."""

    __tablename__ = "product_revisions"
    __table_args__ = (
        UniqueConstraint("product_id", "revision", name="uq_product_revisions_product_id_revision"),
    )

    id = Column(String(64), primary_key=True, index=True)  # rev_{uuid.uuid4().hex[:12]}
    product_id = Column(
        String(64),
        ForeignKey("products.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    artisan_id = Column(
        String(64),
        ForeignKey("artisans.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    revision = Column(Integer, nullable=False)
    title = Column(String(255), nullable=False)
    title_hi = Column(String(255), default="")
    description = Column(Text, default="")
    description_hi = Column(Text, default="")

    price_paise = Column(Integer, nullable=False)
    floor_price_paise = Column(Integer, nullable=False)
    category = Column(String(128), nullable=False)
    tags = Column(Text, default="[]")

    media_id = Column(
        String(64),
        ForeignKey("media_assets.id"),
        nullable=False,
        index=True,
    )
    media_checksum = Column(String(64), nullable=False)
    media_mime_type = Column(String(64), nullable=False)
    media_byte_size = Column(Integer, nullable=False)
    public_media_url = Column(String(512), nullable=False)

    content_hash = Column(String(64), nullable=False)
    approved_by_artisan_id = Column(
        String(64),
        ForeignKey("artisans.id"),
        nullable=False,
    )
    approved_at = Column(DateTime, nullable=False)
    published_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    product = relationship("ProductDB", back_populates="revisions")
    media_asset = relationship("MediaAssetDB", lazy="joined")

    @property
    def tags_list(self) -> list[str]:
        try:
            return json.loads(self.tags) if self.tags else []
        except Exception:
            return []

    def get_price_rupees(self) -> float:
        return round(self.price_paise / 100.0, 2)


class IdempotencyRecordDB(Base):
    """Crash-safe transactional idempotency record."""

    __tablename__ = "idempotency_records"
    __table_args__ = (
        UniqueConstraint("artisan_id", "endpoint", "idempotency_key", name="uq_idempotency_artisan_endpoint_key"),
    )

    id = Column(String(64), primary_key=True, index=True)  # idem_{uuid.uuid4().hex[:12]}
    artisan_id = Column(
        String(64),
        ForeignKey("artisans.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    idempotency_key = Column(String(128), nullable=False, index=True)
    endpoint = Column(String(256), nullable=False, index=True)
    request_hash = Column(String(64), nullable=False)
    status = Column(String(32), default="in_progress", nullable=False)  # in_progress, completed
    lease_expires_at = Column(DateTime, nullable=False)
    response_status_code = Column(Integer, nullable=True)
    response_body = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
