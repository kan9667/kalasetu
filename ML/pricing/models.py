"""
Pricing Pipeline — Data Models.

All structured data types used across scrapers, embeddings, artisan processing,
and LLM pricing are defined here for consistency.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


# ── Enums ────────────────────────────────────────────────────────────────────


class SourcePlatform(str, Enum):
    """Platforms from which benchmark products are scraped."""

    AMAZON_KARIGAR = "amazon_karigar"
    FABINDIA = "fabindia"
    ETSY_INDIA = "etsy_india"
    OKHAI = "okhai"
    SEED_DATA = "seed_data"


class PipelineStage(str, Enum):
    """Pipeline execution stages for logging."""

    SCRAPING = "scraping"
    EMBEDDING = "embedding"
    INDEXING = "indexing"
    ARTISAN_PROCESSING = "artisan_processing"
    LLM_PRICING = "llm_pricing"


# ── Benchmark Products ──────────────────────────────────────────────────────


class BenchmarkProduct(BaseModel):
    """A competitor product scraped from the market or generated as seed data."""

    id: str = Field(description="Unique identifier (hash of image_url + title).")
    image_url: str = Field(description="Original image URL from the source platform.")
    local_image_path: Optional[str] = Field(
        default=None,
        description="Local file path after downloading the image.",
    )
    title: str = Field(description="Product title/name.")
    description: str = Field(default="", description="Product description text.")
    category: str = Field(description="Product category (e.g., textiles, pottery).")
    selling_price: float = Field(description="Current selling price in INR.")
    currency: str = Field(default="INR", description="Price currency code.")
    source_platform: SourcePlatform = Field(
        description="Platform this product was scraped from."
    )
    product_url: Optional[str] = Field(
        default=None, description="URL to the original product listing."
    )
    scraped_at: datetime = Field(
        default_factory=datetime.now,
        description="Timestamp when this product was scraped.",
    )

    def embedding_text(self) -> str:
        """Combine title, description, and category into a single text for embedding."""
        parts = [self.title]
        if self.description:
            parts.append(self.description)
        parts.append(f"Category: {self.category}")
        return " | ".join(parts)


# ── Similar / Retrieved Products ────────────────────────────────────────────


class SimilarProduct(BaseModel):
    """A benchmark product retrieved from the vector store with similarity score."""

    id: str
    title: str
    description: str = ""
    category: str
    selling_price: float
    source_platform: str
    similarity_score: float = Field(
        description="Cosine similarity score (0–1, higher = more similar)."
    )
    product_url: Optional[str] = None


# ── Artisan Inputs ──────────────────────────────────────────────────────────


class CostInputs(BaseModel):
    """
    Cost-based floor inputs provided by the artisan.

    The pricing engine will never suggest a price below
    (materials + labor_hours * hourly_rate + transport + overhead).
    """

    materials: float = Field(
        default=0.0, description="Raw material cost in INR.", ge=0
    )
    labor_hours: float = Field(
        default=0.0, description="Hours of labor invested.", ge=0
    )
    hourly_rate: float = Field(
        default=0.0,
        description="Artisan's hourly rate in INR (defaults to ₹50 if 0).",
        ge=0,
    )
    transport: float = Field(
        default=0.0, description="Transport/shipping cost in INR.", ge=0
    )
    overhead: float = Field(
        default=0.0, description="Miscellaneous overhead in INR.", ge=0
    )

    @property
    def cost_floor(self) -> float:
        """Calculate the minimum price that covers all costs."""
        rate = self.hourly_rate if self.hourly_rate > 0 else 50.0
        return self.materials + (self.labor_hours * rate) + self.transport + self.overhead


class ArtisanProduct(BaseModel):
    """An artisan's product submitted for pricing."""

    image_path: str = Field(description="Path to the artisan's product image.")
    description: str = Field(
        description="English description (from the cataloger pipeline)."
    )
    category: Optional[str] = Field(
        default=None, description="Product category if known."
    )
    cost_inputs: Optional[CostInputs] = Field(
        default=None, description="Cost breakdown for floor-price calculation."
    )


# ── LLM Pricing Result ──────────────────────────────────────────────────────


class PricingResult(BaseModel):
    """Structured pricing output from the LLM."""

    suggested_price: float = Field(
        description="The recommended selling price in INR."
    )
    price_range_low: float = Field(
        description="Lower bound of the suggested price range."
    )
    price_range_high: float = Field(
        description="Upper bound of the suggested price range."
    )
    cost_floor: float = Field(
        default=0.0,
        description="The calculated cost floor (never price below this).",
    )
    confidence_score: float = Field(
        description="Confidence in the suggestion (0.0–1.0).",
        ge=0.0,
        le=1.0,
    )
    reasoning: str = Field(
        description="Plain-English explanation of how the price was determined."
    )
    comparable_products: list[SimilarProduct] = Field(
        default_factory=list,
        description="The benchmark products used for comparison.",
    )
    market_position: str = Field(
        default="",
        description="Where this product sits relative to the market (e.g., 'premium', 'mid-range', 'budget').",
    )


# ── Pipeline Logging ────────────────────────────────────────────────────────


class PipelineRunLog(BaseModel):
    """Log entry for a pipeline run."""

    stage: PipelineStage
    started_at: datetime = Field(default_factory=datetime.now)
    completed_at: Optional[datetime] = None
    products_processed: int = 0
    errors: list[str] = Field(default_factory=list)
    success: bool = False
    message: str = ""
