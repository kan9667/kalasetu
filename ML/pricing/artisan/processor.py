"""
Artisan Product Processor.

The main entry point for processing an artisan's product upload:
1. Generates a query vector from the artisan's image + description
2. Retrieves top-K comparable benchmark products from ChromaDB
3. Passes everything to the LLM pricer for a structured price recommendation

This is triggered when the mobile app syncs a new product.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Optional

from ..config import DATA_DIR, ensure_data_dirs, get_settings
from ..embeddings.embedding_engine import EmbeddingEngine
from ..embeddings.vector_store import VectorStore
from ..llm.pricer import LLMPricer
from ..models import ArtisanProduct, CostInputs, PricingResult

logger = logging.getLogger(__name__)


class ArtisanProductProcessor:
    """
    Processes an artisan's product upload through the full pricing pipeline:
    embed → retrieve comparables → LLM price → return structured result.
    """

    def __init__(self):
        self.settings = get_settings()
        self.embedding_engine = EmbeddingEngine()
        self.vector_store = VectorStore()
        self.pricer = LLMPricer()

    def process_upload(
        self,
        image_path: str,
        description: str,
        cost_inputs: Optional[dict] = None,
        category: Optional[str] = None,
    ) -> PricingResult:
        """
        Process a single artisan product upload and return a pricing recommendation.

        Args:
            image_path: Path to the product image (enhanced by the image pipeline).
            description: English product description (from the cataloger pipeline).
            cost_inputs: Optional dict with cost breakdown keys:
                         materials, labor_hours, hourly_rate, transport, overhead.
            category: Optional product category for filtered search.

        Returns:
            PricingResult with suggested price, range, confidence, and reasoning.
        """
        ensure_data_dirs()
        logger.info("Processing artisan upload: %s", description[:80])

        # Parse cost inputs
        costs = None
        if cost_inputs:
            costs = CostInputs(**cost_inputs)

        # ── Step 1: Generate query vector ────────────────────────────────
        logger.info("Step 1: Generating multimodal query vector...")
        query_vector = self.embedding_engine.embed_multimodal(
            image_path=image_path if Path(image_path).exists() else None,
            text=description,
        )
        logger.info("Query vector generated (dim=%d)", len(query_vector))

        # ── Step 2: Retrieve market comparables (RAG) ────────────────────
        logger.info("Step 2: Retrieving top-%d comparables...", self.settings.pricing_top_k)
        comparables = self.vector_store.query_similar(
            query_vector=query_vector,
            top_k=self.settings.pricing_top_k,
            category_filter=category,
        )

        if not comparables:
            logger.warning("No comparables found. Trying without category filter...")
            comparables = self.vector_store.query_similar(
                query_vector=query_vector,
                top_k=self.settings.pricing_top_k,
                category_filter=None,
            )

        logger.info(
            "Retrieved %d comparables (prices: %s)",
            len(comparables),
            [f"₹{c.selling_price:,.0f}" for c in comparables],
        )

        # ── Step 3: LLM price calculation ────────────────────────────────
        logger.info("Step 3: Running LLM price calculation...")
        result = self.pricer.calculate_price(
            description=description,
            comparables=comparables,
            cost_inputs=costs,
            image_path=image_path if Path(image_path).exists() else None,
            category=category,
        )

        logger.info(
            "Pricing complete: ₹%.0f (range ₹%.0f–₹%.0f, confidence %.0f%%)",
            result.suggested_price,
            result.price_range_low,
            result.price_range_high,
            result.confidence_score * 100,
        )

        # ── Save result for audit trail ──────────────────────────────────
        self._save_result(description, result)

        return result

    def process_batch(
        self,
        products: list[dict],
    ) -> list[PricingResult]:
        """
        Process multiple artisan product uploads.

        Args:
            products: List of dicts, each with keys:
                      image_path, description, cost_inputs (optional), category (optional).

        Returns:
            List of PricingResult instances.
        """
        results = []
        for i, product in enumerate(products):
            logger.info("Processing product %d/%d...", i + 1, len(products))
            try:
                result = self.process_upload(
                    image_path=product["image_path"],
                    description=product["description"],
                    cost_inputs=product.get("cost_inputs"),
                    category=product.get("category"),
                )
                results.append(result)
            except Exception as e:
                logger.error("Failed to process product %d: %s", i + 1, e)
                # Return a minimal error result
                results.append(
                    PricingResult(
                        suggested_price=0,
                        price_range_low=0,
                        price_range_high=0,
                        confidence_score=0,
                        reasoning=f"Processing failed: {e}",
                        market_position="unknown",
                    )
                )

        return results

    def _save_result(self, description: str, result: PricingResult) -> None:
        """Save pricing result to the local audit log."""
        log_file = DATA_DIR / "pricing_results.jsonl"
        entry = {
            "timestamp": datetime.now().isoformat(),
            "description_preview": description[:100],
            "suggested_price": result.suggested_price,
            "price_range": [result.price_range_low, result.price_range_high],
            "cost_floor": result.cost_floor,
            "confidence": result.confidence_score,
            "market_position": result.market_position,
            "num_comparables": len(result.comparable_products),
        }

        with open(log_file, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
