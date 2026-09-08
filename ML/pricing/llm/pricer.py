"""
LLM Pricer — Gemini-based intelligent price calculation.

Constructs a multimodal prompt with the artisan's product details and
retrieved market comparables, then uses structured JSON output to get
a well-reasoned price recommendation.

Key design principle: the LLM will NEVER suggest a price below the
artisan's cost floor (materials + labor + transport + overhead).
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Optional

from google import genai
from google.genai import types

from ..config import get_settings
from ..models import CostInputs, PricingResult, SimilarProduct

try:
    from backend.services.groq_client import GroqClient
except ImportError:
    GroqClient = None

logger = logging.getLogger(__name__)


# ── Pricing Prompt Template ─────────────────────────────────────────────────

PRICING_SYSTEM_PROMPT = """You are an expert pricing analyst specializing in Indian handicrafts and artisan products. Your role is to suggest a fair market price for handmade products created by marginalized artisans.

## Your Principles:
1. **Cost Floor Integrity:**
   - If the artisan provided a cost breakdown, **NEVER** suggest a price below their cost floor.
   - If NO cost inputs were provided (cost floor is ₹0), **DO NOT FABRICATE OR INVENT** cost figures (such as "materials ₹150 + labor ₹360"). Price based strictly on fair market value, art/craft complexity, and category standards.
2. Factor in the uniqueness of handmade products — they deserve a premium over mass-produced goods.
3. Consider the skill level, time invested, and cultural significance of the craft.
4. Use the comparable market products to anchor your pricing in reality — BUT only when they are genuinely similar.
5. Account for the platform (online vs. fair), target buyer, and seasonal demand.
6. Provide a price RANGE (low–high) along with your primary suggestion.
7. Be transparent about your reasoning so the artisan understands the value of their work.

## Critical Rule — Comparable Relevance:
Each comparable product is tagged with a similarity score (0–100%) and a quality label:
- **Excellent (≥80%)** — strong match; weight heavily.
- **Good (60–79%)** — reasonable match; use with moderate confidence.
- **Fair (< 60%)** — weak match; treat as loose context only, do NOT let it dominate the price.

If all comparables are Fair or the match quality summary shows low average similarity, rely primarily
on the cost floor, product description, and general handicraft market knowledge instead.
NEVER anchor the price on a comparable from a completely different product category.

## Output Format:
Return a JSON object with these exact fields:
- suggested_price: Your primary recommended price in INR (number)
- price_range_low: Lower bound of acceptable price range in INR (number)
- price_range_high: Upper bound of acceptable price range in INR (number)
- confidence_score: How confident you are in this suggestion (0.0–1.0)
- reasoning: A clear explanation of how you arrived at this price (string)
- market_position: Where this product sits — "budget", "mid-range", "premium", or "luxury" (string)"""


PRICING_USER_PROMPT_TEMPLATE = """## Artisan's Product
**Description:** {description}
{category_line}
{cost_floor_section}

## Market Comparables — Match Quality Summary
- Comparables retrieved: {num_comparables}
- Average similarity: {avg_similarity:.0%}
- Minimum similarity: {min_similarity:.0%}
{quality_warning}

## Market Comparables (sorted by relevance)
{comparables_text}

## Task
Based on the artisan's product and the market comparables above, calculate a fair suggested price.
{cost_floor_instruction}
Weight each comparable according to its similarity score — low-similarity comparables should have
little influence on the final price.

