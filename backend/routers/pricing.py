"""
Pricing Router.

Exposes AI pricing recommendations powered by ChromaDB RAG and Gemini LLM.
Supports direct JSON payload, image upload, and audio voice note upload.
"""

from typing import Optional, List
from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.schemas import (
    PriceSuggestRequest,
    PriceSuggestResponse,
    ListingGenerateRequest,
    CostInputsSchema,
)
from ..services.pricing_service import PricingService
from ..services.catalog_service import CatalogService
from ..services.storage_service import StorageService

router = APIRouter(prefix="/api/v1/pricing", tags=["Pricing"])
pricing_service = PricingService()
catalog_service = CatalogService()
storage_service = StorageService()


@router.post("/suggest", response_model=PriceSuggestResponse)
async def suggest_price_json(
    request: PriceSuggestRequest,
    db: Session = Depends(get_db),
):
    """
    Get an AI pricing recommendation from structured JSON input.
    Compatible with Flutter's PricingService.
    """
    try:
        return pricing_service.suggest_price(request, db=db)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Pricing calculation failed: {str(e)}")


@router.post("/suggest-upload", response_model=PriceSuggestResponse)
async def suggest_price_with_file_upload(
    description: str = Form(...),
    category: Optional[str] = Form(None),
    raw_material_cost: Optional[float] = Form(None),
    labor_hours: Optional[float] = Form(None),
    hourly_wage: Optional[float] = Form(None),
    transport: Optional[float] = Form(0.0),
    overhead: Optional[float] = Form(0.0),
    tags: Optional[str] = Form(None),  # Comma separated
    image: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
):
    """
    Get an AI pricing recommendation with a direct image file upload.
    """
    image_url = None
    if image:
        image_url = await storage_service.save_upload(image, subfolder="products")

    tags_list = [t.strip() for t in tags.split(",") if t.strip()] if tags else []

    request = PriceSuggestRequest(
        description=description,
        category=category,
        image_url=image_url,
        raw_material_cost=raw_material_cost,
        labor_hours=labor_hours,
        hourly_wage=hourly_wage,
        transport=transport,
        overhead=overhead,
        tags=tags_list,
    )

    try:
        return pricing_service.suggest_price(request, db=db)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Pricing calculation failed: {str(e)}")


@router.post("/suggest-from-voice", response_model=PriceSuggestResponse)
async def suggest_price_from_voice(
    audio: UploadFile = File(..., description="Artisan voice note audio recording"),
    image: Optional[UploadFile] = File(None, description="Optional product photo"),
    language_code: str = Form("hi", description="Spoken language code"),
    category_hint: Optional[str] = Form(None, description="Craft category hint"),
    raw_material_cost: Optional[float] = Form(None, description="Optional raw material cost override"),
    labor_hours: Optional[float] = Form(None, description="Optional labor hours override"),
    hourly_wage: Optional[float] = Form(None, description="Optional hourly rate override"),
    transport: Optional[float] = Form(0.0),
    overhead: Optional[float] = Form(0.0),
    db: Session = Depends(get_db),
):
    """
    Get an AI pricing recommendation directly from an artisan's spoken voice description:
    1. Transcribes voice note with craft glossary biasing.
    2. Generates description & tags.
    3. Extracts cost cues from speech (or uses provided overrides).
    4. Calculates cost floor, market-based suggested price, and Hindi readback reasoning.
    """
    try:
        # 1. Save audio
        audio_url = await storage_service.save_upload(audio, subfolder="audio")
        audio_path = storage_service.get_local_path_from_url(audio_url)
        if not audio_path:
            raise HTTPException(status_code=500, detail="Failed to store audio file")

        # 2. Save image if provided
        image_url = None
        if image:
            image_url = await storage_service.save_upload(image, subfolder="products")

        # 3. Transcribe audio
        transcribe_res = await catalog_service.transcribe_audio(
            audio_file_path=str(audio_path),
            language_code=language_code,
            category_hint=category_hint,
        )

        # 4. Generate listing for English description & category
        listing_res = await catalog_service.generate_listing(
            ListingGenerateRequest(
                transcript=transcribe_res.transcript,
                language_code=language_code,
                category_hint=category_hint,
                image_url=image_url,
            )
        )

        # 5. Extract cost cues from speech if not explicitly given
        extracted_costs = await catalog_service.extract_cost_cues(transcribe_res.transcript)
        final_materials = raw_material_cost if raw_material_cost is not None else extracted_costs.materials
        final_hours = labor_hours if labor_hours is not None else extracted_costs.labor_hours
        final_rate = hourly_wage if hourly_wage is not None else extracted_costs.hourly_rate

        request = PriceSuggestRequest(
            description=listing_res.description_en,
            category=listing_res.category,
            image_url=image_url,
            materials=final_materials,
            labor_hours=final_hours,
            hourly_rate=final_rate,
            transport=transport or 0.0,
            overhead=overhead or 0.0,
            tags=listing_res.tags,
        )

        return pricing_service.suggest_price(request, db=db)
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Voice pricing calculation failed: {str(e)}")


@router.get("/status")
async def get_pricing_status():
    """
    Get the current vector index status and total benchmark products count.
    """
    return pricing_service.get_index_status()
