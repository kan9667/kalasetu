"""
Pydantic Schemas for Request/Response validation.

Designed for full compatibility with Flutter Dart models:
- Product model (product.dart)
- PriceSuggestion model (pricing_service.dart)
- AiListingSuggestion (speech_service.dart)
"""

from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, Field, ConfigDict


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
    status: str = Field(default="live", description="Status: live, pendingSync, draft")


class ProductCreate(ProductBase):
    id: Optional[str] = Field(default=None, description="Optional custom ID (e.g. from offline queue)")
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

