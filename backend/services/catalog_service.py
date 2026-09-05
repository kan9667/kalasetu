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

# Import Image Pipeline Enhancer
try:
    from ML.image_pipeline.enhancer import enhance_image as run_ml_enhancer
except ImportError:
    try:
        from enhancer import enhance_image as run_ml_enhancer
    except ImportError:
        run_ml_enhancer = None

from ..config import get_settings
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

logger = logging.getLogger(__name__)


class CatalogService:
    """Provides speech-to-text, image enhancement, and bilingual catalog listing generation."""

    def __init__(self):
        self.settings = get_settings()
        self.client = genai.Client(api_key=self.settings.gemini_api_key) if self.settings.gemini_api_key else None
        self.voice_processor = ArtisanVoiceProcessor()

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
        if run_ml_enhancer is None:
            raise RuntimeError(
                "ML image enhancer is unavailable. Install the image_pipeline dependencies."
            )

        try:
            enhanced_path = await run_in_threadpool(
                run_ml_enhancer,
                input_path=input_path,
                output_path=output_path,
            )
            if not enhanced_path or not Path(enhanced_path).is_file():
                raise RuntimeError("Image enhancer did not create an output file")
            return enhanced_path
        except Exception as e:
            logger.error("Image enhancement execution failed: %s", e)
            raise e

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
        language_code: str = "hi",
        category_hint: Optional[str] = None,
        note_id: Optional[str] = None,
    ) -> AudioTranscribeResponse:
        """
        Transcribe an artisan's regional voice note using the ML voice pipeline
        (Whisper with craft glossary prompt biasing).
        """
        path = Path(audio_file_path)
        if not path.exists():
            raise FileNotFoundError(f"Audio file not found: {audio_file_path}")

        # Check for silent audio before running heavy Whisper processing
        if self._is_audio_silent(path):
            logger.warning("Audio file %s is silent (volume < -40dB). Aborting transcription.", path.name)
            raise ValueError("No audible speech detected. Please speak closer to the microphone.")

        result = await run_in_threadpool(
            self.voice_processor.process_voice_note,
            audio_path=str(path),
            language_code=language_code,
            category_hint=category_hint,
            note_id=note_id,
        )

        if result.status == JobStatus.FAILED or not result.transcript or not result.transcript.is_usable():
            error_msg = result.error or "Voice transcription failed or returned empty transcript."
            logger.error("Voice pipeline transcription failure: %s", error_msg)
            raise ValueError(error_msg)

        transcript_text = result.transcript.text.strip()
        if self._is_silence_hallucination(transcript_text):
            logger.warning("Whisper silence hallucination detected: '%s'. Aborting transcription.", transcript_text)
            raise ValueError("No audible speech detected. Please speak closer to the microphone.")

        return AudioTranscribeResponse(
            transcript=transcript_text,
            language_code=result.transcript.language_code,
            detected_language=result.transcript.language_code,
            duration_seconds=result.transcript.duration_seconds,
            provider=result.transcript.provider.value if hasattr(result.transcript.provider, "value") else str(result.transcript.provider),
            is_fallback=result.transcript.is_fallback,
            status=result.status.value,
        )

    # ── Bilingual Listing Generation ────────────────────────────────────────

    async def generate_listing(
        self,
        request: ListingGenerateRequest,
    ) -> ListingGenerateResponse:
        """
        Generate SEO-friendly, bilingual e-commerce product titles, descriptions,
        category, and search tags from an artisan's voice transcript.
        Enriches the prompt with domain craft glossary terms.
        """
        # Inject craft glossary hints for accurate terminology
        glossary_prompt = build_prompt_hint(
            category=request.category_hint,
            limit=30,
            language_code=request.language_code,
        )

        system_prompt = f"""You are an expert handicraft cataloger and market specialist for Indian artisans (KalaSetu).
Transform raw spoken voice descriptions into professional, engaging, bilingual e-commerce product listings.

Domain Handicraft Vocabulary Reference:
[{glossary_prompt}]

Rules:
1. Generate title_en (Engaging English e-commerce title) and title_hi (Hindi title in Devanagari script).
2. Generate description_en (capturing craft heritage, materials, technique, and artisan value) and description_hi.
3. Identify the accurate craft category (e.g., Pottery, Textiles, Woodwork, Jewelry, Paintings, Bamboo Craft, Brass, Leather, Stone Craft).
4. Generate 5-8 relevant SEO tags in English (lowercase, hyphenated).
5. Output ONLY valid JSON matching the schema."""

        user_prompt = f"""Raw Artisan Voice Transcript:
"{request.transcript}"

Category Hint (if provided): {request.category_hint or 'None'}

Please generate the structured bilingual catalog listing."""

        if not self.client:
            # Fallback if Gemini key is not configured
            return ListingGenerateResponse(
                title_en="Handcrafted Terracotta Ceramic Floral Vase with Folk Etchings",
                title_hi="लोक नक्काशीदार हस्तनिर्मित मिट्टी का सजावटी फूलदान",
                description_en=request.transcript or "Authentic handcrafted artisanal product made with traditional techniques.",
                description_hi="पारंपरिक तकनीक से बना हस्तनिर्मित उत्कृष्ट उत्पाद।",
                category=request.category_hint or "Pottery",
                tags=["handcrafted", "artisan", "traditional", "heritage", "sustainable"],
            )

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
            return ListingGenerateResponse(
                title_en=data.get("title_en", "Handcrafted Artisan Product"),
                title_hi=data.get("title_hi", "हस्तनिर्मित उत्पाद"),
                description_en=data.get("description_en", request.transcript),
                description_hi=data.get("description_hi", ""),
                category=data.get("category", request.category_hint or "General"),
                tags=data.get("tags", ["handmade", "handicraft", "artisan"]),
            )
        except Exception as e:
            logger.error("Listing generation failed: %s", e)
            return ListingGenerateResponse(
                title_en="Handcrafted Terracotta Ceramic Floral Vase with Folk Etchings",
                title_hi="लोक नक्काशीदार हस्तनिर्मित मिट्टी का सजावटी फूलदान",
                description_en=request.transcript or "Authentic handcrafted artisanal creation with traditional craft value.",
                description_hi="पारंपरिक कला व कारीगरी से बना प्रामाणिक हस्तशिल्प उत्पाद।",
                category=request.category_hint or "Pottery",
                tags=["terracotta", "pottery", "folk-art", "handcrafted", "eco-friendly"],
            )

    # ── Voice Cost Cue Extractor ────────────────────────────────────────────

    async def extract_cost_cues(self, transcript: str) -> CostInputsSchema:
        """
        Extract cost cues (raw materials cost, labor hours, wages) spoken by the artisan
        in their natural voice note description.
        """
        default_costs = CostInputsSchema(
            materials=0.0,
            labor_hours=0.0,
            hourly_rate=50.0,
            transport=0.0,
            overhead=0.0,
        )

        if not self.client or not transcript:
            return default_costs

        prompt = f"""Analyze the following artisan voice transcript and extract any mentioned cost, labor, or time details:
"{transcript}"

Extract:
- materials: Cost of raw materials in INR (number, default 0 if not mentioned)
- labor_hours: Hours spent crafting the product (number, default 0 if not mentioned, e.g. 2 days = 16 hours)
- hourly_rate: Hourly wage rate in INR (default 50.0 if not mentioned)
- transport: Transport/shipping cost in INR (default 0 if not mentioned)
- overhead: Additional overhead cost in INR (default 0 if not mentioned)

Return ONLY JSON matching the schema."""

        try:
            response = await run_in_threadpool(
                self.client.models.generate_content,
                model=self.settings.llm_model,
                contents=prompt,
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
            return CostInputsSchema(
                materials=float(data.get("materials", 0.0) or 0.0),
                labor_hours=float(data.get("labor_hours", 0.0) or 0.0),
                hourly_rate=float(data.get("hourly_rate", 50.0) or 50.0),
                transport=float(data.get("transport", 0.0) or 0.0),
                overhead=float(data.get("overhead", 0.0) or 0.0),
            )
        except Exception as e:
            logger.warning("Could not extract cost cues from transcript: %s", e)
            return default_costs

    # ── Voice-to-Product Pipeline Orchestrator ──────────────────────────────

    async def process_voice_to_product(
        self,
        audio_file_path: str,
        language_code: str = "hi",
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
        from .pricing_service import PricingService
        pricing_service = PricingService()

        # Step 1: Transcribe Audio using ML Voice Pipeline
        transcribe_res = await self.transcribe_audio(
            audio_file_path=audio_file_path,
            language_code=language_code,
            category_hint=category_hint,
        )
        transcript = transcribe_res.transcript

        # Step 2: Generate Bilingual Listing (Description, Tags, Title, Category)
        listing_req = ListingGenerateRequest(
            transcript=transcript,
            language_code=language_code,
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
            image_url=image_url or "/uploads/default.jpg",
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
