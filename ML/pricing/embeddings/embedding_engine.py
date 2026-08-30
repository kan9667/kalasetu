"""
Multimodal Embedding Engine.

Wraps Google's Gemini multimodal embedding model to generate unified vectors
from both product images and text descriptions.

The same embedding model is used for:
1. Indexing benchmark (competitor) products
2. Generating query vectors for artisan uploads

This ensures that both live in the same vector space and cosine similarity
search produces meaningful results.
"""

from __future__ import annotations

import base64
import logging
import time
from pathlib import Path
from typing import Optional

from google import genai
from google.genai import types

from ..config import get_settings

logger = logging.getLogger(__name__)


class EmbeddingEngine:
    """
    Generates multimodal embeddings using Google Gemini's embedding model.

    Supports embedding combinations of:
    - Text only
    - Image only (from local file path or URL)
    - Image + Text (multimodal — recommended for best results)
    """

    def __init__(self):
        settings = get_settings()
        self.client = genai.Client(api_key=settings.gemini_api_key) if settings.gemini_api_key else None
        self.model = settings.embedding_model
        self.retry_attempts = settings.embedding_retry_attempts

    def _fallback_embedding(self, content: str) -> list[float]:
        """Generate deterministic fallback embedding when API key is not present."""
        import hashlib
        h = hashlib.sha256(content.encode()).digest()
        # Create a unit normalized pseudo-vector of 768 dimensions
        vec = [(b / 255.0) - 0.5 for b in h] * 24
        norm = sum(x*x for x in vec) ** 0.5
        return [x / norm for x in vec]

    def embed_text(self, text: str) -> list[float]:
        """Generate an embedding from text only."""
        if not self.client:
            return self._fallback_embedding(text)

        for attempt in range(self.retry_attempts):
            try:
                response = self.client.models.embed_content(
                    model=self.model,
                    contents=text,
                )
                return response.embeddings[0].values
            except Exception as e:
                logger.warning(
                    "Text embedding attempt %d/%d failed: %s",
                    attempt + 1,
                    self.retry_attempts,
                    e,
                )
                if attempt < self.retry_attempts - 1:
                    time.sleep(2 ** (attempt + 1))

        return self._fallback_embedding(text)

    def embed_image(self, image_path: str) -> list[float]:
        """Generate an embedding from a local image file."""
        return self.embed_multimodal(image_path=image_path, text=None)

    def embed_multimodal(
        self,
        image_path: Optional[str] = None,
        text: Optional[str] = None,
    ) -> list[float]:
        """
        Generate a unified multimodal embedding from an image and/or text.

        This is the primary method — use it for both indexing and querying
        to keep everything in the same vector space.

        Args:
            image_path: Path to a local image file (jpg, png, webp).
            text: Text description of the product.

        Returns:
            A list of floats representing the embedding vector.
        """
        if not image_path and not text:
            raise ValueError("At least one of image_path or text must be provided")

        # Build content parts
        parts = []

        if image_path and Path(image_path).exists():
            # Read and encode the image
            image_bytes = Path(image_path).read_bytes()
            mime_type = self._get_mime_type(image_path)

            parts.append(
                types.Part.from_bytes(
                    data=image_bytes,
                    mime_type=mime_type,
                )
            )

        if text:
            parts.append(types.Part.from_text(text=text))

        # If we only have text (no valid image), fall back to text embedding
        if len(parts) == 1 and text and not (image_path and Path(image_path).exists()):
            return self.embed_text(text)

        if not self.client:
            return self._fallback_embedding(text or "multimodal_craft")

        # Generate multimodal embedding
        for attempt in range(self.retry_attempts):
            try:
                response = self.client.models.embed_content(
                    model=self.model,
                    contents=types.Content(parts=parts),
                )
                return response.embeddings[0].values
            except Exception as e:
                logger.warning(
                    "Multimodal embedding attempt %d/%d failed: %s",
                    attempt + 1,
                    self.retry_attempts,
                    e,
                )
                if attempt < self.retry_attempts - 1:
                    time.sleep(2 ** (attempt + 1))

        return self._fallback_embedding(text or "multimodal_craft")

    def embed_batch(
        self,
        items: list[dict],
        batch_size: int = 10,
    ) -> list[list[float]]:
        """
        Embed a batch of items, each with optional 'image_path' and 'text' keys.

        Args:
            items: List of dicts with 'image_path' and/or 'text' keys.
            batch_size: Number of items to process before a rate-limit pause.

        Returns:
            List of embedding vectors in the same order as input items.
        """
        settings = get_settings()
        vectors: list[list[float]] = []

        for i, item in enumerate(items):
            try:
                vector = self.embed_multimodal(
                    image_path=item.get("image_path"),
                    text=item.get("text"),
                )
                vectors.append(vector)
            except Exception as e:
                logger.error("Failed to embed item %d: %s", i, e)
                # Use a zero vector as placeholder for failed items
                # (will have low similarity to everything)
                if vectors:
                    vectors.append([0.0] * len(vectors[0]))
                else:
                    vectors.append([0.0] * 768)  # Default dimension

            # Rate limiting between batches
            if (i + 1) % batch_size == 0:
                logger.info(
                    "Embedded %d/%d items, pausing for rate limit...",
                    i + 1,
                    len(items),
                )
                time.sleep(2.0)

        return vectors

    @staticmethod
    def _get_mime_type(file_path: str) -> str:
        """Determine MIME type from file extension."""
        ext = Path(file_path).suffix.lower()
        mime_map = {
            ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg",
            ".png": "image/png",
            ".webp": "image/webp",
            ".gif": "image/gif",
            ".bmp": "image/bmp",
        }
        return mime_map.get(ext, "image/jpeg")
