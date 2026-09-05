"""
Pydantic Schemas for Request/Response validation.

Designed for full compatibility with Flutter Dart models:
- Product model (product.dart)
- PriceSuggestion model (pricing_service.dart)
- AiListingSuggestion (speech_service.dart)
- ArtisanProfile (user_profile.dart)
"""

from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, Field, ConfigDict


# ── Artisan Schemas ─────────────────────────────────────────────────────────


class ArtisanRegisterRequest(BaseModel):
    name: str = Field(..., description="Artisan full name")
    phone: str = Field(..., description="10-digit mobile number")
    craft_type: str = Field(..., description="Primary craft category")
    location_cluster: str = Field(..., description="Artisan cluster / town location")
    state: Optional[str] = Field(default="", description="State / Region")
    experience_years: Optional[str] = Field(default=None, description="Craft experience in years")
    pehchan_id: Optional[str] = Field(default=None, description="Pehchan card / Artisan ID")
    preferred_language: Optional[str] = Field(default="en", description="Preferred app language")


class ArtisanLoginRequest(BaseModel):
    phone: str = Field(..., description="10-digit mobile number")


class OtpVerifyRequest(BaseModel):
    phone: str = Field(..., description="10-digit mobile number")
    otp: str = Field(..., description="6-digit OTP code")


class ArtisanProfileResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    phone: str
    craft_type: str
    location_cluster: str
    state: str
    experience_years: Optional[str] = None
    pehchan_id: Optional[str] = None
    preferred_language: str
    created_at: datetime


# ── Product Schemas ─────────────────────────────────────────────────────────


class ProductBase(BaseModel):
    title: str = Field(..., description="English product title")
    title_hi: Optional[str] = Field(default="", description="Hindi product title")
    description: str = Field(..., description="English product description")
    description_hi: Optional[str] = Field(default="", description="Hindi product description")
    price: float = Field(..., ge=0.0, description="Selling price in INR")
    image_url: str = Field(..., description="URL or local path to product image")
    category: str = Field(default="General", description="Craft category")
    tags: List[str] = Field(default_factory=list, description="Search and catalog tags")
    status: str = Field(default="live", description="Status: live, draft, archived")


class ProductCreate(ProductBase):
    id: Optional[str] = Field(default=None, description="Optional custom ID (e.g. from offline queue)")
    artisan_id: Optional[str] = Field(default=None, description="Owner artisan ID")
    created_at: Optional[datetime] = Field(default=None)


class ProductUpdate(BaseModel):
    title: Optional[str] = None
    title_hi: Optional[str] = None
    description: Optional[str] = None
    description_hi: Optional[str] = None
    price: Optional[float] = None
    image_url: Optional[str] = None
    category: Optional[str] = None
    tags: Optional[List[str]] = None
    status: Optional[str] = None


