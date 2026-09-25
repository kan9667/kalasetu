"""
Deterministic Content Hashing Utility.

Generates a canonical SHA-256 hash for product content revisions to enforce
that approved listings match the exact artisan-reviewed attributes and media identity.
"""

import hashlib
import json
from typing import List, Optional


def compute_content_hash(
    title: str,
    title_hi: Optional[str],
    description: str,
    description_hi: Optional[str],
    price_paise: int,
    category: str,
    tags: List[str],
    floor_price_paise: int,
    media_id: Optional[str] = "",
    media_checksum: Optional[str] = "",
) -> str:
    """
    Compute a deterministic SHA-256 hash over normalized product attributes and immutable media identity.
    """
    normalized = {
        "category": (category or "").strip(),
        "description": (description or "").strip(),
        "description_hi": (description_hi or "").strip(),
        "floor_price_paise": int(floor_price_paise or 0),
        "media_checksum": (media_checksum or "").strip(),
        "media_id": (media_id or "").strip(),
        "price_paise": int(price_paise or 0),
        "tags": sorted([t.strip() for t in (tags or []) if t.strip()]),
        "title": (title or "").strip(),
        "title_hi": (title_hi or "").strip(),
    }

    payload = json.dumps(normalized, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()
