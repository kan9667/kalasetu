"""
Social Media Helper Service.

Generates AI-drafted social media captions and hashtag sets for artisan
product listings using the Gemini vision model.

Features:
  - Structured JSON-only output enforced by prompt + server-side validation.
  - One automatic retry on parse failure; clean HTTPException on second failure.
  - In-memory per-process rate-limiting (max N regenerations per listing per hour).
"""

from __future__ import annotations
import mimetypes
from pathlib import Path
from urllib.parse import unquote, urlparse

import json
import logging
import re
from collections import defaultdict
from datetime import datetime, timedelta
from typing import Optional

from fastapi import HTTPException
from google import genai
from google.genai import types

from ..config import get_settings

logger = logging.getLogger(__name__)

# ── Prompt Template ──────────────────────────────────────────────────────────

_PROMPT_TEMPLATE = """\
You are writing a social media caption and hashtags for a handmade/artisan \
product listing, to help the seller get more reach.

Product title: {title}
Category: {category}
Materials: {materials}
Description: {description}
Tone: {tone}

Using the attached product image and the details above, write:
1. A caption (1–3 short paragraphs) in a warm, authentic voice. Do not invent \
facts (sizes, materials, care instructions) not present in the listing details \
or clearly visible in the image. Use no more than 2 emoji. Do NOT use \
unverified claims.
2. 15–30 relevant hashtags for social media discovery: mix a few broad \
high-volume tags (e.g. #handmade, #shopsmall, #supportsmallbusiness) with \
more specific, niche tags derived from the category, materials, and craft \
technique (niche tags drive more relevant artisan-buyer discovery than generic \
ones).

Language: respond in the language matching the locale "{locale}".

Respond with ONLY valid JSON in this exact shape, no markdown fences, no extra \
text:
{{"caption": "...", "hashtags": ["#tag1", "#tag2", ...]}}
"""

# ── Rate-Limit Store ─────────────────────────────────────────────────────────
# Keyed by a string (listing_id+image_url or draft_key+image_url).
# Value: list of datetime objects for requests in the current hour window.

_rate_limit_store: dict[str, list[datetime]] = defaultdict(list)

MAX_REGEN_PER_HOUR = 5  # overridable via env/settings if needed


def _check_rate_limit(rate_key: str) -> None:
    """Raise HTTPException(429) if the rate key has exceeded MAX_REGEN_PER_HOUR."""
    now = datetime.now()
    cutoff = now - timedelta(hours=1)
    # Prune old entries
    _rate_limit_store[rate_key] = [
        ts for ts in _rate_limit_store[rate_key] if ts > cutoff
    ]
    if len(_rate_limit_store[rate_key]) >= MAX_REGEN_PER_HOUR:
        logger.warning("[SocialMedia] Rate limit hit for key=%s", rate_key)
        raise HTTPException(
            status_code=429,
            detail=(
                f"Too many regeneration requests. "
                f"Max {MAX_REGEN_PER_HOUR} per hour per listing. Try again later."
            ),
        )
    _rate_limit_store[rate_key].append(now)


# ── Service ──────────────────────────────────────────────────────────────────


