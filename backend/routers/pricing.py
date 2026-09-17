"""
Pricing Router.

Exposes AI pricing recommendations powered by ChromaDB RAG and Gemini LLM.
Supports direct JSON payload, image upload, and audio voice note upload.

Enforces:
- Bearer authentication across all pricing endpoints.
- Single-pass streaming ingestion for file uploads.
- Retry-safe idempotency.
"""

from typing import List, Optional
from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, Response, UploadFile, status
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from ..database import get_db
from ..models.db_models import ArtisanDB
from ..models.schemas import (
    ListingGenerateRequest,
    PriceSuggestRequest,
    PriceSuggestResponse,
)
from ..services.catalog_service import CatalogService
from ..services.pricing_service import PricingService
from ..services.streaming_ingest import (
    AUDIO_MAX_BYTES,
    IMAGE_MAX_BYTES,
    stream_and_validate_upload,
)
from ..utils.auth import get_current_artisan
from ..utils.idempotency import (
    claim_idempotency,
    complete_idempotency,
    compute_request_fingerprint,
    release_idempotency_claim,
    require_idempotency_key,
)

router = APIRouter(prefix="/api/v1/pricing", tags=["Pricing"])
pricing_service = PricingService()
catalog_service = CatalogService()


@router.get("/status")
def get_pricing_status():
    """Return benchmark vector store index status (public)."""
    return pricing_service.get_index_status()


