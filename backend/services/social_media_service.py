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
import os
import json
import logging
import re
from collections import defaultdict
from datetime import datetime, timedelta
from typing import Optional

from fastapi import HTTPException
from google import genai
from google.genai import types

from .groq_client import GroqClient
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
{channel_instructions}

Language: respond in the language matching the locale "{locale}".

Respond with ONLY valid JSON in this exact shape, no markdown fences, no extra \
text:
{{"caption": "...", "hashtags": ["#tag1", "#tag2", ...]}}
"""

_WHATSAPP_INSTRUCTIONS = """\
1. Write a short (2–4 lines), direct, warm, and personal caption specifically crafted for a WhatsApp message or status update to customers and community contacts. Keep it friendly, clear, and punchy. Include a warm artisan greeting (like "Namaste!" or "Hello!"), mention the handcrafted nature, and end with a clear call-to-action to reply or message to order. Do not invent facts not present in the listing details. Use no more than 2 tasteful emojis.
2. Hashtags: WhatsApp messages do not use heavy hashtags. Return an empty list or at most 1-2 minimal tags (e.g. ["#handmade", "#artisan"])."""

_INSTAGRAM_INSTRUCTIONS = """\
1. Write an engaging Instagram caption (1–3 short paragraphs) with a rich craft heritage and storytelling angle. Focus on the visual beauty, texture, artisan technique, and tactile materials. Include an aesthetic opening hook and an invitation to appreciate handmade craft. Do not invent facts (sizes, materials, care instructions) not present in the listing details or clearly visible in the image. Use 2-4 appropriate emojis.
2. 15–25 high-discovery hashtags for Instagram: mix a few broad high-volume tags (e.g. #handmade, #craftsmanship, #supportlocal) with niche craft tags derived from the category, materials, and artisan tradition (e.g. #handcrafteddecor, #traditionalcraft, #artisanmade)."""

_FACEBOOK_INSTRUCTIONS = """\
1. Write a community-focused Facebook post (2–3 short paragraphs) with an authentic artisan story angle. Facebook audiences connect with the maker's journey, heritage traditions, family legacy, and community impact. Share what makes this piece special, and encourage friends, family, and craft lovers to like, comment, and share to support local handmade art. Use 2-3 warm emojis.
2. 5–10 relevant Facebook community and discovery hashtags (e.g. #SupportLocalArtisans, #HandmadeCommunity, #IndianCrafts, #VocalForLocal, #TraditionalArt)."""

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
    """Generates social media captions + hashtags for artisan listings via Groq or Gemini."""

    def __init__(self) -> None:
        self.settings = get_settings()
        self.groq_client = GroqClient()
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
        channel: str = "instagram",
        rate_limit_key: str = "",
    ) -> dict:
        """
        Generate a social media caption + hashtags for the given image/listing.

        Returns:
            {"caption": str, "hashtags": list[str]}

        Raises:
            HTTPException(429) on rate limit.
            HTTPException(502) on LLM/parse failure after one retry.
            HTTPException(503) if neither Groq nor Gemini is configured.
        """
        if not self.groq_client.is_available() and not self.client:
            raise HTTPException(
                status_code=503,
                detail="AI service not configured. Please set GROQ_API_KEY in .env.",
            )

        # Rate limit check (skip if no key provided — e.g. first-time load)
        if rate_limit_key:
            _check_rate_limit(rate_limit_key)

        channel_lower = (channel or "instagram").lower()
        if channel_lower == "whatsapp":
            channel_instructions = _WHATSAPP_INSTRUCTIONS
        elif channel_lower == "facebook":
            channel_instructions = _FACEBOOK_INSTRUCTIONS
        else:
            channel_instructions = _INSTAGRAM_INSTRUCTIONS

        prompt = _PROMPT_TEMPLATE.format(
            title=title or "(not provided)",
            category=category or "(not provided)",
            materials=", ".join(materials) if materials else "(not provided)",
            description=description or "(not provided)",
            tone=tone,
            locale=locale,
            channel_instructions=channel_instructions,
        )

        # ── 1. Try Groq Cloud ───────────────────────────────────────────────
        if self.groq_client.is_available() and self.settings.llm_provider == "groq":
            try:
                if channel_lower == "whatsapp":
                    system_content = (
                        "You are writing a short, personal WhatsApp message/status (2-4 lines) for a handmade artisan product with an artisan greeting and buy call-to-action. "
                        "No heavy hashtags. Respond with ONLY valid JSON: {\"caption\": \"...\", \"hashtags\": [\"#handmade\"]}"
                    )
                    default_caption = f"Namaste! ✨ Check out this handcrafted {title} made with traditional artisan skill. Reply here to order!"
                    default_tags = ["#handmade"]
                elif channel_lower == "facebook":
                    system_content = (
                        "You are writing a community and heritage storytelling Facebook post (2-3 paragraphs) for a handmade artisan product, focusing on maker pride, tradition, and community support. "
                        "Include 5-10 community hashtags. Respond with ONLY valid JSON: {\"caption\": \"...\", \"hashtags\": [\"#SupportLocalArtisans\", \"#IndianCrafts\"]}"
                    )
                    default_caption = (
                        f"We are proud to share our latest handcrafted creation: {title}. "
                        f"Every piece is shaped by hand with dedication to traditional heritage craftsmanship. "
                        f"Please support local artisans by sharing this with your friends and family! ✨"
                    )
                    default_tags = ["#SupportLocalArtisans", "#IndianCrafts", "#HandmadeCommunity", "#VocalForLocal", "#TraditionalArt"]
                else:
                    system_content = (
                        "You are writing an aesthetic Instagram caption (1-3 paragraphs) for a handmade artisan product with craft storytelling and 15-25 discovery hashtags. "
                        "Respond with ONLY valid JSON: {\"caption\": \"...\", \"hashtags\": [\"#handmade\", \"#artisanmade\"]}"
                    )
                    default_caption = (
                        f"Admire the timeless beauty of this handcrafted {title}. "
                        f"Made by master artisans with passion and heritage techniques. Support local art! ✨"
                    )
                    default_tags = ["#handmade", "#artisan", "#handcrafted", "#supportartisans", "#craftsmanship", "#indiancrafts", "#shopsmall"]

                messages = [
                    {
                        "role": "system",
                        "content": system_content,
                    },
                    {"role": "user", "content": prompt},
                ]
                data = await self.groq_client.chat_json(messages)
                return {
                    "caption": data.get("caption", default_caption),
                    "hashtags": data.get("hashtags", default_tags),
                }
            except Exception as e:
                logger.warning("[SocialMediaService] Groq generation failed: %s. Trying Gemini fallback.", e)

        # ── 2. Fallback to Gemini ───────────────────────────────────────────
        if self.client:
            return await self._call_with_retry(prompt=prompt, image_url=image_url)

        # ── 3. Offline / Rule-based Fallback ────────────────────────────────
        if channel_lower == "whatsapp":
            return {
                "caption": (
                    f"Namaste! ✨ Take a look at this handcrafted {title or 'creation'}. "
                    f"Made with love using traditional artisan techniques. Message me to order!"
                ),
                "hashtags": ["#handmade"],
            }
        elif channel_lower == "facebook":
            return {
                "caption": (
                    f"We are excited to present this handcrafted {title or 'creation'}! ✨\n\n"
                    f"Rooted in authentic tradition and crafted with immense care by local artisans. "
                    f"Every purchase directly empowers our artisan community. "
                    f"If you love handmade art, please like and share with your family and friends!"
                ),
                "hashtags": [
                    "#SupportLocalArtisans",
                    "#HandmadeCommunity",
                    "#IndianCrafts",
                    "#VocalForLocal",
                    "#TraditionalArt",
                ],
            }

        tags = ["#handmade", "#handcrafted", "#artisan", "#vocalforlocal", "#indiancrafts", "#artisanmade", "#craftsmanship"]
        if category:
            tags.insert(0, f"#{category.lower().replace(' ', '')}")
        return {
            "caption": (
                f"Admire the timeless beauty of this handcrafted {title or 'creation'}. "
                f"Made by master artisans with passion and heritage techniques. Support local art! ✨"
            ),
            "hashtags": tags,
        }

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
        
        # 1. Block obvious traversal characters
        if not relative_path or ".." in relative_path or "\\" in relative_path:
            logger.warning(
                "[SocialMedia] Rejected invalid image path segment: %s",
                relative_path,
            )
            return Path()

        # 2. CodeQL-compliant resolution
        # We must use os.path functions because CodeQL explicitly looks for them
        safe_dir = os.path.realpath(str(self.settings.upload_dir))
        target_path = os.path.realpath(os.path.join(safe_dir, relative_path))

        # 3. CodeQL-compliant boundary check using .startswith()
        if not target_path.startswith(safe_dir):
            logger.warning(
                "[SocialMedia] Rejected image path outside upload directory: %s",
                relative_path,
            )
            return Path()

        # Return a Path object to keep the rest of your app functioning as normal
        return Path(target_path)

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
