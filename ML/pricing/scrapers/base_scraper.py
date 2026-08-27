"""
Base Scraper — Abstract interface for all platform scrapers.

Every scraper must implement the `scrape()` method returning a list
of BenchmarkProduct instances.
"""

from __future__ import annotations

import hashlib
import logging
import random
import time
from abc import ABC, abstractmethod
from typing import Optional

import requests

from ..models import BenchmarkProduct, SourcePlatform

logger = logging.getLogger(__name__)


# Rotating user-agent pool for polite scraping
USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
    "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
]


def generate_product_id(image_url: str, title: str) -> str:
    """Generate a deterministic ID from image URL and title."""
    raw = f"{image_url}|{title}".encode("utf-8")
    return hashlib.sha256(raw).hexdigest()[:16]


class BaseScraper(ABC):
    """Abstract base class for platform scrapers."""

    platform: SourcePlatform
    base_url: str

    def __init__(
        self,
        categories: Optional[list[str]] = None,
        max_products: int = 250,
        timeout: int = 15,
        delay: float = 1.5,
    ):
        self.categories = categories or [
            "pottery",
            "textiles",
            "jewelry",
            "woodwork",
        ]
        self.max_products = max_products
        self.timeout = timeout
        self.delay = delay
        self.session = requests.Session()

    def _get_headers(self) -> dict[str, str]:
        """Return randomized request headers."""
        return {
            "User-Agent": random.choice(USER_AGENTS),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-IN,en;q=0.9,hi;q=0.8",
            "Accept-Encoding": "gzip, deflate",
            "Connection": "keep-alive",
        }

    def _fetch_page(self, url: str) -> Optional[str]:
        """
        Fetch a page with rate limiting, retries, and user-agent rotation.

        Returns the HTML content or None on failure.
        """
        time.sleep(self.delay + random.uniform(0, 0.5))

        for attempt in range(3):
            try:
                response = self.session.get(
                    url,
                    headers=self._get_headers(),
                    timeout=self.timeout,
                )
                response.raise_for_status()
                return response.text
            except requests.RequestException as e:
                logger.warning(
                    "Attempt %d/%d failed for %s: %s",
                    attempt + 1,
                    3,
                    url,
                    e,
                )
                if attempt < 2:
                    time.sleep(2 ** (attempt + 1))

        logger.error("All attempts failed for %s", url)
        return None

    def _clean_price(self, price_str: str) -> Optional[float]:
        """
        Parse a price string like '₹1,299.00' or 'Rs. 2500' into a float.

        Returns None if parsing fails.
        """
        if not price_str:
            return None

        import re

        # Remove currency symbols, commas, and whitespace
        cleaned = re.sub(r"[₹$,\s]", "", price_str)
        cleaned = re.sub(r"^(Rs\.?|INR)\s*", "", cleaned, flags=re.IGNORECASE)
        cleaned = cleaned.strip()

        try:
            return float(cleaned)
        except ValueError:
            logger.debug("Could not parse price: %r", price_str)
            return None

    @abstractmethod
    def scrape(self) -> list[BenchmarkProduct]:
        """
        Execute the scraping logic and return benchmark products.

        Must be implemented by each platform scraper.
        """
        ...
