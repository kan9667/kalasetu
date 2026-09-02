"""
Voice Router.

Exposes endpoints for:
1. Artisan Voice Speech-to-Text Transcription (Whisper STT + Craft Glossary).
2. Complete Voice-to-Product Pipeline (Voice -> Description & Tags -> Base Price -> Product Draft).
3. Craft Glossary Term Lookups by Category.
"""

from typing import Optional
from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException, Query
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.schemas import (
    AudioTranscribeResponse,
    VoiceToProductResponse,
    VoiceGlossaryResponse,
    CostInputsSchema,
)
from ..services.catalog_service import CatalogService
from ..services.storage_service import StorageService

router = APIRouter(prefix="/api/v1/voice", tags=["Voice Pipeline"])
catalog_service = CatalogService()
storage_service = StorageService()


@router.post("/transcribe", response_model=AudioTranscribeResponse)
async def transcribe_artisan_voice(
    audio: UploadFile = File(..., description="Artisan voice recording (.m4a, .wav, .mp3)"),
    language_code: str = Form("hi", description="Spoken language code (e.g. hi, ta, bn, mr, etc.)"),
    category_hint: Optional[str] = Form(None, description="Craft category hint to prioritize glossary terms"),
):
    """
    Transcribe an artisan's voice note to text using the ML voice pipeline
    with craft vocabulary biasing (Whisper STT).
    """
    try:
        audio_url = await storage_service.save_upload(audio, subfolder="audio")
        local_path = storage_service.get_local_path_from_url(audio_url)
        if not local_path:
            raise HTTPException(status_code=500, detail="Failed to locate saved audio file on server")

        return await catalog_service.transcribe_audio(
            audio_file_path=str(local_path),
            language_code=language_code,
            category_hint=category_hint,
        )
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Voice transcription failed: {str(e)}")


@router.post("/process", response_model=VoiceToProductResponse)
async def process_voice_to_product(
    audio: UploadFile = File(..., description="Artisan voice recording (.m4a, .wav, .mp3)"),
    image: Optional[UploadFile] = File(None, description="Optional product photograph"),
    language_code: str = Form("hi", description="Spoken language code"),
    category_hint: Optional[str] = Form(None, description="Craft category hint"),
    raw_material_cost: Optional[float] = Form(None, description="Optional raw material cost in INR"),
    labor_hours: Optional[float] = Form(None, description="Optional hours of labor spent"),
    hourly_wage: Optional[float] = Form(None, description="Optional artisan hourly rate in INR"),
    transport: Optional[float] = Form(0.0, description="Optional transport cost in INR"),
    overhead: Optional[float] = Form(0.0, description="Optional overhead cost in INR"),
    db: Session = Depends(get_db),
):
    """
    Complete end-to-end voice pipeline:
    1. Upload & validate artisan voice note.
    2. Transcribe voice in source regional language with craft glossary biasing.
    3. Generate bilingual product titles, storytelling descriptions, and SEO tags.
    4. Extract cost cues or apply provided cost inputs.
    5. Compute base price, price floor, range, comparables, and Hindi audio reasoning.
    6. Construct a ready-to-save product draft.
    """
    try:
        # 1. Save uploaded audio
        audio_url = await storage_service.save_upload(audio, subfolder="audio")
        audio_path = storage_service.get_local_path_from_url(audio_url)
        if not audio_path:
            raise HTTPException(status_code=500, detail="Failed to store audio file")

        # 2. Save optional uploaded image
        image_url = None
        if image:
            image_url = await storage_service.save_upload(image, subfolder="products")

        # 3. Formulate cost inputs override if provided
        cost_override = None
        if raw_material_cost is not None or labor_hours is not None or hourly_wage is not None:
            cost_override = CostInputsSchema(
                materials=raw_material_cost or 0.0,
                labor_hours=labor_hours or 0.0,
                hourly_rate=hourly_wage or 50.0,
                transport=transport or 0.0,
                overhead=overhead or 0.0,
            )

        # 4. Orchestrate pipeline
        return await catalog_service.process_voice_to_product(
            audio_file_path=str(audio_path),
            language_code=language_code,
            category_hint=category_hint,
            image_url=image_url,
            audio_url=audio_url,
            cost_inputs_override=cost_override,
            db=db,
        )
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Voice processing failed: {str(e)}")


@router.get("/glossary", response_model=VoiceGlossaryResponse)
async def get_glossary(
    category: Optional[str] = Query(None, description="Filter craft terms by category (e.g. Pottery, Textiles)"),
    limit: int = Query(50, ge=1, le=200, description="Max terms to return"),
):
    """
    Get Indian craft glossary terms prioritized by craft category.
    """
    try:
        return catalog_service.get_craft_glossary(category=category, limit=limit)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch glossary: {str(e)}")
