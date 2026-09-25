"""
Catalog Service.

Integrates:
1. Speech-to-Text (STT) via ML.voice_pipeline (Whisper + Craft Glossary biasing).
2. Bilingual AI Catalog Listing Generation (English + Hindi) with craft vocabulary injection.
3. Cost Cue Extraction from artisan speech.
4. Non-blocking AI Image Enhancement (rembg / CV pipeline).
5. Complete Voice-to-Product Pipeline orchestration (Voice -> Listing -> Pricing -> Draft).
"""

from __future__ import annotations

import asyncio
import os
import sys
import json
import logging
import re
import subprocess
from pathlib import Path
from typing import Optional, List
from starlette.concurrency import run_in_threadpool
from google import genai
from google.genai import types
from sqlalchemy.orm import Session

# Setup path to import ML pipelines
_PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

# Import Voice Pipeline
from ML.voice_pipeline.orchestrator.processor import ArtisanVoiceProcessor
from ML.voice_pipeline.glossary import build_prompt_hint, get_glossary_terms
from ML.voice_pipeline.models import JobStatus

# Image Pipeline Enhancer is lazy-loaded inside enhance_product_photo() to avoid import-time ML penalties
run_ml_enhancer = None

from .groq_client import GroqClient
from ..config import get_settings
from ..utils.cost_extraction import regex_extract_cost_cues, DEFAULT_HOURLY_RATE
from ..models.schemas import (
    AudioTranscribeResponse,
    ListingGenerateRequest,
    ListingGenerateResponse,
    PriceSuggestRequest,
    PriceSuggestResponse,
    CostInputsSchema,
    ProductCreate,
    VoiceToProductResponse,
    VoiceGlossaryResponse,
)

class VoiceServiceUnavailableException(Exception):
    """Raised when voice transcription service encounters a transient upstream failure or timeout."""
    pass


class InvalidAudioException(Exception):
    """Raised when uploaded audio is corrupt, missing, or in an unsupported format."""
    pass


logger = logging.getLogger(__name__)


INSUFFICIENT_INFO_GREETINGS = {
    "hello", "hi", "hey", "namaste", "namaskar", "pranam", "test", "testing",
    "mic", "check", "audio", "one", "two", "three", "1", "2", "3", "bhaiya",
    "bhai", "haan", "theek", "bolo", "sun", "sunai", "de", "raha", "rahi", "hai",
    "aa", "aawaz", "kya", "ok", "okay", "yes", "no", "sir", "madam", "hallo",
    "हेलो", "नमस्ते", "नमस्कार", "प्रणाम", "माइक", "टेस्टिंग", "चेक", "हाँ",
    "ठीक", "बोलो", "सुनो", "सुनाई", "दे", "रहा", "आवाज़", "आ", "रही", "क्या",
    "एक", "दो", "तीन", "भैया", "भाई"
}


def is_insufficient_product_info(transcript: str) -> bool:
    if not transcript:
        return True
    cleaned = re.sub(r"[^\w\s]", " ", transcript.lower())
    words = [w for w in cleaned.split() if w]
    if not words:
        return True
    noise_count = sum(1 for w in words if w in INSUFFICIENT_INFO_GREETINGS)
    if len(words) <= 5 and noise_count >= len(words) - 1:
        return True
    if len(words) > 5 and (noise_count / len(words)) >= 0.85:
        return True
    return False