class ProductResponse(ProductBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    artisan_id: Optional[str] = None
    created_at: datetime
    updated_at: Optional[datetime] = None


class ProductSyncBatch(BaseModel):
    """Batch payload sent during offline sync drain."""
    products: List[ProductCreate]


class ProductSyncResponse(BaseModel):
    synced_count: int
    products: List[ProductResponse]


# ── Pricing Schemas ─────────────────────────────────────────────────────────


class CostInputsSchema(BaseModel):
    materials: float = Field(default=0.0, ge=0, description="Raw material cost in INR")
    labor_hours: float = Field(default=0.0, ge=0, description="Hours of labor invested")
    hourly_rate: float = Field(default=50.0, ge=0, description="Hourly wage rate in INR")
    transport: float = Field(default=0.0, ge=0, description="Transport/shipping cost in INR")
    overhead: float = Field(default=0.0, ge=0, description="Miscellaneous overhead in INR")


class PriceSuggestRequest(BaseModel):
    """
    Pricing suggestion request payload.
    Supports both naming conventions (Flutter camelCase/snake_case).
    """
    description: str = Field(..., description="Artisan product description")
    category: Optional[str] = Field(default=None, description="Product craft category")
    image_url: Optional[str] = Field(default=None, description="URL or path to product image")
    
    # Cost Breakdown
    raw_material_cost: Optional[float] = Field(default=None, ge=0)
    materials: Optional[float] = Field(default=None, ge=0)
    
    labor_hours: Optional[float] = Field(default=None, ge=0)
    
    hourly_wage: Optional[float] = Field(default=None, ge=0)
    hourly_rate: Optional[float] = Field(default=None, ge=0)
    
    transport: Optional[float] = Field(default=0.0, ge=0)
    overhead: Optional[float] = Field(default=0.0, ge=0)

    tags: Optional[List[str]] = Field(default_factory=list)

    def to_cost_inputs(self) -> CostInputsSchema:
        """Normalize cost inputs from various field aliases."""
        mat = self.materials if self.materials is not None else (self.raw_material_cost or 0.0)
        hours = self.labor_hours or 0.0
        rate = self.hourly_rate if self.hourly_rate is not None else (self.hourly_wage or 50.0)
        return CostInputsSchema(
            materials=mat,
            labor_hours=hours,
            hourly_rate=rate,
            transport=self.transport or 0.0,
            overhead=self.overhead or 0.0,
        )


class ComparableProductSchema(BaseModel):
    id: str
    title: str
    selling_price: float
    category: str
    source_platform: str
    similarity_score: float
    product_url: Optional[str] = None


class PriceSuggestResponse(BaseModel):
    """
    Structured pricing recommendation compatible with Flutter PriceSuggestion model.
    """
    suggested_price: float = Field(description="Primary suggested market price in INR")
    min_price: float = Field(description="Lower bound of suggested price range")
    max_price: float = Field(description="Upper bound of suggested price range")
    floor_price: float = Field(description="Calculated cost floor (materials + labor)")
    confidence_score: float = Field(description="Confidence (0.0 - 1.0)")
    market_position: str = Field(description="Positioning: budget, mid-range, premium, luxury")
    reasoning: str = Field(description="English reasoning for the suggested price")
    reasoning_hi: str = Field(description="Hindi reasoning for text-to-speech readback")
    comparable_products: List[ComparableProductSchema] = Field(default_factory=list)


# ── AI Cataloger & Audio Schemas ────────────────────────────────────────────


class AudioTranscribeResponse(BaseModel):
    transcript: str
    language_code: str
    detected_language: Optional[str] = None
    duration_seconds: Optional[float] = None
    provider: Optional[str] = "whisper"
    is_fallback: bool = False
    status: str = "completed"


class ListingGenerateRequest(BaseModel):
    transcript: str
    language_code: str = "hi"
    category_hint: Optional[str] = None
    image_url: Optional[str] = None


class ListingGenerateResponse(BaseModel):
    title_en: str
    title_hi: str
    description_en: str
    description_hi: str
    category: str
    tags: List[str]


class ImageEnhanceResponse(BaseModel):
    original_url: str
    enhanced_url: str
    status: str = "success"


class VoiceToProductResponse(BaseModel):
    """
    Unified result for end-to-end voice pipeline:
    audio -> transcript -> bilingual listing -> pricing recommendation -> product draft.
    """
    transcript: str
    language_code: str
    title_en: str
    title_hi: str
    description_en: str
    description_hi: str
    category: str
    tags: List[str]
    pricing: PriceSuggestResponse
    audio_url: Optional[str] = None
    image_url: Optional[str] = None
    product_draft: ProductCreate
    status: str = "completed"


class VoiceGlossaryResponse(BaseModel):
    """Craft glossary lookup response."""
    category: Optional[str] = None
    total_terms: int
    terms: List[str]
    categories: List[str]


# ── Social Media Helper Schemas ──────────────────────────────────────────────


class SocialDraftRequest(BaseModel):
    """
    Request body for generating a social-media caption + hashtags for a
    persisted listing.  The listing_id is provided in the URL path.
    """

    image_url: str = Field(..., description="URL of the product image to use for the caption")
    title: Optional[str] = Field(default="", description="Listing title (English)")
    category: Optional[str] = Field(default="", description="Craft category")
    materials: Optional[List[str]] = Field(default_factory=list, description="Materials used")
    description: Optional[str] = Field(default="", description="Listing description")
    tone: Optional[str] = Field(default="warm and authentic", description="Caption tone (warm | playful | minimal)")
    locale: Optional[str] = Field(default="en-US", description="BCP-47 locale code for caption language")
    source: str = Field(default="catalogue", description="Entry-point source: add_flow | catalogue")


class SocialDraftUnsavedRequest(SocialDraftRequest):
    """
    Same as SocialDraftRequest but for an add-flow listing that hasn't been
    saved to the DB yet.  The draft_key matches AddProductDraft.draftId on
    the Flutter side and acts as the upsert key instead of listing_id.
    """

    draft_key: str = Field(..., description="Client-side draft ID from the add-product flow")


class SocialDraftSaveRequest(BaseModel):
    """Body used when the user saves (possibly edited) caption + hashtags."""

    caption: str = Field(..., description="Caption text (may be user-edited)")
    hashtags: List[str] = Field(..., description="Hashtag list (may be user-edited)")
    edited_by_user: bool = Field(default=True, description="Whether the user modified the AI output")


class SocialDraftResponse(BaseModel):
    """Response from generate and save endpoints."""

    draft_id: str = Field(description="UUID of the persisted social_drafts row")
    caption: str
    hashtags: List[str]
