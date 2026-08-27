"""
FabIndia Scraper.

Scrapes product listings from FabIndia's online catalog.
"""

from __future__ import annotations

import logging
from datetime import datetime

from bs4 import BeautifulSoup

from ..models import BenchmarkProduct, SourcePlatform
from .base_scraper import BaseScraper, generate_product_id

logger = logging.getLogger(__name__)


class FabIndiaScraper(BaseScraper):
    """Scrapes FabIndia product catalog pages."""

    platform = SourcePlatform.FABINDIA
    base_url = "https://www.fabindia.com"

    # FabIndia category URL slugs mapped from our categories
    CATEGORY_SLUGS = {
        "pottery": "/products/home-decor/ceramics-pottery",
        "textiles": "/products/women/clothing",
        "jewelry": "/products/jewellery/all-jewellery",
        "woodwork": "/products/home-decor/wooden-decor",
        "handloom saree": "/products/women/sarees",
        "block print": "/products/women/clothing?filter=block-print",
        "brass handicraft": "/products/home-decor/metal-decor",
        "jute craft": "/products/home-decor/baskets-boxes",
        "leather craft": "/products/men/accessories",
        "bamboo craft": "/products/home-decor/baskets-boxes",
    }

    def _build_url(self, category: str, page: int = 1) -> str:
        """Build FabIndia catalog URL for a category."""
        slug = self.CATEGORY_SLUGS.get(
            category, f"/search?q=handmade+{category.replace(' ', '+')}"
        )
        return f"{self.base_url}{slug}?page={page}"

    def _parse_product(self, card, category: str) -> BenchmarkProduct | None:
        """Extract product data from a FabIndia product tile."""
        try:
            # Title
            title_el = card.select_one(
                ".product-name, .product-title, h3, .product-card__title"
            )
            if not title_el:
                return None
            title = title_el.get_text(strip=True)
            if not title or len(title) < 3:
                return None

            # Price
            price_el = card.select_one(
                ".product-price, .price, .product-card__price, .sale-price"
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
                    or img_el.get("data-lazy-src")
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
                ".product-description, .product-card__desc"
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
            logger.debug("Failed to parse FabIndia product: %s", e)
            return None

    def scrape(self) -> list[BenchmarkProduct]:
        """Scrape FabIndia catalog across configured categories."""
        products: list[BenchmarkProduct] = []
        seen_ids: set[str] = set()

        logger.info("Starting FabIndia scraper for %d categories", len(self.categories))

        for category in self.categories:
            if len(products) >= self.max_products:
                break

            for page in range(1, 4):
                url = self._build_url(category, page)
                logger.info("Scraping FabIndia: %s (page %d)", category, page)

                html = self._fetch_page(url)
                if not html:
                    break

                soup = BeautifulSoup(html, "lxml")
                cards = soup.select(
                    ".product-card, .product-tile, .product-item, "
                    ".grid-item, [class*='product']"
                )

                if not cards:
                    logger.info("No products found for %s page %d", category, page)
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

                logger.info("  → Found %d new FabIndia products", page_count)

        logger.info("FabIndia scraper complete: %d products total", len(products))
        return products
