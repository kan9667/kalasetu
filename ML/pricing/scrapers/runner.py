"""
Scraper Runner — Orchestrates all scrapers, deduplicates, downloads images,
and persists the benchmark product dataset.
"""

from __future__ import annotations

import json
import logging
import os
import time
from datetime import datetime
from pathlib import Path
from typing import Optional

import requests

from ..config import (
    BENCHMARK_IMAGES_DIR,
    BENCHMARK_PRODUCTS_FILE,
    DATA_DIR,
    ensure_data_dirs,
    get_settings,
)
from ..models import BenchmarkProduct, PipelineRunLog, PipelineStage
from .amazon_karigar import AmazonKarigarScraper
from .etsy_india import EtsyIndiaScraper
from .fabindia import FabIndiaScraper
from .okhai import OkhaiScraper
from .seed_data import SeedDataGenerator

logger = logging.getLogger(__name__)


class ScraperRunner:
    """
    Orchestrates all platform scrapers, deduplicates results,
    downloads images locally, and saves the benchmark dataset.
    """

    def __init__(self, use_seed_only: bool = False):
        """
        Args:
            use_seed_only: If True, skip live scraping and use only seed data.
                           Useful for testing or when network is unavailable.
        """
        self.use_seed_only = use_seed_only
        self.settings = get_settings()

    def run(self) -> list[BenchmarkProduct]:
        """
        Execute the full scraping pipeline:
        1. Run all scrapers (or use seed data)
        2. Deduplicate products
        3. Download product images
        4. Save to benchmark_products.json

        Returns the final list of benchmark products.
        """
        ensure_data_dirs()

        run_log = PipelineRunLog(stage=PipelineStage.SCRAPING)
        all_products: list[BenchmarkProduct] = []

        if self.use_seed_only:
            logger.info("=== Using seed data only (no live scraping) ===")
            generator = SeedDataGenerator(
                categories=self.settings.scrape_categories,
            )
            all_products = generator.generate(
                max_products=self.settings.scrape_max_products_per_source * 4,
            )
        else:
            # Run all live scrapers
            scrapers = [
                AmazonKarigarScraper(
                    categories=self.settings.scrape_categories,
                    max_products=self.settings.scrape_max_products_per_source,
                    timeout=self.settings.scrape_request_timeout,
                    delay=self.settings.scrape_request_delay,
                ),
                FabIndiaScraper(
                    categories=self.settings.scrape_categories,
                    max_products=self.settings.scrape_max_products_per_source,
                    timeout=self.settings.scrape_request_timeout,
                    delay=self.settings.scrape_request_delay,
                ),
                EtsyIndiaScraper(
                    categories=self.settings.scrape_categories,
                    max_products=self.settings.scrape_max_products_per_source,
                    timeout=self.settings.scrape_request_timeout,
                    delay=self.settings.scrape_request_delay,
                ),
                OkhaiScraper(
                    categories=self.settings.scrape_categories,
                    max_products=self.settings.scrape_max_products_per_source,
                    timeout=self.settings.scrape_request_timeout,
                    delay=self.settings.scrape_request_delay,
                ),
            ]

            for scraper in scrapers:
                scraper_name = scraper.__class__.__name__
                logger.info("Running %s...", scraper_name)
                try:
                    products = scraper.scrape()
                    all_products.extend(products)
                    logger.info(
                        "%s returned %d products", scraper_name, len(products)
                    )
                except Exception as e:
                    error_msg = f"{scraper_name} failed: {e}"
                    logger.error(error_msg)
                    run_log.errors.append(error_msg)

            # If live scraping yielded too few results, supplement with seed data
            if len(all_products) < 50:
                logger.warning(
                    "Only %d products from live scraping — supplementing with seed data",
                    len(all_products),
                )
                seed_gen = SeedDataGenerator(
                    categories=self.settings.scrape_categories,
                )
                seed_products = seed_gen.generate(max_products=500)
                all_products.extend(seed_products)

        # Deduplicate
        all_products = self._deduplicate(all_products)
        logger.info("After deduplication: %d products", len(all_products))

        # Download images
        self._download_images(all_products)

        # Save to JSON
        self._save_products(all_products)

        # Update run log
        run_log.completed_at = datetime.now()
        run_log.products_processed = len(all_products)
        run_log.success = True
        run_log.message = (
            f"Scraped {len(all_products)} products"
            f" ({'seed only' if self.use_seed_only else 'live + seed'})"
        )
        self._append_log(run_log)

        return all_products

    def _deduplicate(
        self, products: list[BenchmarkProduct]
    ) -> list[BenchmarkProduct]:
        """Remove duplicate products based on their ID."""
        seen: set[str] = set()
        unique: list[BenchmarkProduct] = []
        for p in products:
            if p.id not in seen:
                seen.add(p.id)
                unique.append(p)
        return unique

    def _download_images(self, products: list[BenchmarkProduct]) -> None:
        """
        Download product images to local storage for embedding.

        Skips images that are already downloaded.
        """
        logger.info("Downloading images for %d products...", len(products))
        downloaded = 0
        failed = 0

        for product in products:
            # Determine local file path
            ext = self._get_image_extension(product.image_url)
            local_path = BENCHMARK_IMAGES_DIR / f"{product.id}{ext}"

            # Skip if already exists
            if local_path.exists():
                product.local_image_path = str(local_path)
                continue

            try:
                response = requests.get(
                    product.image_url,
                    timeout=10,
                    headers={"User-Agent": "KarigarSetu/1.0"},
                )
                response.raise_for_status()

                with open(local_path, "wb") as f:
                    f.write(response.content)

                product.local_image_path = str(local_path)
                downloaded += 1

                # Rate limiting
                time.sleep(0.3)

            except Exception as e:
                logger.debug("Failed to download %s: %s", product.image_url, e)
                failed += 1

        logger.info(
            "Image download complete: %d new, %d failed, %d already cached",
            downloaded,
            failed,
            len(products) - downloaded - failed,
        )

    @staticmethod
    def _get_image_extension(url: str) -> str:
        """Extract image file extension from URL."""
        path = url.split("?")[0].split("#")[0]
        if path.lower().endswith(".png"):
            return ".png"
        elif path.lower().endswith(".webp"):
            return ".webp"
        elif path.lower().endswith(".gif"):
            return ".gif"
        return ".jpg"

    def _save_products(self, products: list[BenchmarkProduct]) -> None:
        """Save benchmark products to JSON file."""
        data = [p.model_dump(mode="json") for p in products]

        with open(BENCHMARK_PRODUCTS_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False, default=str)

        logger.info(
            "Saved %d products to %s", len(products), BENCHMARK_PRODUCTS_FILE
        )

    @staticmethod
    def load_products() -> list[BenchmarkProduct]:
        """Load benchmark products from the JSON file."""
        if not BENCHMARK_PRODUCTS_FILE.exists():
            logger.warning("No benchmark products file found at %s", BENCHMARK_PRODUCTS_FILE)
            return []

        with open(BENCHMARK_PRODUCTS_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)

        return [BenchmarkProduct(**item) for item in data]

    def _append_log(self, log: PipelineRunLog) -> None:
        """Append a pipeline run log entry."""
        log_file = DATA_DIR / "pipeline_runs.log"
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(log.model_dump_json() + "\n")
