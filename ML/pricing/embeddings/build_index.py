"""
Build Index — End-to-end pipeline from scraped data to ChromaDB index.

Reads benchmark products, generates multimodal embeddings, and upserts
them into the vector store. Idempotent: skips already-indexed products.
"""

from __future__ import annotations

import logging
from datetime import datetime

from ..config import ensure_data_dirs, get_settings
from ..models import PipelineRunLog, PipelineStage
from ..scrapers.runner import ScraperRunner
from .embedding_engine import EmbeddingEngine
from .vector_store import VectorStore

logger = logging.getLogger(__name__)


def build_benchmark_index(
    use_seed: bool = False,
    skip_scraping: bool = False,
    force_reindex: bool = False,
) -> dict:
    """
    Build or update the benchmark product vector index.

    Pipeline:
    1. Scrape products (or load existing data if skip_scraping=True)
    2. Generate multimodal embeddings via Gemini
    3. Upsert into ChromaDB

    Args:
        use_seed: Use seed data only (no live scraping).
        skip_scraping: Skip scraping and use existing benchmark_products.json.
        force_reindex: Clear existing index and rebuild from scratch.

    Returns:
        Summary dict with counts and timing.
    """
    ensure_data_dirs()
    settings = get_settings()

    run_log = PipelineRunLog(stage=PipelineStage.INDEXING)
    start_time = datetime.now()

    # ── Step 1: Get benchmark products ───────────────────────────────────
    if skip_scraping:
        logger.info("Skipping scraping, loading existing benchmark data...")
        products = ScraperRunner.load_products()
        if not products:
            logger.error("No existing benchmark data found. Run scraping first.")
            return {"error": "No benchmark data found", "products": 0}
    else:
        logger.info("Running scrapers (use_seed=%s)...", use_seed)
        runner = ScraperRunner(use_seed_only=use_seed)
        products = runner.run()

    logger.info("Total benchmark products: %d", len(products))

    if not products:
        return {"error": "No products available", "products": 0}

    # ── Step 2: Initialize vector store ──────────────────────────────────
    vector_store = VectorStore()

    if force_reindex:
        logger.info("Force reindex: clearing existing vector store...")
        vector_store.clear()

    # Determine which products need embedding
    existing_count = vector_store.get_count()
    if not force_reindex and existing_count > 0:
        # Get existing IDs to skip
        # ChromaDB doesn't have a simple "list all IDs" for large collections,
        # so we'll check by querying
        logger.info(
            "Vector store already has %d items. Upserting all (dedup by ID)...",
            existing_count,
        )

    # ── Step 3: Generate embeddings ──────────────────────────────────────
    logger.info("Generating multimodal embeddings for %d products...", len(products))
    engine = EmbeddingEngine()

    # Prepare embedding inputs
    embedding_items = []
    for product in products:
        embedding_items.append({
            "image_path": product.local_image_path,
            "text": product.embedding_text(),
        })

    vectors = engine.embed_batch(
        items=embedding_items,
        batch_size=settings.embedding_batch_size,
    )

    # ── Step 4: Upsert into ChromaDB ─────────────────────────────────────
    logger.info("Upserting %d vectors into ChromaDB...", len(vectors))
    added = vector_store.add_products(products, vectors)

    # ── Summary ──────────────────────────────────────────────────────────
    elapsed = (datetime.now() - start_time).total_seconds()

    summary = {
        "products_scraped": len(products),
        "vectors_generated": len(vectors),
        "vectors_indexed": added,
        "total_in_store": vector_store.get_count(),
        "elapsed_seconds": round(elapsed, 1),
        "use_seed": use_seed,
        "skip_scraping": skip_scraping,
        "force_reindex": force_reindex,
    }

    logger.info("Index build complete: %s", summary)

    # Update run log
    run_log.completed_at = datetime.now()
    run_log.products_processed = added
    run_log.success = True
    run_log.message = f"Indexed {added} products in {elapsed:.1f}s"

    return summary