@router.post("/suggest", response_model=PriceSuggestResponse)
async def suggest_price_json(
    raw_req: Request,
    request: PriceSuggestRequest,
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    Get an AI pricing recommendation from structured JSON input.
    Protected by bearer authentication and retry-safe idempotency.
    """
    idempotency_key = require_idempotency_key(raw_req)
    endpoint = "/api/v1/pricing/suggest"

    fingerprint_dict = {
        "description": request.description,
        "category": request.category,
        "raw_material_cost": request.raw_material_cost,
        "labor_hours": request.labor_hours,
        "hourly_wage": request.hourly_wage,
        "transport": request.transport,
        "overhead": request.overhead,
        "tags": sorted(request.tags) if request.tags else [],
    }
    request_hash = compute_request_fingerprint("POST", endpoint, fingerprint_dict)

    is_completed, cached_status, cached_body = claim_idempotency(
        db=db,
        artisan_id=artisan.id,
        endpoint=endpoint,
        idempotency_key=idempotency_key,
        request_hash=request_hash,
    )
    if is_completed:
        return Response(
            content=cached_body,
            status_code=cached_status or status.HTTP_200_OK,
            media_type="application/json",
        )

    try:
        res = await run_in_threadpool(pricing_service.suggest_price, request, db=db)
        complete_idempotency(
            db=db,
            artisan_id=artisan.id,
            endpoint=endpoint,
            idempotency_key=idempotency_key,
            status_code=status.HTTP_200_OK,
            response_data=res.model_dump(mode="json"),
        )
        db.commit()
        return res
    except Exception as e:
        db.rollback()
        release_idempotency_claim(db, artisan.id, endpoint, idempotency_key)
        if isinstance(e, HTTPException):
            raise
        raise HTTPException(status_code=500, detail=f"Pricing calculation failed: {str(e)}")


@router.post("/suggest-upload", response_model=PriceSuggestResponse)
async def suggest_price_with_file_upload(
    raw_req: Request,
    description: str = Form(...),
    category: Optional[str] = Form(None),
    raw_material_cost: Optional[float] = Form(None),
    labor_hours: Optional[float] = Form(None),
    hourly_wage: Optional[float] = Form(None),
    transport: Optional[float] = Form(0.0),
    overhead: Optional[float] = Form(0.0),
    tags: Optional[str] = Form(None),
    image: Optional[UploadFile] = File(None),
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    Get an AI pricing recommendation with a direct image file upload.
    Protected by bearer authentication, streaming size limits, and idempotency.
    """
    idempotency_key = require_idempotency_key(raw_req)
    endpoint = "/api/v1/pricing/suggest-upload"

    staged_image = None
    if image:
        staged_image = await stream_and_validate_upload(
            file=image,
            max_bytes=IMAGE_MAX_BYTES,
            allowed_categories={"image"},
        )

    parsed_tags = sorted([t.strip() for t in tags.split(",") if t.strip()]) if tags else []
    fingerprint_dict = {
        "image_sha256": staged_image.sha256_checksum if staged_image else None,
        "description": description,
        "category": category,
        "raw_material_cost": raw_material_cost,
        "labor_hours": labor_hours,
        "hourly_wage": hourly_wage,
        "transport": transport,
        "overhead": overhead,
        "tags": parsed_tags,
    }
    request_hash = compute_request_fingerprint("POST", endpoint, fingerprint_dict)

    is_completed, cached_status, cached_body = claim_idempotency(
        db=db,
        artisan_id=artisan.id,
        endpoint=endpoint,
        idempotency_key=idempotency_key,
        request_hash=request_hash,
    )

    if is_completed:
        if staged_image:
            staged_image.cleanup()
        return Response(
            content=cached_body,
            status_code=cached_status or status.HTTP_200_OK,
            media_type="application/json",
        )

    tags_list = [t.strip() for t in tags.split(",") if t.strip()] if tags else []

    try:
        request_obj = PriceSuggestRequest(
            description=description,
            category=category,
            image_url=None,
            raw_material_cost=raw_material_cost,
            labor_hours=labor_hours,
            hourly_wage=hourly_wage,
            transport=transport,
            overhead=overhead,
            tags=tags_list,
        )

        res = await run_in_threadpool(pricing_service.suggest_price, request_obj, db=db)

        complete_idempotency(
            db=db,
            artisan_id=artisan.id,
            endpoint=endpoint,
            idempotency_key=idempotency_key,
            status_code=status.HTTP_200_OK,
            response_data=res.model_dump(mode="json"),
        )
        db.commit()

        return res
    except Exception:
        db.rollback()
        release_idempotency_claim(db, artisan.id, endpoint, idempotency_key)
        raise
    finally:
        if staged_image:
            staged_image.cleanup()


@router.post("/suggest-from-voice", response_model=PriceSuggestResponse)
async def suggest_price_from_voice(
    raw_req: Request,
    audio: UploadFile = File(..., description="Artisan voice note audio recording"),
    image: Optional[UploadFile] = File(None, description="Optional product photo"),
    language_code: str = Form("hi", description="Spoken language code"),
    category_hint: Optional[str] = Form(None, description="Craft category hint"),
    raw_material_cost: Optional[float] = Form(None, description="Optional raw material cost override"),
    labor_hours: Optional[float] = Form(None, description="Optional labor hours override"),
    hourly_wage: Optional[float] = Form(None, description="Optional hourly rate override"),
    transport: Optional[float] = Form(0.0),
    overhead: Optional[float] = Form(0.0),
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    Get an AI pricing recommendation directly from an artisan's spoken voice description.
    Protected by bearer authentication, streaming size limits, and idempotency.
    """
    idempotency_key = require_idempotency_key(raw_req)
    endpoint = "/api/v1/pricing/suggest-from-voice"

    staged_audio = await stream_and_validate_upload(
        file=audio,
        max_bytes=AUDIO_MAX_BYTES,
        allowed_categories={"audio"},
    )

    staged_image = None
    if image:
        staged_image = await stream_and_validate_upload(
            file=image,
            max_bytes=IMAGE_MAX_BYTES,
            allowed_categories={"image"},
        )

    fingerprint_dict = {
        "audio_sha256": staged_audio.sha256_checksum,
        "image_sha256": staged_image.sha256_checksum if staged_image else None,
        "language_code": language_code,
        "category_hint": category_hint,
        "raw_material_cost": raw_material_cost,
        "labor_hours": labor_hours,
        "hourly_wage": hourly_wage,
        "transport": transport,
        "overhead": overhead,
    }
    request_hash = compute_request_fingerprint("POST", endpoint, fingerprint_dict)

    is_completed, cached_status, cached_body = claim_idempotency(
        db=db,
        artisan_id=artisan.id,
        endpoint=endpoint,
        idempotency_key=idempotency_key,
        request_hash=request_hash,
    )

    if is_completed:
        staged_audio.cleanup()
        if staged_image:
            staged_image.cleanup()
        return Response(
            content=cached_body,
            status_code=cached_status or status.HTTP_200_OK,
            media_type="application/json",
        )

    try:
        transcribe_res = await catalog_service.transcribe_audio(
            audio_file_path=str(staged_audio.staged_path),
            language_code=language_code,
            category_hint=category_hint,
        )

        listing_res = await catalog_service.generate_listing(
            ListingGenerateRequest(
                transcript=transcribe_res.transcript,
                language_code=language_code,
                category_hint=category_hint,
                image_url=None,
            )
        )

        extracted_costs = await catalog_service.extract_cost_cues(transcribe_res.transcript)
        final_materials = raw_material_cost if raw_material_cost is not None else extracted_costs.materials
        final_hours = labor_hours if labor_hours is not None else extracted_costs.labor_hours
        final_rate = hourly_wage if hourly_wage is not None else extracted_costs.hourly_rate

        request_obj = PriceSuggestRequest(
            description=f"{listing_res.title_en} - {listing_res.description_en}",
            category=listing_res.category,
            image_url=None,
            raw_material_cost=final_materials,
            labor_hours=final_hours,
            hourly_wage=final_rate,
            transport=transport or 0.0,
            overhead=overhead or 0.0,
            tags=listing_res.tags,
        )

        res = await run_in_threadpool(pricing_service.suggest_price, request_obj, db=db)

        complete_idempotency(
            db=db,
            artisan_id=artisan.id,
            endpoint=endpoint,
            idempotency_key=idempotency_key,
            status_code=status.HTTP_200_OK,
            response_data=res.model_dump(mode="json"),
        )
        db.commit()

        return res
    except Exception:
        db.rollback()
        release_idempotency_claim(db, artisan.id, endpoint, idempotency_key)
        raise
    finally:
        staged_audio.cleanup()
        if staged_image:
            staged_image.cleanup()
