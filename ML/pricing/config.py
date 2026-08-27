"""
Pricing Pipeline — Central Configuration.

All settings are loaded from environment variables / .env file.
"""

import os
from pathlib import Path
from pydantic_settings import BaseSettings
from pydantic import Field


# ── Paths ────────────────────────────────────────────────────────────────────

# Root of the pricing module
PRICING_ROOT = Path(__file__).resolve().parent

# Runtime data directory (gitignored)
DATA_DIR = PRICING_ROOT / "data"
BENCHMARK_PRODUCTS_FILE = DATA_DIR / "benchmark_products.json"
BENCHMARK_IMAGES_DIR = DATA_DIR / "benchmark_images"
PIPELINE_LOG_FILE = DATA_DIR / "pipeline_runs.log"

# ChromaDB persistent storage
CHROMADB_DIR = PRICING_ROOT / "chroma_db"

# Reference prices from the parent ML folder
REFERENCE_PRICES_FILE = PRICING_ROOT.parent / "reference_prices.json"


class Settings(BaseSettings):
    """
    Application settings loaded from environment variables.

    Create a .env file in the project root with these values,
    or export them in your shell.
    """

    # ── API Keys ─────────────────────────────────────────────────────────
    gemini_api_key: str = Field(
        default="",
        description="Google Gemini API key for embeddings and LLM pricing.",
    )

    # ── Model Configuration ──────────────────────────────────────────────
    embedding_model: str = Field(
        default="gemini-embedding-001",
        description="Gemini multimodal embedding model name.",
    )
    llm_model: str = Field(
        default="gemini-3.6-flash",
        description="Gemini LLM model for price calculation.",
    )

    # ── ChromaDB ─────────────────────────────────────────────────────────
    chromadb_path: str = Field(
        default=str(CHROMADB_DIR),
        description="Path for ChromaDB persistent storage.",
    )
    chromadb_collection: str = Field(
        default="benchmark_products",
        description="ChromaDB collection name for benchmark embeddings.",
    )

    # ── Scraping ─────────────────────────────────────────────────────────
    scrape_categories: list[str] = Field(
        default=[
            "pottery",
            "textiles",
            "jewelry",
            "woodwork",
            "handloom saree",
            "block print",
            "brass handicraft",
            "jute craft",
            "leather craft",
            "bamboo craft",
        ],
        description="Product categories to scrape across platforms.",
    )
    scrape_max_products_per_source: int = Field(
        default=250,
        description="Maximum products to scrape per platform per run.",
    )
    scrape_request_timeout: int = Field(
        default=15,
        description="HTTP request timeout in seconds for scrapers.",
    )
    scrape_request_delay: float = Field(
        default=1.5,
        description="Delay between HTTP requests in seconds (rate limiting).",
    )

    # ── Embedding ────────────────────────────────────────────────────────
    embedding_batch_size: int = Field(
        default=10,
        description="Number of products to embed in one batch.",
    )
    embedding_retry_attempts: int = Field(
        default=3,
        description="Number of retry attempts for failed embedding requests.",
    )

    # ── Pricing LLM ─────────────────────────────────────────────────────
    pricing_top_k: int = Field(
        default=5,
        description="Number of similar benchmark products to retrieve for pricing.",
    )

    model_config = {
        "env_file": str(PRICING_ROOT.parents[1] / ".env"),
        "env_file_encoding": "utf-8",
        "extra": "ignore",
    }


def get_settings() -> Settings:
    """Return a cached Settings instance."""
    return Settings()


def ensure_data_dirs() -> None:
    """Create runtime data directories if they don't exist."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    BENCHMARK_IMAGES_DIR.mkdir(parents=True, exist_ok=True)
    Path(get_settings().chromadb_path).mkdir(parents=True, exist_ok=True)