class SocialMediaService:
    """Calls Gemini vision to produce caption + hashtags for artisan listings."""

    def __init__(self) -> None:
        self.settings = get_settings()
        self.client = (
            genai.Client(api_key=self.settings.gemini_api_key)
            if self.settings.gemini_api_key
            else None
        )
        self.model = self.settings.llm_model  # e.g. "gemini-3.6-flash"

    # ── Public API ───────────────────────────────────────────────────────────

    async def generate(
        self,
        *,
        image_url: str,
        title: str = "",
        category: str = "",
        materials: Optional[list[str]] = None,
        description: str = "",
        tone: str = "warm and authentic",
        locale: str = "en-US",
        rate_limit_key: str = "",
    ) -> dict:
        """
        Generate a social media caption + hashtags for the given image/listing.

        Returns:
            {"caption": str, "hashtags": list[str]}

        Raises:
            HTTPException(429) on rate limit.
            HTTPException(502) on LLM/parse failure after one retry.
            HTTPException(503) if the Gemini client is not configured.
        """
        if not self.client:
            raise HTTPException(
                status_code=503,
                detail="AI service not configured. Please set GEMINI_API_KEY.",
            )

        # Rate limit check (skip if no key provided — e.g. first-time load)
        if rate_limit_key:
            _check_rate_limit(rate_limit_key)

        prompt = _PROMPT_TEMPLATE.format(
            title=title or "(not provided)",
            category=category or "(not provided)",
            materials=", ".join(materials) if materials else "(not provided)",
            description=description or "(not provided)",
            tone=tone,
            locale=locale,
        )

        return await self._call_with_retry(prompt=prompt, image_url=image_url)

    # ── Internal Helpers ─────────────────────────────────────────────────────

    async def _call_with_retry(self, *, prompt: str, image_url: str) -> dict:
        """Call Gemini once; retry once on parse failure."""
        for attempt in range(2):
            try:
                raw = await self._call_gemini(prompt=prompt, image_url=image_url)
                parsed = _parse_json_response(raw)
                return parsed
            except _ParseError as exc:
                if attempt == 0:
                    logger.warning(
                        "[SocialMedia] JSON parse failed (attempt 1), retrying: %s", exc
                    )
                    continue
                logger.error("[SocialMedia] JSON parse failed after retry: %s", exc)
                raise HTTPException(
                    status_code=502,
                    detail=(
                        "The AI returned an unexpected response. "
                        "Please try again using the Regenerate button."
                    ),
                ) from exc
            except HTTPException:
                raise
            except Exception as exc:
                logger.error("[SocialMedia] Gemini call failed: %s", exc, exc_info=True)
                raise HTTPException(
                    status_code=502,
                    detail=(
                        "Failed to reach the AI service. "
                        "Please check your connection and try again."
                    ),
                ) from exc
        raise HTTPException(status_code=502, detail="Unexpected generation error.")

    async def _call_gemini(self, *, prompt: str, image_url: str) -> str:
        """Send image + prompt to Gemini and return the raw text response."""
        image_path = self._local_image_path(image_url)

        if not image_path.is_file():
            raise HTTPException(
                status_code=400,
                detail="Invalid or unavailable product image.",
            )

        mime_type = mimetypes.guess_type(image_path.name)[0] or "image/jpeg"
        contents: list = [
            types.Part.from_bytes(
                data=image_path.read_bytes(),
                mime_type=mime_type,
            ),
            types.Part.from_text(text=prompt),
        ]
        response = await self.client.aio.models.generate_content(
            model=self.model,
            contents=contents,
        )
        return response.text or ""

    def _local_image_path(self, image_url: str) -> Path:
        """
        Resolve only this backend's localhost upload URLs to local files.

        Arbitrary filesystem paths are rejected. The resolved file must
        remain inside the configured upload directory.
        """
        parsed = urlparse(image_url)

        if parsed.hostname not in {"localhost", "127.0.0.1", "0.0.0.0"}:
            return Path()

        upload_prefix = self.settings.static_url_prefix.rstrip("/") + "/"
        if not parsed.path.startswith(upload_prefix):
            return Path()

        relative_path = unquote(parsed.path[len(upload_prefix):]).lstrip("/")
        upload_root = Path(self.settings.upload_dir).resolve()
        candidate = (upload_root / relative_path).resolve()

        try:
            candidate.relative_to(upload_root)
        except ValueError:
            logger.warning(
                "[SocialMedia] Rejected image path outside upload directory: %s",
                relative_path,
            )
            return Path()

        return candidate


# ── JSON Parsing ─────────────────────────────────────────────────────────────


class _ParseError(ValueError):
    """Raised when the LLM response cannot be parsed into the expected shape."""


def _parse_json_response(raw: str) -> dict:
    """
    Extract and validate JSON from the model response.

    Handles:
      - Properly formatted JSON
      - JSON wrapped in ```json ... ``` fences (model occasionally ignores instructions)
      - Missing '#' prefix on hashtags (auto-repaired)
    """
    text = raw.strip()

    # Strip optional markdown fences
    fenced = re.search(r"```(?:json)?\s*(.*?)\s*```", text, re.DOTALL)
    if fenced:
        text = fenced.group(1).strip()

    # Find first {...} block
    brace_match = re.search(r"\{.*\}", text, re.DOTALL)
    if not brace_match:
        raise _ParseError(f"No JSON object found in response: {raw[:200]!r}")

    try:
        data = json.loads(brace_match.group())
    except json.JSONDecodeError as exc:
        raise _ParseError(f"JSON decode error: {exc}") from exc

    caption = data.get("caption")
    hashtags = data.get("hashtags")

    if not isinstance(caption, str) or not caption.strip():
        raise _ParseError("Missing or empty 'caption' field.")
    if not isinstance(hashtags, list):
        raise _ParseError("'hashtags' must be a list.")

    # Repair: ensure every tag starts with '#'
    hashtags = [
        tag if tag.startswith("#") else f"#{tag}"
        for tag in hashtags
        if isinstance(tag, str) and tag.strip()
    ]

    return {"caption": caption.strip(), "hashtags": hashtags}
