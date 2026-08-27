"""
Okhai Scraper.

Scrapes product listings from Okhai (okhai.org), a social enterprise
that sells handcrafted products made by rural artisans.
"""

from __future__ import annotations

import logging
from datetime import datetime

from bs4 import BeautifulSoup

from ..models import BenchmarkProduct, SourcePlatform
from .base_scraper import BaseScraper, generate_product_id

logger = logging.getLogger(__name__)


class OkhaiScraper(BaseScraper):
    """Scrapes Okhai product listings."""

    platform = SourcePlatform.OKHAI
    base_url = "https://www.okhai.org"

    # Okhai category mappings
    CATEGORY_PATHS = {
        "textiles": "/collections/all-products",
        "jewelry": "/collections/jewellery",
        "pottery": "/collections/home-decor",
        "woodwork": "/collections/home-decor",
        "handloom saree": "/collections/sarees",
        "block print": "/collections/all-products?filter=block-print",
        "brass handicraft": "/collections/home-decor",
        "jute craft": "/collections/bags-and-accessories",
        "leather craft": "/collections/bags-and-accessories",
        "bamboo craft": "/collections/home-decor",
    }

    def _build_url(self, category: str, page: int = 1) -> str:
        """Build Okhai catalog URL."""
        path = self.CATEGORY_PATHS.get(category, "/collections/all-products")
        separator = "&" if "?" in path else "?"
        return f"{self.base_url}{path}{separator}page={page}"

    def _parse_product(self, card, category: str) -> BenchmarkProduct | None:
        """Extract product data from an Okhai product card."""
        try:
            # Title
            title_el = card.select_one(
                ".product-card__title, .grid-product__title, "
                "h3, .product-title, .card__heading"
            )
            if not title_el:
                return None
            title = title_el.get_text(strip=True)
            if not title or len(title) < 3:
                return None

            # Price
            price_el = card.select_one(
                ".product-card__price, .grid-product__price, "
                ".price, .money, .product-price"
            )
            price = None
            if price_el:
                price = self._clean_price(price_el.get_text(strip=True))
            if price is None or price <= 0:
                return None

            # Image
            img_el = card.select_one("img")
            image_url = ""
            if img_el:
                image_url = (
                    img_el.get("data-src")
                    or img_el.get("src")
                    or img_el.get("data-srcset", "").split(",")[0].split(" ")[0]
                    or ""
                )
            if not image_url or image_url.startswith("data:"):
                return None
            if image_url.startswith("//"):
                image_url = f"https:{image_url}"
            elif image_url.startswith("/"):
                image_url = f"{self.base_url}{image_url}"

            # Product URL
            link_el = card.select_one("a")
            product_url = ""
            if link_el and link_el.get("href"):
                href = link_el["href"]
                product_url = (
                    href if href.startswith("http") else f"{self.base_url}{href}"
                )

            # Description
            desc_el = card.select_one(
                ".product-card__description, .product-description"
            )
            description = desc_el.get_text(strip=True) if desc_el else ""

            return BenchmarkProduct(
                id=generate_product_id(image_url, title),
                image_url=image_url,
                title=title,
                description=description,
                category=category,
                selling_price=price,
                source_platform=self.platform,
                product_url=product_url,
                scraped_at=datetime.now(),
            )
        except Exception as e:
            logger.debug("Failed to parse Okhai product: %s", e)
            return None

    def scrape(self) -> list[BenchmarkProduct]:
        """Scrape Okhai catalog across configured categories."""
        products: list[BenchmarkProduct] = []
        seen_ids: set[str] = set()

        logger.info("Starting Okhai scraper for %d categories", len(self.categories))

        for category in self.categories:
            if len(products) >= self.max_products:
                break

            for page in range(1, 4):
                url = self._build_url(category, page)
                logger.info("Scraping Okhai: %s (page %d)", category, page)

                html = self._fetch_page(url)
                if not html:
                    break

                soup = BeautifulSoup(html, "lxml")
                cards = soup.select(
                    ".product-card, .grid-product, .grid__item, "
                    ".collection-product-card, [class*='product-card']"
                )

                if not cards:
                    logger.info("No Okhai results for %s page %d", category, page)
                    break

                page_count = 0
                for card in cards:
                    product = self._parse_product(card, category)
                    if product and product.id not in seen_ids:
                        seen_ids.add(product.id)
                        products.append(product)
                        page_count += 1

                        if len(products) >= self.max_products:
                            break

                logger.info("  → Found %d new Okhai products", page_count)

        logger.info("Okhai scraper complete: %d products total", len(products))
        return products
