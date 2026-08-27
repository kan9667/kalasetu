"""
Etsy India Scraper.

Scrapes handicraft product listings from Etsy targeting Indian artisan sellers.
"""

from __future__ import annotations

import logging
from datetime import datetime

from bs4 import BeautifulSoup

from ..models import BenchmarkProduct, SourcePlatform
from .base_scraper import BaseScraper, generate_product_id

logger = logging.getLogger(__name__)


class EtsyIndiaScraper(BaseScraper):
    """Scrapes Etsy India handicraft listings."""

    platform = SourcePlatform.ETSY_INDIA
    base_url = "https://www.etsy.com"

    def _build_search_url(self, category: str, page: int = 1) -> str:
        """Build Etsy search URL for Indian handicrafts."""
        query = f"indian handmade {category}"
        offset = (page - 1) * 64  # Etsy uses offset-based pagination
        return (
            f"{self.base_url}/search?"
            f"q={query.replace(' ', '+')}"
            f"&ship_to=IN"
            f"&offset={offset}"
            f"&ref=pagination"
        )

    def _parse_listing(self, card, category: str) -> BenchmarkProduct | None:
        """Extract product data from an Etsy listing card."""
        try:
            # Title
            title_el = card.select_one(
                ".v2-listing-card__title, "
                "h3.wt-text-caption, "
                "[data-listing-card-title], "
                ".wt-text-truncate"
            )
            if not title_el:
                return None
            title = title_el.get_text(strip=True)
            if not title or len(title) < 3:
                return None

            # Price — Etsy shows prices in various formats
            price_el = card.select_one(
                ".currency-value, "
                ".lc-price .wt-text-title-01, "
                "[data-buy-box-listing-price], "
                ".wt-text-title-small .currency-value"
            )
            price = None
            if price_el:
                price_text = price_el.get_text(strip=True)
                price = self._clean_price(price_text)

            # Try to find INR price specifically
            if price is None:
                for span in card.select("span"):
                    text = span.get_text(strip=True)
                    if "₹" in text or "INR" in text.upper():
                        price = self._clean_price(text)
                        if price:
                            break

            if price is None or price <= 0:
                return None

            # Image
            img_el = card.select_one(
                ".wt-width-full img, "
                "img.wt-position-absolute, "
                ".v2-listing-card__img img"
            )
            image_url = ""
            if img_el:
                image_url = (
                    img_el.get("data-src")
                    or img_el.get("src")
                    or img_el.get("srcset", "").split(",")[0].split(" ")[0]
                    or ""
                )
            if not image_url or image_url.startswith("data:"):
                return None

            # Product URL
            link_el = card.select_one("a.listing-link, a[href*='/listing/']")
            product_url = ""
            if link_el and link_el.get("href"):
                href = link_el["href"]
                product_url = (
                    href if href.startswith("http") else f"{self.base_url}{href}"
                )

            return BenchmarkProduct(
                id=generate_product_id(image_url, title),
                image_url=image_url,
                title=title,
                description="",  # Etsy cards don't show descriptions in search
                category=category,
                selling_price=price,
                source_platform=self.platform,
                product_url=product_url,
                scraped_at=datetime.now(),
            )
        except Exception as e:
            logger.debug("Failed to parse Etsy listing: %s", e)
            return None

    def scrape(self) -> list[BenchmarkProduct]:
        """Scrape Etsy India listings across configured categories."""
        products: list[BenchmarkProduct] = []
        seen_ids: set[str] = set()

        logger.info("Starting Etsy India scraper for %d categories", len(self.categories))

        for category in self.categories:
            if len(products) >= self.max_products:
                break

            for page in range(1, 4):
                url = self._build_search_url(category, page)
                logger.info("Scraping Etsy: %s (page %d)", category, page)

                html = self._fetch_page(url)
                if not html:
                    break

                soup = BeautifulSoup(html, "lxml")
                cards = soup.select(
                    ".v2-listing-card, "
                    "[data-listing-card], "
                    ".wt-grid__item-xs-6"
                )

                if not cards:
                    logger.info("No Etsy results for %s page %d", category, page)
                    break

                page_count = 0
                for card in cards:
                    product = self._parse_listing(card, category)
                    if product and product.id not in seen_ids:
                        seen_ids.add(product.id)
                        products.append(product)
                        page_count += 1

                        if len(products) >= self.max_products:
                            break

                logger.info("  → Found %d new Etsy products", page_count)

        logger.info("Etsy India scraper complete: %d products total", len(products))
        return products
