"""
Pricing Router.

Exposes AI pricing recommendations powered by ChromaDB RAG and Gemini LLM.
"""

from typing import Optional, List
from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.schemas import (
    PriceSuggestRequest,
    PriceSuggestResponse,
)
from ..services.pricing_service import PricingService
from ..services.storage_service import StorageService

router = APIRouter(prefix="/api/v1/pricing", tags=["Pricing"])
pricing_service = PricingService()
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


@router.get("/status")
async def get_pricing_status():
    """
    Get the current vector index status and total benchmark products count.
    """
    return pricing_service.get_index_status()
