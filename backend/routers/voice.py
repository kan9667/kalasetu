"""
Voice Router.

Exposes endpoints for:
1. Artisan Voice Speech-to-Text Transcription (Whisper STT + Craft Glossary).
2. Complete Voice-to-Product Pipeline (Voice -> Description & Tags -> Base Price -> Product Draft).
3. Craft Glossary Term Lookups by Category (Public Read-Only).

Enforces:
- Bearer authentication and idempotency on compute endpoints.
- Single-pass streaming ingestion with magic-byte validation and 25 MB audio limit.
- Automatic cleanup of staged files.
"""

from typing import Optional
from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, Response, UploadFile, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.db_models import ArtisanDB
from ..models.schemas import (
    AudioTranscribeResponse,
    VoiceToProductResponse,
    VoiceGlossaryResponse,
    CostInputsSchema,
)
from ..services.catalog_service import CatalogService
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

router = APIRouter(prefix="/api/v1/voice", tags=["Voice Pipeline"])
catalog_service = CatalogService()


@router.post("/transcribe", response_model=AudioTranscribeResponse)
async def transcribe_artisan_voice(
    request: Request,
    audio: UploadFile = File(..., description="Artisan voice recording (.m4a, .wav, .mp3)"),
    language_code: str = Form("auto", description="Spoken language code (default: auto, or hi, en, ta, bn, etc.)"),
    category_hint: Optional[str] = Form(None, description="Craft category hint to prioritize glossary terms"),
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    Transcribe an artisan's voice note to text using the ML voice pipeline
    with craft vocabulary biasing (Whisper STT).
    Protected by bearer authentication and retry-safe idempotency.
    """
    idempotency_key = require_idempotency_key(request)
    endpoint = "/api/v1/voice/transcribe"

    staged = await stream_and_validate_upload(
        file=audio,
        max_bytes=AUDIO_MAX_BYTES,
        allowed_categories={"audio"},
    )

    fingerprint_dict = {
        "audio_sha256": staged.sha256_checksum,
        "language_code": language_code,
        "category_hint": category_hint,
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
        staged.cleanup()
        return Response(
            content=cached_body,
            status_code=cached_status or status.HTTP_200_OK,
            media_type="application/json",
        )

    try:
        res = await catalog_service.transcribe_audio(
            audio_file_path=str(staged.staged_path),
            language_code=language_code,
            category_hint=category_hint,
        )

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
        staged.cleanup()


@router.post("/process", response_model=VoiceToProductResponse)
async def process_voice_to_product(
    request: Request,
    audio: UploadFile = File(..., description="Artisan voice recording (.m4a, .wav, .mp3)"),
    image: Optional[UploadFile] = File(None, description="Optional product photograph"),
    language_code: str = Form("auto", description="Spoken language code (default: auto)"),
    category_hint: Optional[str] = Form(None, description="Craft category hint"),
    raw_material_cost: Optional[float] = Form(None, description="Optional raw material cost in INR"),
    labor_hours: Optional[float] = Form(None, description="Optional hours of labor spent"),
    hourly_wage: Optional[float] = Form(None, description="Optional artisan hourly rate in INR"),
    transport: Optional[float] = Form(0.0, description="Optional transport cost in INR"),
    overhead: Optional[float] = Form(0.0, description="Optional overhead cost in INR"),
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    Complete end-to-end voice pipeline:
    1. Stream & validate artisan voice note (and optional photo).
    2. Transcribe voice in source regional language with craft glossary biasing.
    3. Generate bilingual product titles, storytelling descriptions, and SEO tags.
    4. Extract cost cues or apply provided cost inputs.
    5. Compute base price, price floor, range, comparables, and Hindi audio reasoning.
    6. Construct a ready-to-save product draft.
    """
    idempotency_key = require_idempotency_key(request)
    endpoint = "/api/v1/voice/process"

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
        cost_override = None
        if raw_material_cost is not None or labor_hours is not None or hourly_wage is not None:
            cost_override = CostInputsSchema(
                materials=raw_material_cost or 0.0,
                labor_hours=labor_hours or 0.0,
                hourly_rate=hourly_wage or 50.0,
                transport=transport or 0.0,
                overhead=overhead or 0.0,
            )

        res = await catalog_service.process_voice_to_product(
            audio_file_path=str(staged_audio.staged_path),
            language_code=language_code,
            category_hint=category_hint,
            cost_inputs_override=cost_override,
            db=db,
        )

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


@router.get("/glossary", response_model=VoiceGlossaryResponse)
async def get_glossary(
    category: Optional[str] = Query(None, description="Filter craft terms by category (e.g. Pottery, Textiles)"),
    limit: int = Query(50, ge=1, le=200, description="Max terms to return"),
):
    """
    Get Indian craft glossary terms prioritized by craft category.
    Deliberately public read-only metadata endpoint.
    """
    try:
        return catalog_service.get_craft_glossary(category=category, limit=limit)
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to fetch glossary")