Return your response as a valid JSON object with the fields: suggested_price, price_range_low, price_range_high, confidence_score, reasoning, market_position."""


class LLMPricer:
    """
    Uses Gemini LLM to calculate intelligent price recommendations
    based on the artisan's product and market comparables.
    """

    def __init__(self):
        settings = get_settings()
        self.groq_client = GroqClient() if GroqClient else None
        self.client = genai.Client(api_key=settings.gemini_api_key) if settings.gemini_api_key else None
        self.model = settings.llm_model

    def calculate_price(
        self,
        description: str,
        comparables: list[SimilarProduct],
        cost_inputs: Optional[CostInputs] = None,
        image_path: Optional[str] = None,
        category: Optional[str] = None,
    ) -> PricingResult:
        """
        Calculate a price recommendation using Groq or Gemini LLM.
        """
        # Calculate cost floor
        cost_floor = 0.0
        if cost_inputs:
            cost_floor = cost_inputs.cost_floor

        has_groq = bool(self.groq_client and self.groq_client.is_available())
        if not self.client and not has_groq:
            return self._fallback_pricing(
                comparables=comparables,
                cost_floor=cost_floor,
                description=description,
            )

        # Build the comparables text block
        comparables_text = self._format_comparables(comparables)

        # Compute match quality summary stats for the prompt
        if comparables:
            similarities = [c.similarity_score for c in comparables]
            avg_similarity = sum(similarities) / len(similarities)
            min_similarity = min(similarities)
        else:
            avg_similarity = 0.0
            min_similarity = 0.0

        if avg_similarity < 0.60:
            if cost_floor > 0:
                quality_warning = (
                    "⚠️  **Low match quality** — comparables are not closely related to this "
                    "product. Rely primarily on cost floor and category knowledge."
                )
            else:
                quality_warning = (
                    "⚠️  **Low match quality** — comparables are not closely related to this "
                    "product. Rely on product description, craft complexity, and category market knowledge."
                )
        elif avg_similarity < 0.75:
            quality_warning = (
                "ℹ️  Moderate match quality — use comparables as loose guidance only."
            )
        else:
            quality_warning = "✅ Good match quality — comparables are reliable price anchors."

        # Build the cost section
        if cost_inputs and cost_floor > 0:
            cost_floor_section = (
                f"\n**Cost Breakdown (provided by artisan):**\n"
                f"- Raw materials: ₹{cost_inputs.materials:,.0f}\n"
                f"- Labor: {cost_inputs.labor_hours} hours × ₹{cost_inputs.hourly_rate or 50}/hr = ₹{cost_inputs.labor_hours * (cost_inputs.hourly_rate or 50):,.0f}\n"
                f"- Transport: ₹{cost_inputs.transport:,.0f}\n"
                f"- Overhead: ₹{cost_inputs.overhead:,.0f}\n"
                f"- **Total Cost Floor: ₹{cost_floor:,.0f}** (DO NOT price below this)\n"
            )
            cost_floor_instruction = f"Remember: the suggested price MUST be at or above the artisan's cost floor of ₹{cost_floor:.0f}."
        else:
            cost_floor_section = "\n**Cost Breakdown:** None provided. Do NOT invent or assume raw material or labor costs."
            cost_floor_instruction = "No cost floor was specified. Do NOT invent fabricated material or labor figures in your reasoning. Estimate fair market value based on product type, art complexity, and market comparables."

        category_line = f"**Category:** {category}" if category else ""

        # Build the user prompt
        user_prompt = PRICING_USER_PROMPT_TEMPLATE.format(
            description=description,
            category_line=category_line,
            cost_floor_section=cost_floor_section,
            num_comparables=len(comparables),
            comparables_text=comparables_text,
            cost_floor_instruction=cost_floor_instruction,
            avg_similarity=avg_similarity,
            min_similarity=min_similarity,
            quality_warning=quality_warning,
        )

        raw_json = None
        last_exception = None

        # ── 1. Try Groq Cloud first ─────────────────────────────────────────
        if has_groq:
            try:
                groq_prompt = (
                    f"{user_prompt}\n\n"
                    "Respond with ONLY a valid JSON object matching keys: "
                    "suggested_price, price_range_low, price_range_high, confidence_score, reasoning, market_position."
                )
                groq_messages = [
                    {"role": "system", "content": PRICING_SYSTEM_PROMPT},
                    {"role": "user", "content": groq_prompt},
                ]
                raw_json = self.groq_client.chat_json_sync(groq_messages)
                logger.info("[LLMPricer] Groq pricing recommendation generated: %s", raw_json)
            except Exception as e:
                logger.warning("[LLMPricer] Groq pricing attempt failed, trying Gemini: %s", e)

        # ── 2. Fallback to Gemini if Groq did not provide raw_json ──────────
        if not raw_json and self.client:
            # Build content parts (multimodal if image is available)
            contents = []

            if image_path and Path(image_path).exists():
                image_bytes = Path(image_path).read_bytes()
                mime_type = self._get_mime_type(image_path)
                contents.append(
                    types.Part.from_bytes(data=image_bytes, mime_type=mime_type)
                )

            contents.append(types.Part.from_text(text=user_prompt))

            candidate_models = [self.model]
            for fallback_m in ["gemini-3.6-flash", "gemini-3.5-flash", "gemini-flash-latest", "gemini-3.7-flash"]:
                if fallback_m not in candidate_models:
                    candidate_models.append(fallback_m)

            for model_name in candidate_models:
                try:
                    response = self.client.models.generate_content(
                        model=model_name,
                        contents=types.Content(parts=contents),
                        config=types.GenerateContentConfig(
                            system_instruction=PRICING_SYSTEM_PROMPT,
                            temperature=0.3,  # Low temp for consistent pricing
                            response_mime_type="application/json",
                            response_schema={
                                "type": "object",
                                "properties": {
                                    "suggested_price": {"type": "number"},
                                    "price_range_low": {"type": "number"},
                                    "price_range_high": {"type": "number"},
                                    "confidence_score": {"type": "number"},
                                    "reasoning": {"type": "string"},
                                    "market_position": {"type": "string"},
                                },
                                "required": [
                                    "suggested_price",
                                    "price_range_low",
                                    "price_range_high",
                                    "confidence_score",
                                    "reasoning",
                                    "market_position",
                                ],
                            },
                        ),
                    )
                    raw_json = json.loads(response.text)
                    logger.info("LLM pricing response from %s: %s", model_name, raw_json)
                    break
                except Exception as e:
                    last_exception = e
                    logger.warning("Pricing attempt with model %s failed: %s", model_name, e)

        if not raw_json:
            logger.error("All LLM pricing attempts failed. Last error: %s", last_exception)
            return self._fallback_pricing(comparables, cost_floor, description)

        try:

            # Enforce cost floor
            suggested = raw_json["suggested_price"]
            range_low = raw_json["price_range_low"]
            range_high = raw_json["price_range_high"]

            if cost_floor > 0:
                if suggested < cost_floor:
                    logger.warning(
                        "LLM suggested ₹%.0f below cost floor ₹%.0f — adjusting",
                        suggested,
                        cost_floor,
                    )
                    suggested = cost_floor * 1.2  # 20% markup above cost
                    raw_json["reasoning"] += (
                        f" [Adjusted: original suggestion was below cost floor of ₹{cost_floor:.0f}]"
                    )

                range_low = max(range_low, cost_floor)
                range_high = max(range_high, suggested * 1.1)

            return PricingResult(
                suggested_price=round(suggested, 0),
                price_range_low=round(range_low, 0),
                price_range_high=round(range_high, 0),
                cost_floor=cost_floor,
                confidence_score=min(1.0, max(0.0, raw_json["confidence_score"])),
                reasoning=raw_json["reasoning"],
                comparable_products=comparables,
                market_position=raw_json.get("market_position", "mid-range"),
            )

        except Exception as e:
            logger.error("LLM pricing failed: %s", e)
            # Fallback: simple comparable-based pricing
            return self._fallback_pricing(comparables, cost_floor, description)

    @staticmethod
    def _similarity_label(score: float) -> str:
        """Return a human-readable quality label for a similarity score."""
        if score >= 0.80:
            return "Excellent"
        elif score >= 0.60:
            return "Good"
        else:
            return "Fair"

    def _format_comparables(self, comparables: list[SimilarProduct]) -> str:
        """Format comparable products as a readable text block for the prompt."""
        if not comparables:
            return "No comparable products found in the market database."

        lines = []
        for i, comp in enumerate(comparables, 1):
            label = self._similarity_label(comp.similarity_score)
            lines.append(
                f"{i}. **{comp.title}**\n"
                f"   - Price: ₹{comp.selling_price:,.0f}\n"
                f"   - Category: {comp.category}\n"
                f"   - Platform: {comp.source_platform}\n"
                f"   - Similarity: {comp.similarity_score:.2%} [{label} match]\n"
                f"   - Description: {comp.description[:200] if comp.description else 'N/A'}"
            )
        return "\n\n".join(lines)

    def _fallback_pricing(
        self,
        comparables: list[SimilarProduct],
        cost_floor: float,
        description: str,
    ) -> PricingResult:
        """
        Fallback pricing when the LLM call fails.

        Uses weighted average of comparable prices with cost floor enforcement.
        """
        logger.warning("Using fallback pricing (LLM unavailable)")

        if comparables:
            # Weighted average by similarity score
            total_weight = sum(c.similarity_score for c in comparables)
            if total_weight > 0:
                weighted_price = sum(
                    c.selling_price * c.similarity_score for c in comparables
                ) / total_weight
            else:
                weighted_price = sum(c.selling_price for c in comparables) / len(
                    comparables
                )

            suggested = max(weighted_price, cost_floor * 1.2 if cost_floor > 0 else weighted_price)
            prices = [c.selling_price for c in comparables]
            range_low = max(min(prices) * 0.9, cost_floor)
            range_high = max(prices) * 1.1
        else:
            # No comparables at all — pure cost-based
            suggested = cost_floor * 2.0 if cost_floor > 0 else 500.0
            range_low = cost_floor if cost_floor > 0 else 300.0
            range_high = suggested * 1.5

        return PricingResult(
            suggested_price=round(suggested, 0),
            price_range_low=round(range_low, 0),
            price_range_high=round(range_high, 0),
            cost_floor=cost_floor,
            confidence_score=0.4,
            reasoning=(
                "Fallback pricing: based on weighted average of comparable products "
                "with cost floor enforcement. LLM analysis was unavailable."
            ),
            comparable_products=comparables,
            market_position="mid-range",
        )

    @staticmethod
    def _get_mime_type(file_path: str) -> str:
        """Determine MIME type from file extension."""
        ext = Path(file_path).suffix.lower()
        return {
            ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg",
            ".png": "image/png",
            ".webp": "image/webp",
            ".gif": "image/gif",
        }.get(ext, "image/jpeg")
