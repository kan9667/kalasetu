"""
Karigar Setu — AI-Driven Pricing Pipeline.

Public API for the pricing engine. Import from here for clean usage:

    from ML.pricing import build_benchmark_index, get_price_suggestion

Pipeline stages:
    1. Scrape benchmark products from e-commerce platforms
    2. Generate multimodal embeddings (Gemini) and store in ChromaDB
    3. Process artisan uploads → embed → retrieve comparables → LLM price
"""

from .artisan.processor import ArtisanProductProcessor
from .embeddings.build_index import build_benchmark_index
from .scrapers.runner import ScraperRunner

__all__ = [
    "build_benchmark_index",
    "get_price_suggestion",
    "run_scraper",
    "ArtisanProductProcessor",
    "ScraperRunner",
]


def run_scraper(use_seed_only: bool = False):
    """
    Run the benchmark product scrapers.

    Args:
        use_seed_only: If True, skip live scraping and use curated seed data.

    Returns:
        List of BenchmarkProduct instances.
    """
    runner = ScraperRunner(use_seed_only=use_seed_only)
    return runner.run()


def get_price_suggestion(
    image_path: str,
    description: str,
    cost_inputs: dict | None = None,
    category: str | None = None,
) -> dict:
    """
    Get an AI-powered price suggestion for an artisan's product.

    This is the main entry point — it handles the full pipeline:
    embed the artisan's product → retrieve market comparables → LLM pricing.

    Args:
        image_path: Path to the product image.
        description: English product description.
        cost_inputs: Optional cost breakdown dict with keys:
                     materials, labor_hours, hourly_rate, transport, overhead.
        category: Optional category for filtered comparable search.

    Returns:
        Dict with pricing recommendation including suggested_price,
        price_range, confidence_score, reasoning, and comparable_products.
    """
    processor = ArtisanProductProcessor()
    result = processor.process_upload(
        image_path=image_path,
        description=description,
        cost_inputs=cost_inputs,
        category=category,
    )
    return result.model_dump()
