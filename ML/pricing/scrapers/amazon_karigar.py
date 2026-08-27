"""
Amazon Karigar Scraper.

Scrapes handicraft product listings from Amazon India's Karigar program.
Targets search results for artisan product categories.
"""

from __future__ import annotations

import logging
from datetime import datetime

from bs4 import BeautifulSoup

from ..models import BenchmarkProduct, SourcePlatform
from .base_scraper import BaseScraper, generate_product_id

logger = logging.getLogger(__name__)


class AmazonKarigarScraper(BaseScraper):
    """Scrapes Amazon India Karigar handicraft listings."""

    platform = SourcePlatform.AMAZON_KARIGAR
    base_url = "https://www.amazon.in"

    def _build_search_url(self, category: str, page: int = 1) -> str:
        """Build Amazon search URL for a handicraft category."""
        query = f"handmade {category} karigar"
        return (
            f"{self.base_url}/s?"
            f"k={query.replace(' ', '+')}"
            f"&page={page}"
            f"&ref=sr_pg_{page}"
        )

    def _parse_product_card(self, card, category: str) -> BenchmarkProduct | None:
        """Extract product data from an Amazon search result card."""
        try:
            # Title
            title_el = card.select_one(
                "h2 a span, .a-size-medium.a-color-base.a-text-normal, "
                ".a-size-base-plus.a-color-base.a-text-normal"
            )
            if not title_el:
                return None
            title = title_el.get_text(strip=True)

            if not title or len(title) < 5:
                return None

            # Price
            price_el = card.select_one(
                ".a-price .a-offscreen, .a-price-whole"
            )
            price = None
            if price_el:
                price = self._clean_price(price_el.get_text(strip=True))
            if price is None or price <= 0:
                return None

            # Image
            img_el = card.select_one("img.s-image")
            image_url = img_el.get("src", "") if img_el else ""
            if not image_url:
                return None

            # Product URL
            link_el = card.select_one("h2 a")
            product_url = ""
            if link_el and link_el.get("href"):
                href = link_el["href"]
                product_url = (
                    href if href.startswith("http") else f"{self.base_url}{href}"
                )

            # Description — Amazon cards don't have full descriptions,
            # so we use any bullet points or secondary text
            desc_parts = []
            for bullet in card.select(".a-size-base-plus:not(.a-color-base)"):
                text = bullet.get_text(strip=True)
                if text and text != title:
                    desc_parts.append(text)

            return BenchmarkProduct(
                id=generate_product_id(image_url, title),
                image_url=image_url,
                title=title,
                description=" | ".join(desc_parts) if desc_parts else "",
                category=category,
                selling_price=price,
                source_platform=self.platform,
                product_url=product_url,
                scraped_at=datetime.now(),
            )
        except Exception as e:
            logger.debug("Failed to parse Amazon product card: %s", e)
            return None

    def scrape(self) -> list[BenchmarkProduct]:
        """Scrape Amazon Karigar listings across all configured categories."""
        products: list[BenchmarkProduct] = []
        seen_ids: set[str] = set()

        logger.info("Starting Amazon Karigar scraper for %d categories", len(self.categories))

        for category in self.categories:
            if len(products) >= self.max_products:
                break

            for page in range(1, 4):  # Max 3 pages per category
                url = self._build_search_url(category, page)
                logger.info("Scraping: %s (page %d)", category, page)

                html = self._fetch_page(url)
                if not html:
                    logger.warning("No HTML returned for %s page %d", category, page)
                    break

                soup = BeautifulSoup(html, "lxml")

                # Amazon product cards
                cards = soup.select(
                    "[data-component-type='s-search-result'], "
                    ".s-result-item[data-asin]"
                )

                if not cards:
                    logger.info("No more results for %s at page %d", category, page)
                    break

                page_count = 0
                for card in cards:
                    product = self._parse_product_card(card, category)
                    if product and product.id not in seen_ids:
                        seen_ids.add(product.id)
                        products.append(product)
                        page_count += 1

                        if len(products) >= self.max_products:
                            break

                logger.info(
                    "  → Found %d new products on page %d", page_count, page
                )

        logger.info(
            "Amazon Karigar scraper complete: %d products total", len(products)
        )
        return products