class CatalogService:
    """Provides speech-to-text, image enhancement, and bilingual catalog listing generation."""

    def __init__(self):
        self.settings = get_settings()
        self.groq_client = GroqClient()
        self.client = (
            genai.Client(api_key=self.settings.gemini_api_key)
            if self.settings.gemini_api_key and (
                self.settings.llm_provider == "gemini"
                or self.settings.catalog_gemini_fallback_enabled
            )
            else None
        )
        logger.info(
            "[CatalogService] Selected provider=%s model=%s credentials_present=%s gemini_fallback_enabled=%s",
            self.settings.llm_provider,
            self.settings.groq_chat_model if self.settings.llm_provider == "groq" else self.settings.llm_model,
            self.groq_client.is_available() if self.settings.llm_provider == "groq" else bool(self.client),
            self.settings.catalog_gemini_fallback_enabled,
        )
        self.voice_processor = ArtisanVoiceProcessor()
        self._pricing_service = None

    @property
    def pricing_service(self):
        """Persistent lazily-initialized PricingService instance."""
        if self._pricing_service is None:
            from .pricing_service import PricingService
            self._pricing_service = PricingService()
        return self._pricing_service

    # ── Image Enhancement ───────────────────────────────────────────────────

    async def enhance_product_photo(
        self,
        input_path: str,
        output_path: Optional[str] = None,
    ) -> str:
        """
        Run the 11-stage AI image enhancement pipeline in a threadpool to prevent
        blocking FastAPI's async event loop.
        """
        global run_ml_enhancer
        degraded_reason = None
        if run_ml_enhancer is None:
            try:
                from ML.image_pipeline.enhancer import enhance_image as _dyn_enhancer
                run_ml_enhancer = _dyn_enhancer
            except Exception as import_err:
                degraded_reason = f"ML image enhancer dynamic import failed: {import_err}"
                logger.warning("[CatalogService] %s", degraded_reason)

        if run_ml_enhancer is not None:
            try:
                enhanced_path = await run_in_threadpool(
                    run_ml_enhancer,
                    input_path=input_path,
                    output_path=output_path,
                )
                if enhanced_path and Path(enhanced_path).is_file():
                    return (str(enhanced_path), False, None)
            except Exception as e:
                degraded_reason = f"Image enhancement execution failed: {e}"
                logger.error("[CatalogService] %s, falling back to input image", degraded_reason)

        # Fallback: copy input image to output path if specified, or return input path
        reason = degraded_reason or "AI enhancement unavailable; raw image preserved"
        if output_path:
            import shutil
            shutil.copy2(input_path, output_path)
            return (output_path, True, reason)
        return (input_path, True, reason)


    # ── Voice Transcription (ML Voice Pipeline) ─────────────────────────────

    @staticmethod
    def _is_audio_silent(path: Path) -> bool:
        """Check if audio has no audible sound using ffmpeg volumedetect."""
        try:
            result = subprocess.run(
                [
                    "ffmpeg", "-i", str(path), "-af", "volumedetect",
                    "-vn", "-sn", "-dn", "-f", "null", "/dev/null"
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=5,
            )
            for line in result.stderr.splitlines():
                if "max_volume:" in line:
                    parts = line.split("max_volume:")
                    if len(parts) > 1:
                        vol_str = parts[1].replace("dB", "").strip()
                        max_vol = float(vol_str)
                        return max_vol < -40.0
        except Exception:
            pass
        return False

    @staticmethod
    def _is_silence_hallucination(text: str) -> bool:
        """Detect common Whisper hallucinations triggered by silent audio."""
        if not text:
            return True
        clean = re.sub(r'[\s\.,!?:;\-_"\'()[\]{}।…~*]+', ' ', text).strip().lower()
        silence_artifacts = {
            "thanks", "thank you", "thanks for watching", "thank you for watching",
            "thanks for listening", "thank you for listening", "thank you very much",
            "thank you so much", "please subscribe", "subscribe", "subtitles",
            "subtitles by", "bye", "bye bye", "you", "goodbye", "peace",
            "watching", "so", "the end", "see you next time", "thanks guys", "thank you all",
            "धन्यवाद", "बहुत धन्यवाद", "शुक्रिया", "बहुत शुक्रिया",
            "प्रस्तुत", "प्रश्नित", "प्रश्नित प्रश्नित", "झाल", "सब्सक्राइब करें",
            "लाइक करें", "शेयर करें", "चैनल को सब्सक्राइब करें",
        }
        if clean in silence_artifacts:
            return True
        words = clean.split()
        if len(words) <= 6:
            if ("thank" in clean or "thanks" in clean) and "watching" in clean:
                return True
            for prefix in ["thanks", "thank you", "bye", "goodbye", "subtitles", "subscribe", "धन्यवाद", "शुक्रिया"]:
                if clean.startswith(prefix):
                    return True
        return False

    async def transcribe_audio(
        self,
        audio_file_path: str,
        language_code: str = "auto",
        category_hint: Optional[str] = None,
        note_id: Optional[str] = None,
    ) -> AudioTranscribeResponse:
        """
        Transcribe an artisan's regional voice note using the ML voice pipeline
        (Whisper with craft glossary prompt biasing).
        """
        path = Path(audio_file_path)
        if not path.exists():
            raise InvalidAudioException(f"Audio file not found: {audio_file_path}")

        # Check for silent audio before running heavy Whisper processing (non-blocking threadpool)
        is_silent = await run_in_threadpool(self._is_audio_silent, path)
        if is_silent:
            logger.warning("Audio file %s is silent (volume < -40dB).", path.name)
            return AudioTranscribeResponse(
                transcript="",
                language_code=language_code or "hi",
                detected_language=language_code or "hi",
                duration_seconds=0.0,
                provider="whisper",
                is_fallback=True,
                status="no_speech",
                fallback_reason="no_speech",
            )

        result = await run_in_threadpool(
            self.voice_processor.process_voice_note,
            audio_path=str(path),
            language_code=language_code,
            category_hint=category_hint,
            note_id=note_id,
        )

        if result.status == JobStatus.FAILED or not result.transcript or not result.transcript.is_usable():
            fallback_reason = (result.transcript.fallback_reason if result.transcript else "") or result.error or ""
            if "No audible speech detected" in fallback_reason or fallback_reason == "no_speech":
                return AudioTranscribeResponse(
                    transcript="",
                    language_code=language_code or "hi",
                    detected_language=language_code or "hi",
                    duration_seconds=0.0,
                    provider="whisper",
                    is_fallback=True,
                    status="no_speech",
                    fallback_reason="no_speech",
                )
            if "invalid_audio_format" in fallback_reason or "ValueError" in fallback_reason or "Audio file" in fallback_reason:
                logger.warning("Voice pipeline invalid audio failure: %s", fallback_reason)
                raise InvalidAudioException(f"Invalid audio format or content: {fallback_reason}")

            logger.error("Voice pipeline transcription failure: %s", fallback_reason)
            raise VoiceServiceUnavailableException("Voice transcription service temporarily unavailable.")

        transcript_text = result.transcript.text.strip()
        if self._is_silence_hallucination(transcript_text):
            logger.warning("Whisper silence hallucination detected (%d chars). Marking as no_speech.", len(transcript_text))
            return AudioTranscribeResponse(
                transcript="",
                language_code=result.transcript.language_code,
                detected_language=result.transcript.language_code,
                duration_seconds=result.transcript.duration_seconds,
                provider=result.transcript.provider.value if hasattr(result.transcript.provider, "value") else str(result.transcript.provider),
                is_fallback=True,
                status="no_speech",
                fallback_reason="no_speech",
            )

        return AudioTranscribeResponse(
            transcript=transcript_text,
            language_code=result.transcript.language_code,
            detected_language=result.transcript.language_code,
            duration_seconds=result.transcript.duration_seconds,
            provider=result.transcript.provider.value if hasattr(result.transcript.provider, "value") else str(result.transcript.provider),
            is_fallback=result.transcript.is_fallback,
            status=result.status.value,
            fallback_reason=result.transcript.fallback_reason if result.transcript else None,
        )

    # ── Bilingual Listing Sanitizers & Rules ────────────────────────────────

    @staticmethod
    def _sanitize_customer_facing_text(text: str) -> str:
        """
        Purge internal manufacturing costs, raw material costs, hourly rates,
        and wage figures from customer-facing e-commerce titles/descriptions.
        """
        if not text:
            return ""

        # Split text into sentences/phrases (handles English and Hindi punctuation)
        sentences = re.split(r"(?<=[.!?।\n])\s+", text)
        cleaned_sentences = []

        cost_trigger = re.compile(
            r"(?i)(?:"
            r"₹\s*\d+|"
            r"\b(?:rs\.?|inr)\s*\d+|"
            r"\b\d+\s*(?:rupees|rs\.?|inr|रुपये|रुपया|रु)\b|"
            r"cost\s+of\s+making|making\s+cost|base\s+cost|raw\s+material\s+cost|production\s+cost|"
            r"manufacturing\s+cost|labor\s+cost|material\s+cost|cost\s+price|hourly\s+rate|artisan\s+wage|"
            r"took\s+\d+\s*(?:hours?|hrs?|days?)|takes\s+\d+\s*(?:hours?|hrs?|days?)|"
            r"लागत|खर्च|मजदूरी|कच्चा\s*माल|घंटे\s*लगे|दिन\s*लगे"
            r")"
        )

        for s in sentences:
            s_clean = s.strip()
            if not s_clean:
                continue
            # If the sentence contains a cost/production cue, check if it can be split or dropped
            if cost_trigger.search(s_clean):
                sub_clauses = re.split(r"(?<=;)\s+|(?<=[,])\s+(?=[A-Z\u0900-\u097F])", s_clean)
                surviving = [c.strip() for c in sub_clauses if not cost_trigger.search(c) and len(c.strip()) > 5]
                if surviving:
                    cleaned_sentences.append("; ".join(surviving))
                continue
            cleaned_sentences.append(s_clean)

        result = " ".join(cleaned_sentences)
        # Final sweep for any standalone price/currency mentions
        result = re.sub(r"(?i)(?:₹|rs\.?|inr)\s*\d+(?:,\d+)*(?:\.\d+)?", "", result)
        result = re.sub(r"(?i)\b\d+(?:,\d+)*(?:\.\d+)?\s*(?:rupees|rs\.?|inr|रुपये|रुपया|रु)\b", "", result)
        result = re.sub(r"\s+([,.;:?!।])", r"\1", result)
        result = re.sub(r"[,;]\s*[,;]+", ", ", result)
        result = re.sub(r"\.\s*\.+", ". ", result)
        result = re.sub(r"\s{2,}", " ", result)
        return result.strip(" ,.-;")

    @staticmethod
    def _sanitize_tags(tags: List[str]) -> List[str]:
        """Remove any tags containing costs, digits, or price-related terms."""
        clean_tags = []
        bad_substrings = ["cost", "price", "rupee", "rs", "inr", "making", "wage", "labor", "labour", "hour"]
        for tag in tags:
            t = str(tag).strip().lower()
            if not t or len(t) < 2 or len(t) > 35:
                continue
            if any(char.isdigit() for char in t):
                continue
            if any(bad in t for bad in bad_substrings):
                continue
            clean_tags.append(t)
        return clean_tags or ["handcrafted", "artisan", "traditional", "indian-handicrafts"]

    async def _generate_listing_text(
        self,
        system_prompt: str,
        user_prompt: str,
        category_hint: Optional[str],
        effective_category: Optional[str],
    ) -> Optional[tuple[str, str, str, str, str, List[str]]]:
        # Groq is primary; Gemini fallback is explicitly configurable.
        if self.groq_client.is_available() and self.settings.llm_provider == "groq":
            try:
                groq_messages = [
                    {
                        "role": "system",
                        "content": (
                            system_prompt
                            + "\n\nCRITICAL: Respond ONLY with a valid JSON object matching the keys: "
                            "title_en, title_hi, description_en, description_hi, category, tags. "
                            "No markdown fences, no extra text."
                        ),
                    },
                    {"role": "user", "content": user_prompt},
                ]
                # GPT-OSS spends part of this budget on reasoning. The previous
                # 800-token default truncated bilingual JSON and Groq returned
                # json_validate_failed (HTTP 400) for realistic listing prompts.
                data = await self.groq_client.chat_json(groq_messages, max_tokens=2400)
                return (
                    self._sanitize_customer_facing_text(data.get("title_en", "Handcrafted Artisan Product")),
                    self._sanitize_customer_facing_text(data.get("title_hi", "हस्तनिर्मित उत्पाद")),
                    self._sanitize_customer_facing_text(data.get("description_en", "")),
                    self._sanitize_customer_facing_text(data.get("description_hi", "")),
                    data.get("category") if isinstance(data.get("category"), str) and data["category"].strip()
                    else category_hint or effective_category or "General",
                    self._sanitize_tags(data.get("tags", ["handmade", "handicraft", "artisan"])),
                )
            except Exception as e:
                logger.warning("[CatalogService] Groq listing generation failed (%s); checking configured fallback", type(e).__name__)

        if self.settings.llm_provider == "groq":
            if not self.groq_client.is_available():
                logger.warning("[CatalogService] Groq unavailable: configure GROQ_API_KEY and restart the backend")
            if not self.settings.catalog_gemini_fallback_enabled:
                return None

        if self.client and (self.settings.llm_provider == "gemini" or self.settings.catalog_gemini_fallback_enabled):
            if self.settings.llm_provider == "groq":
                logger.warning("[CatalogService] Listing provider fallback: Groq -> Gemini")
            try:
                response = await run_in_threadpool(
                    self.client.models.generate_content,
                    model=self.settings.llm_model,
                    contents=user_prompt,
                    config=types.GenerateContentConfig(
                        system_instruction=system_prompt,
                        temperature=0.2,
                        response_mime_type="application/json",
                        response_schema={
                            "type": "object",
                            "properties": {
                                "title_en": {"type": "string"},
                                "title_hi": {"type": "string"},
                                "description_en": {"type": "string"},
                                "description_hi": {"type": "string"},
                                "category": {"type": "string"},
                                "tags": {
                                    "type": "array",
                                    "items": {"type": "string"},
                                },
                            },
                            "required": [
                                "title_en",
                                "title_hi",
                                "description_en",
                                "description_hi",
                                "category",
                                "tags",
                            ],
                        },
                    ),
                )
                data = json.loads(response.text)
                return (
                    self._sanitize_customer_facing_text(data.get("title_en", "Handcrafted Artisan Product")),
                    self._sanitize_customer_facing_text(data.get("title_hi", "हस्तनिर्मित उत्पाद")),
                    self._sanitize_customer_facing_text(data.get("description_en", "")),
                    self._sanitize_customer_facing_text(data.get("description_hi", "")),
                    data.get("category") if isinstance(data.get("category"), str) and data["category"].strip()
                    else category_hint or effective_category or "General",
                    self._sanitize_tags(data.get("tags", ["handmade", "handicraft", "artisan"])),
                )
            except Exception as e:
                logger.warning("[CatalogService] Gemini listing generation failed (%s); using labeled local fallback", type(e).__name__)

        return None

    async def generate_listing(
        self,
        request: ListingGenerateRequest,
    ) -> ListingGenerateResponse:
        """
        Generate SEO-friendly, bilingual e-commerce product titles, descriptions,
        category, and search tags from an artisan's voice transcript.
        Enriches the prompt with domain craft glossary terms and enforces strict
        privacy quarantine on internal production costs.
        """
        # Check insufficient input before expensive calls
        if is_insufficient_product_info(request.transcript):
            logger.info("[CatalogService] Transcript lacks product details; returning needs_clarification response.")
            return ListingGenerateResponse(
                title_en="Product Details Needed",
                title_hi="उत्पाद विवरण की आवश्यकता है",
                description_en="Please provide details about your handcrafted product (such as craft type, materials, size, or making process) to generate a listing.",
                description_hi="कृपया अपने हस्तशिल्प उत्पाद के बारे में विवरण प्रदान करें (जैसे शिल्प का प्रकार, प्रयुक्त सामग्री, आकार आदि) ताकि पूरी सूची बनाई जा सके।",
                category=request.category_hint or "General",
                tags=[],
                cost_inputs=CostInputsSchema(
                    materials=0.0,
                    labor_hours=0.0,
                    hourly_rate=DEFAULT_HOURLY_RATE,
                    transport=0.0,
                    overhead=0.0,
                ),
                status="needs_clarification",
                is_degraded=True,
                degraded_reason="Insufficient product details in transcript. Please describe the item, materials, or craft.",
            )

        # Detect category dynamically from transcript to prevent false terracotta biasing
        lower_transcript = request.transcript.lower()
        effective_category = request.category_hint
        if any(w in lower_transcript for w in ["cloth", "silk", "cotton", "saree", "dupatta", "fabric", "weave", "kapda", "chanderi", "handloom"]):
            effective_category = "Textiles"
        elif any(w in lower_transcript for w in ["wood", "wooden", "lakdi", "carved", "teak", "sheesham", "rosewood"]):
            effective_category = "Woodwork"
        elif any(w in lower_transcript for w in ["brass", "metal", "copper", "peetal", "bronze", "dhokra", "iron"]):
            effective_category = "Brass"
        elif any(w in lower_transcript for w in ["paint", "painting", "chitra", "madhubani", "warli", "canvas", "pattachitra"]):
            effective_category = "Paintings"
        elif any(w in lower_transcript for w in ["jewelry", "jewellery", "necklace", "earring", "bangle", "ring", "silver", "gehna"]):
            effective_category = "Jewelry"
        elif any(w in lower_transcript for w in ["bamboo", "cane", "basket", "tokri", "jute"]):
            effective_category = "Bamboo Craft"
        elif any(w in lower_transcript for w in ["clay", "matti", "mitti", "pot", "pottery", "terracotta", "kulhad", "surahi", "diya"]):
            effective_category = "Pottery"

        # Inject craft glossary hints for accurate terminology
        glossary_prompt = build_prompt_hint(
            category=effective_category,
            limit=30,
            language_code=request.language_code,
        )

        system_prompt = f"""You are KalaSetu's Master Artisan Cataloger & E-Commerce Merchandising Specialist for authentic Indian handicrafts.
Your mission is to transform spoken regional voice descriptions into elite, culturally resonant, high-converting, bilingual e-commerce catalog listings.

Domain Handicraft Vocabulary Reference:
[{glossary_prompt}]

================================================================================
CRITICAL DIRECTIVES & COMPREHENSIVE RULES:
================================================================================

1. STRICT CONFIDENTIALITY & COST QUARANTINE (ZERO PRODUCTION COST LEAKAGE):
   - You MUST ABSOLUTELY NEVER mention, include, hint at, or expose internal manufacturing economics in the customer-facing title, description, or tags.
   - BANNED FROM PUBLIC LISTING:
      * Raw material expenses, total cost of making, base cost, cost price, financial production investment, transportation cost. (Note: Customer marketing phrasing like "a worthy investment for your home" or "timeless investment" is allowed).
      * Labor hours spent (e.g., "took 5 hours to make", "2 days of work"), hourly wage rates, or artisan pay.
      * Specific monetary cost amounts (e.g., "₹400", "500 rupees", "लागत", "खर्च", "मजदूरी", "कच्चा माल इतने का").
   - WHY: Internal costs are strictly private operational data used solely by the backend dynamic pricing algorithm. Disclosing production costs or maker hours to buyers cheapens the perception of art, damages artisan profit margins, and violates e-commerce marketplace standards.
   - WHAT TO DO INSTEAD: Convert statements about cost or effort into statements of premium craft quality, meticulous dedication, and material excellence. For example:
     * If the artisan says: "I spent 400 rupees on fine wood and worked 6 hours on this elephant"
     * Write: "Masterfully hand-carved from seasoned, premium-grade hardwood with exquisite artisanal dedication and intricate detailing." (NO mention of ₹400 or 6 hours).

2. E-COMMERCE TITLE ARCHITECTURE:
   - title_en: Professional, engaging, and SEO-optimized title (50-80 characters).
     Format: [Key Material / Finish] + [Craft Technique / Art Heritage] + [Product Type / Object]
     Example: "Hand-Carved Sheesham Wood Elephant Figurine with Fine Brass Inlay" or "Handwoven Pure Chanderi Silk Saree with Zari Border".
   - title_hi: Culturally authentic, grammatically natural Hindi title in Devanagari script.
     Example: "बारीक पीतल नक्काशी के साथ हाथ से तराशी गई शीशम की लकड़ी की हाथी की मूर्ति".
   - NEVER put prices, discounts, cost words, or marketing hyperbole ("Best", "Cheap", "Only ₹500") in titles.

3. RICH BILINGUAL E-COMMERCE STORYTELLING DESCRIPTIONS:
   - description_en: 2-3 engaging, cohesive paragraphs covering:
     * Paragraph 1 - Art Heritage & Identity: The cultural story, regional tradition, and distinctive personality of the handcrafted piece.
     * Paragraph 2 - Materials & Artisanal Craftsmanship: Specific materials (e.g., seasoned Indian rosewood, pure mulberry silk, organic natural dyes, hand-hammered brass) and master techniques employed.
     * Paragraph 3 - Utility, Decor & Styling: Practical dimensions, styling ideas for contemporary home decor, gifting occasions, and care instructions.
   - description_hi: Expressive, dignified, warm Hindi in Devanagari script honoring the artisan's skill (शिल्प कौशल), traditional heritage (पारंपरिक धरोहर), and natural materials (प्राकृतिक सामग्री). Do NOT use literal robotic translations.

4. PRECISE CATEGORY CLASSIFICATION & ANTI-BIAS ENFORCEMENT:
   - Identify the exact craft category from standard Indian crafts:
     * Textiles (handloom, silk, cotton, embroidery, saree, dupatta, fabric)
     * Woodwork (carved wood, sheesham, teak, sandalwood, wooden toys)
     * Brass (brass, copper, bronze, bell metal, dhokra, metal casting)
     * Pottery (terracotta, river clay, ceramic, pottery, earthen pots)
     * Jewelry (silver, beaded, tribal, brass jewelry, bangles, necklaces)
     * Paintings (Madhubani, Warli, Pattachitra, miniature, canvas art)
     * Bamboo Craft (cane, bamboo, wicker, baskets)
     * Leather Craft, Stone Craft, or Handicrafts (general)
   - CRITICAL ANTI-BIAS RULE: NEVER categorize as or hallucinate "Terracotta", "Clay", or "Pottery" unless the transcript explicitly mentions clay, mitti, or terracotta.

5. HIGH-INTENT SEO SEARCH TAGS:
   - tags: Provide 6-8 relevant, lowercase, hyphenated search tags.
   - Target buyer search queries: craft name, material, decor aesthetic, gift intent, Indian art heritage.
   - Example: ["hand-carved", "sheesham-wood", "indian-handicrafts", "elephant-figurine", "home-decor", "traditional-artisan", "wooden-craft"].
   - STRICTLY FORBIDDEN in tags: Any numbers, monetary amounts, or terms like "cost", "price", "rupee", "cheap".

6. VOCAL CONVERSATIONAL NOISE & FILLER REMOVAL:
   - Strip vocal disfluencies, mic tests, and conversational chatter from speech (e.g., "namaste", "aap dekh sakte hain", "bhaiya", "um", "ah", "matlab", "video me"). Focus solely on the craft and product attributes.

7. STRICT OUTPUT FORMAT:
   - Return ONLY a valid JSON object matching the schema:
     {{
       "title_en": string,
       "title_hi": string,
       "description_en": string,
       "description_hi": string,
       "category": string,
       "tags": [string]
     }}"""

        user_prompt = f"""Raw Artisan Voice Transcript:
"{request.transcript}"

Category Hint (if provided): {effective_category or 'Auto-detect from transcript'}

Please generate the structured bilingual catalog listing, strictly observing the cost confidentiality and quality rules."""

        # Concurrently extract cost cues and generate listing content
        cost_future = self.extract_cost_cues(request.transcript)
        listing_future = self._generate_listing_text(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            category_hint=request.category_hint,
            effective_category=effective_category,
        )

        cost_res, listing_res = await asyncio.gather(cost_future, listing_future, return_exceptions=True)

        # Handle cost cues failure independently: fallback to regex without discarding listing
        if isinstance(cost_res, Exception) or not isinstance(cost_res, CostInputsSchema):
            logger.warning("[CatalogService] Cost cue extraction failed: %s; using deterministic regex fallback", cost_res)
            regex_cues = regex_extract_cost_cues(request.transcript)
            extracted_costs = CostInputsSchema(
                materials=regex_cues["materials"],
                labor_hours=regex_cues["labor_hours"],
                hourly_rate=regex_cues["hourly_rate"],
                transport=regex_cues["transport"],
                overhead=regex_cues["overhead"],
            )
        else:
            extracted_costs = cost_res

        if isinstance(listing_res, tuple) and listing_res[0] is not None:
            # LLM succeeded!
            title_en, title_hi, desc_en, desc_hi, cat, tags = listing_res
            return ListingGenerateResponse(
                title_en=title_en,
                title_hi=title_hi,
                description_en=desc_en,
                description_hi=desc_hi,
                category=cat,
                tags=tags,
                cost_inputs=extracted_costs,
                status="success",
                is_degraded=False,
                degraded_reason=None,
            )

        # ── Offline / Mock Fallback ──────────────────────────────────────
        clean_text = self._sanitize_customer_facing_text((request.transcript or "").strip())
        detected_cat = effective_category or request.category_hint or "Handicrafts"
        title_snippet = (clean_text[:50] + "...") if len(clean_text) > 50 else clean_text
        return ListingGenerateResponse(
            title_en=f"Handcrafted {detected_cat} Item: {title_snippet}" if title_snippet else f"Handcrafted {detected_cat} Artisan Product",
            title_hi="प्रामाणिक हस्तशिल्प उत्पाद",
            description_en=clean_text or "Authentic handcrafted artisanal creation with traditional craft value.",
            description_hi="पारंपरिक कला व कारीगरी से बना प्रामाणिक हस्तशिल्प उत्पाद।",
            category=detected_cat,
            tags=self._sanitize_tags(["handcrafted", "artisan", detected_cat.lower().replace(" ", "-"), "made-in-india"]),
            cost_inputs=extracted_costs,
            status="fallback",
            is_degraded=True,
            degraded_reason=(
                "Groq is not configured. Set GROQ_API_KEY and restart the backend; using an editable draft template."
                if self.settings.llm_provider == "groq" and not self.groq_client.is_available()
                else "Configured AI listing providers unavailable; generated editable draft template."
            ),
        )

    # ── Voice Cost Cue Extractor ────────────────────────────────────────────

    async def extract_cost_cues(self, transcript: str) -> CostInputsSchema:
        """
        Extract cost cues (raw materials / base making cost, labor hours, wages)
        spoken or written by the artisan in their natural description.
        Regex baseline -> primary LLM -> optional Gemini fallback -> regex fallback.
        """
        if not transcript:
            return CostInputsSchema(
                materials=0.0,
                labor_hours=0.0,
                hourly_rate=DEFAULT_HOURLY_RATE,
                transport=0.0,
                overhead=0.0,
            )

        # 1. Deterministic baseline extraction using shared regex
        regex_result = regex_extract_cost_cues(transcript)
        base_costs = CostInputsSchema(
            materials=regex_result["materials"],
            labor_hours=regex_result["labor_hours"],
            hourly_rate=regex_result["hourly_rate"],
            transport=regex_result["transport"],
            overhead=regex_result["overhead"],
        )

        cost_prompt = f"""Analyze the following artisan voice/text transcript and extract any mentioned cost, labor, or time details:
"{transcript}"

Extract:
- materials: Cost of raw materials, base cost, or total making cost in INR (number, default 0 if not mentioned)
- labor_hours: Hours spent crafting the product (number, default 0 if not mentioned, e.g. 2 days = 16 hours, 4 hours = 4)
- hourly_rate: Hourly wage rate in INR (default 50.0 if not mentioned)
- transport: Transport/shipping cost in INR (default 0 if not mentioned)
- overhead: Additional overhead cost in INR (default 0 if not mentioned)

Return ONLY a valid JSON object matching keys: materials, labor_hours, hourly_rate, transport, overhead."""

        # 2. Try Groq Cloud if configured
        if self.groq_client.is_available() and self.settings.llm_provider == "groq":
            try:
                groq_messages = [
                    {"role": "system", "content": "You are a cost extraction assistant. Return ONLY valid JSON with keys: materials, labor_hours, hourly_rate, transport, overhead."},
                    {"role": "user", "content": cost_prompt},
                ]
                data = await self.groq_client.chat_json(groq_messages)
                mat = float(data.get("materials", 0.0) or 0.0)
                hrs = float(data.get("labor_hours", 0.0) or 0.0)
                rate = float(data.get("hourly_rate", 50.0) or 50.0)
                final_mat = mat if mat > 0 else base_costs.materials
                final_hrs = hrs if hrs > 0 else base_costs.labor_hours
                final_rate = rate if rate > 0 else (base_costs.hourly_rate if final_hrs > 0 else DEFAULT_HOURLY_RATE)
                return CostInputsSchema(
                    materials=final_mat,
                    labor_hours=final_hrs,
                    hourly_rate=final_rate,
                    transport=float(data.get("transport", 0.0) or 0.0),
                    overhead=float(data.get("overhead", 0.0) or 0.0),
                )
            except Exception as e:
                logger.warning("[CatalogService] Groq cost extraction failed (%s); checking configured fallback", type(e).__name__)

        if self.settings.llm_provider == "groq" and not self.settings.catalog_gemini_fallback_enabled:
            return base_costs

        if self.client and (self.settings.llm_provider == "gemini" or self.settings.catalog_gemini_fallback_enabled):
            try:
                response = await run_in_threadpool(
                    self.client.models.generate_content,
                    model=self.settings.llm_model,
                    contents=cost_prompt,
                    config=types.GenerateContentConfig(
                        temperature=0.0,
                        response_mime_type="application/json",
                        response_schema={
                            "type": "object",
                            "properties": {
                                "materials": {"type": "number"},
                                "labor_hours": {"type": "number"},
                                "hourly_rate": {"type": "number"},
                                "transport": {"type": "number"},
                                "overhead": {"type": "number"},
                            },
                        },
                    ),
                )
                data = json.loads(response.text)
                mat = float(data.get("materials", 0.0) or 0.0)
                hrs = float(data.get("labor_hours", 0.0) or 0.0)
                rate = float(data.get("hourly_rate", 50.0) or 50.0)
                final_mat = mat if mat > 0 else base_costs.materials
                final_hrs = hrs if hrs > 0 else base_costs.labor_hours
                final_rate = rate if rate > 0 else (base_costs.hourly_rate if final_hrs > 0 else DEFAULT_HOURLY_RATE)
                return CostInputsSchema(
                    materials=final_mat,
                    labor_hours=final_hrs,
                    hourly_rate=final_rate,
                    transport=float(data.get("transport", 0.0) or 0.0),
                    overhead=float(data.get("overhead", 0.0) or 0.0),
                )
            except Exception as e:
                logger.warning("[CatalogService] Gemini cost extraction failed (%s); using regex fallback", type(e).__name__)

        # 4. Fall back to deterministic regex extraction
        return base_costs

    # ── Voice-to-Product Pipeline Orchestrator ──────────────────────────────

    async def process_voice_to_product(
        self,
        audio_file_path: str,
        language_code: str = "auto",
        category_hint: Optional[str] = None,
        image_url: Optional[str] = None,
        audio_url: Optional[str] = None,
        cost_inputs_override: Optional[CostInputsSchema] = None,
        db: Optional[Session] = None,
    ) -> VoiceToProductResponse:
        """
        Complete end-to-end voice pipeline:
        Audio Upload -> Speech-to-Text -> Listing Generation (Description, Tags) ->
        Cost Cue Extraction -> AI Pricing Calculation -> Ready Product Draft.
        """
        pricing_service = self.pricing_service

        # Step 1: Transcribe Audio using ML Voice Pipeline
        transcribe_res = await self.transcribe_audio(
            audio_file_path=audio_file_path,
            language_code=language_code,
            category_hint=category_hint,
        )
        transcript = transcribe_res.transcript

        # Step 2: Generate Bilingual Listing (Description, Tags, Title, Category)
        detected_lang = transcribe_res.language_code or language_code
        listing_req = ListingGenerateRequest(
            transcript=transcript,
            language_code=detected_lang,
            category_hint=category_hint,
            image_url=image_url,
        )
        listing_res = await self.generate_listing(listing_req)

        # Step 3: Extract or Merge Cost Inputs
        extracted_costs = await self.extract_cost_cues(transcript)
        final_materials = (
            cost_inputs_override.materials
            if cost_inputs_override and cost_inputs_override.materials > 0
            else extracted_costs.materials
        )
        final_hours = (
            cost_inputs_override.labor_hours
            if cost_inputs_override and cost_inputs_override.labor_hours > 0
            else extracted_costs.labor_hours
        )
        final_rate = (
            cost_inputs_override.hourly_rate
            if cost_inputs_override and cost_inputs_override.hourly_rate > 0
            else extracted_costs.hourly_rate
        )
        final_transport = (
            cost_inputs_override.transport
            if cost_inputs_override and cost_inputs_override.transport > 0
            else extracted_costs.transport
        )
        final_overhead = (
            cost_inputs_override.overhead
            if cost_inputs_override and cost_inputs_override.overhead > 0
            else extracted_costs.overhead
        )

        # Step 4: Calculate Base Price & AI Pricing Recommendation
        pricing_req = PriceSuggestRequest(
            description=listing_res.description_en,
            category=listing_res.category,
            image_url=image_url,
            materials=final_materials,
            labor_hours=final_hours,
            hourly_rate=final_rate,
            transport=final_transport,
            overhead=final_overhead,
            tags=listing_res.tags,
        )
        pricing_res = await run_in_threadpool(
            pricing_service.suggest_price,
            request=pricing_req,
            db=db,
        )

        # Step 5: Construct Product Draft
        product_draft = ProductCreate(
            title=listing_res.title_en,
            title_hi=listing_res.title_hi,
            description=listing_res.description_en,
            description_hi=listing_res.description_hi,
            price=pricing_res.suggested_price,
            materials=final_materials,
            labor_hours=final_hours,
            hourly_rate=final_rate,
            transport=final_transport,
            overhead=final_overhead,
            category=listing_res.category,
            tags=listing_res.tags,
            status="draft",
        )

        return VoiceToProductResponse(
            transcript=transcript,
            language_code=language_code,
            title_en=listing_res.title_en,
            title_hi=listing_res.title_hi,
            description_en=listing_res.description_en,
            description_hi=listing_res.description_hi,
            category=listing_res.category,
            tags=listing_res.tags,
            pricing=pricing_res,
            audio_url=audio_url,
            image_url=image_url,
            product_draft=product_draft,
            status="completed",
        )

    # ── Craft Glossary Lookup ───────────────────────────────────────────────

    def get_craft_glossary(self, category: Optional[str] = None, limit: int = 50) -> VoiceGlossaryResponse:
        """Fetch craft glossary terms and all available categories."""
        terms = get_glossary_terms(category=category, limit=limit)
        all_categories = [
            "Pottery",
            "Textiles",
            "Woodwork",
            "Jewelry",
            "Paintings",
            "Metal Craft",
            "Stone Carving",
            "Bamboo Craft",
            "Leather Craft",
            "Glass Craft",
        ]
        return VoiceGlossaryResponse(
            category=category,
            total_terms=len(terms),
            terms=terms,
            categories=all_categories,
        )
