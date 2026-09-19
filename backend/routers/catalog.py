"""
Catalog & AI Multimodal Router.

Handles photo enhancement, speech-to-text audio transcription via ML voice pipeline,
bilingual listing generation, and complete voice-to-product draft creation.

Enforces:
- Bearer authentication via get_current_artisan across all compute and upload endpoints.
- Single-pass streaming ingestion with magic-byte validation and size limits.
- Mandatory Idempotency-Key header on retryable compute operations.
- Full idempotency replay without re-running ML pipelines or creating duplicate media assets.
- Explicit lineage (source_media_id) and degradation tracking (is_degraded).
"""

import asyncio
import hashlib
import uuid
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, Response, UploadFile, status
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from ..config import get_settings
from ..database import get_db
from ..models.db_models import ArtisanDB, MediaAssetDB
from ..models.schemas import (
    AudioTranscribeResponse,
    CostInputsSchema,
    ImageEnhanceResponse,
    ListingGenerateRequest,
    ListingGenerateResponse,
    VoiceToProductResponse,
)
from ..services.catalog_service import CatalogService
from ..services.streaming_ingest import (
    AUDIO_MAX_BYTES,
    IMAGE_MAX_BYTES,
    get_existing_media_asset,
    register_media_asset,
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

router = APIRouter(prefix="/api/v1/catalog", tags=["Cataloger AI"])
catalog_service = CatalogService()
settings = get_settings()
_image_semaphore = asyncio.Semaphore(1)


@router.post("/enhance-image", response_model=ImageEnhanceResponse)
async def enhance_image(
    request: Request,
    image: UploadFile = File(...),
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    Upload and optimize product photos for studio quality e-commerce listings.
    Single-pass streaming ingestion, magic-byte inspection, and retry-safe idempotency.
    Persists original and enhanced assets in MediaAssetDB with lineage and degradation metadata.
    """
    idempotency_key = require_idempotency_key(request)
    endpoint = "/api/v1/catalog/enhance-image"

    staged_raw = await stream_and_validate_upload(
        file=image,
        max_bytes=IMAGE_MAX_BYTES,
        allowed_categories={"image"},
    )

    request_hash = compute_request_fingerprint("POST", endpoint, {"image_sha256": staged_raw.sha256_checksum})

    is_completed, cached_status, cached_body = claim_idempotency(
        db=db,
        artisan_id=artisan.id,
        endpoint=endpoint,
        idempotency_key=idempotency_key,
        request_hash=request_hash,
    )

    if is_completed:
        staged_raw.cleanup()
        return Response(
            content=cached_body,
            status_code=cached_status or status.HTTP_200_OK,
            media_type="application/json",
        )

    raw_asset = None
    enhanced_asset = None
    raw_dest = None
    enhanced_path = None
    raw_promoted_new = False
    enhanced_created_new = False
    try:
        # 1. Lineage-aware raw deduplication check before promotion
        existing_raw = get_existing_media_asset(
            db=db,
            artisan_id=artisan.id,
            sha256_checksum=staged_raw.sha256_checksum,
            processing_provenance="artisan_raw_image",
            source_media_id=None,
            is_degraded=False,
        )
        if existing_raw:
            raw_asset = existing_raw
            raw_dest = Path(existing_raw.file_path)
            staged_raw.cleanup()
        else:
            raw_dest = Path(settings.upload_dir) / "private" / f"med_{uuid.uuid4().hex[:12]}_{staged_raw.sha256_checksum[:8]}.jpg"
            staged_raw.promote_to(raw_dest)
            raw_promoted_new = True
            raw_asset = register_media_asset(
                db=db,
                artisan_id=artisan.id,
                file_path=str(raw_dest),
                mime_type=staged_raw.mime_type,
                byte_size=staged_raw.byte_size,
                sha256_checksum=staged_raw.sha256_checksum,
                processing_provenance="artisan_raw_image",
                source_media_id=None,
                is_degraded=False,
                status_str="ready",
            )

        # 2. Prepare destination path for enhanced image
        enhanced_id = f"med_{uuid.uuid4().hex[:12]}"
        enhanced_path = Path(settings.upload_dir) / "private" / f"{enhanced_id}.jpg"
        enhanced_path.parent.mkdir(parents=True, exist_ok=True)

        # 3. Execute non-blocking AI image enhancement (serialized with semaphore)
        async with _image_semaphore:
            result_path_str, is_degraded, degraded_reason = await catalog_service.enhance_product_photo(
                input_path=str(raw_dest),
                output_path=str(enhanced_path),
            )

        result_path = Path(result_path_str)
        if not result_path.exists() or result_path == raw_dest:
            # Fallback: raw image used
            is_degraded = True
            degraded_reason = degraded_reason or "AI enhancement failed; falling back to original photo."
            enhanced_asset = register_media_asset(
                db=db,
                artisan_id=artisan.id,
                file_path=str(raw_dest),
                mime_type=raw_asset.mime_type,
                byte_size=raw_asset.byte_size,
                sha256_checksum=raw_asset.sha256_checksum,
                processing_provenance="raw_fallback",
                source_media_id=raw_asset.id,
                is_degraded=True,
                degraded_reason=degraded_reason,
                status_str="ready",
            )
        else:
            with open(result_path, "rb") as ef:
                enhanced_bytes = ef.read()
            enhanced_checksum = hashlib.sha256(enhanced_bytes).hexdigest()
            enhanced_size = len(enhanced_bytes)
            provenance = "ai_enhanced_image" if not is_degraded else "degraded_enhanced_image"

            # Check lineage-aware derived asset deduplication
            existing_derived = get_existing_media_asset(
                db=db,
                artisan_id=artisan.id,
                sha256_checksum=enhanced_checksum,
                processing_provenance=provenance,
                source_media_id=raw_asset.id,
                is_degraded=is_degraded,
            )
            if existing_derived:
                if result_path.exists() and result_path != raw_dest:
                    result_path.unlink(missing_ok=True)
                enhanced_asset = existing_derived
            else:
                enhanced_created_new = True
                enhanced_asset = register_media_asset(
                    db=db,
                    artisan_id=artisan.id,
                    file_path=str(result_path),
                    mime_type="image/jpeg",
                    byte_size=enhanced_size,
                    sha256_checksum=enhanced_checksum,
                    processing_provenance=provenance,
                    source_media_id=raw_asset.id,
                    is_degraded=is_degraded,
                    degraded_reason=degraded_reason,
                    status_str="ready",
                )

        response_data = {
            "original_url": raw_asset.file_url,
            "enhanced_url": enhanced_asset.file_url,
            "status": "success" if not is_degraded else "degraded",
            "media_id": enhanced_asset.id,
            "original_media_id": raw_asset.id,
            "sha256_checksum": enhanced_asset.sha256_checksum,
            "byte_size": enhanced_asset.byte_size,
            "is_degraded": is_degraded,
            "degraded_reason": degraded_reason,
        }

        complete_idempotency(
            db=db,
            artisan_id=artisan.id,
            endpoint=endpoint,
            idempotency_key=idempotency_key,
            status_code=status.HTTP_200_OK,
            response_data=response_data,
        )
        db.commit()

        return ImageEnhanceResponse(**response_data)
    except Exception:
        db.rollback()
        release_idempotency_claim(db, artisan.id, endpoint, idempotency_key)
        staged_raw.cleanup()
        if raw_promoted_new and raw_dest and raw_dest.exists():
            raw_dest.unlink(missing_ok=True)
        if enhanced_created_new and enhanced_path and enhanced_path.exists():
            enhanced_path.unlink(missing_ok=True)
        raise


@router.post("/upload-image", response_model=dict, status_code=status.HTTP_201_CREATED)
async def upload_image(
    request: Request,
    image: UploadFile = File(...),
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """Store a private artisan image and return server-owned MediaAsset identity."""
    idempotency_key = require_idempotency_key(request)
    endpoint = "/api/v1/catalog/upload-image"

    staged = await stream_and_validate_upload(
        file=image,
        max_bytes=IMAGE_MAX_BYTES,
        allowed_categories={"image"},
    )

    request_hash = compute_request_fingerprint("POST", endpoint, staged.sha256_checksum)

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
            status_code=cached_status or status.HTTP_201_CREATED,
            media_type="application/json",
        )

    try:
        dest_path = Path(settings.upload_dir) / "private" / f"med_{uuid.uuid4().hex[:12]}.jpg"
        staged.promote_to(dest_path)

        asset = register_media_asset(
            db=db,
            artisan_id=artisan.id,
            file_path=str(dest_path),
            mime_type=staged.mime_type,
            byte_size=staged.byte_size,
            sha256_checksum=staged.sha256_checksum,
            processing_provenance="artisan_direct_upload",
            source_media_id=None,
            is_degraded=False,
            status_str="ready",
        )

        res_dict = {
            "media_id": asset.id,
            "image_url": asset.file_url,
            "file_url": asset.file_url,
            "byte_size": asset.byte_size,
            "sha256_checksum": asset.sha256_checksum,
        }

        complete_idempotency(
            db=db,
            artisan_id=artisan.id,
            endpoint=endpoint,
            idempotency_key=idempotency_key,
            status_code=status.HTTP_201_CREATED,
            response_data=res_dict,
        )
        db.commit()

        return JSONResponse(status_code=status.HTTP_201_CREATED, content=res_dict)
    except Exception:
        db.rollback()
        release_idempotency_claim(db, artisan.id, endpoint, idempotency_key)
        staged.cleanup()
        raise


@router.post("/transcribe", response_model=AudioTranscribeResponse)
async def transcribe_voice_note(
    request: Request,
    audio: UploadFile = File(...),
    language_code: str = Form("hi"),
    category_hint: Optional[str] = Form(None),
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    Transcribe an artisan's regional voice note using the ML voice pipeline (Whisper STT).
    Single-pass streaming with audio magic-byte validation and retry-safe idempotency.
    """
    idempotency_key = require_idempotency_key(request)
    endpoint = "/api/v1/catalog/transcribe"

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


@router.post("/generate-listing", response_model=ListingGenerateResponse)
async def generate_bilingual_listing(
    raw_req: Request,
    request: ListingGenerateRequest,
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    Generate professional bilingual (English + Hindi) titles, descriptions,
    category classification, and SEO tags from a transcript.
    Protected by artisan authentication and retry-safe idempotency.
    """
    idempotency_key = require_idempotency_key(raw_req)
    endpoint = "/api/v1/catalog/generate-listing"

    fingerprint_dict = {
        "transcript": request.transcript,
        "language_code": request.language_code,
        "category_hint": request.category_hint,
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
        res = await catalog_service.generate_listing(request)
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
        raise HTTPException(status_code=500, detail="Listing generation failed")


@router.post("/voice-to-listing", response_model=ListingGenerateResponse)
async def voice_to_listing(
    request: Request,
    audio: UploadFile = File(...),
    language_code: str = Form("hi"),
    category_hint: Optional[str] = Form(None),
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    Direct voice-to-listing pipeline:
    Transcribes artisan voice note and directly generates bilingual title, description, category, and tags.
    """
    idempotency_key = require_idempotency_key(request)
    endpoint = "/api/v1/catalog/voice-to-listing"

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
        transcribe_res = await catalog_service.transcribe_audio(
            audio_file_path=str(staged.staged_path),
            language_code=language_code,
            category_hint=category_hint,
        )

        res = await catalog_service.generate_listing(
            ListingGenerateRequest(
                transcript=transcribe_res.transcript,
                language_code=language_code,
                category_hint=category_hint,
            )
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


@router.post("/voice-to-product", response_model=VoiceToProductResponse)
async def voice_to_product(
    request: Request,
    audio: UploadFile = File(...),
    image: Optional[UploadFile] = File(None),
    language_code: str = Form("hi"),
    category_hint: Optional[str] = Form(None),
    raw_material_cost: Optional[float] = Form(None),
    labor_hours: Optional[float] = Form(None),
    hourly_wage: Optional[float] = Form(None),
    transport: Optional[float] = Form(0.0),
    overhead: Optional[float] = Form(0.0),
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    One-click voice-to-product endpoint:
    Processes artisan voice audio, generates description & tags, calculates base prices and
    pricing suggestions, and returns a pre-populated product draft.
    """
    idempotency_key = require_idempotency_key(request)
    endpoint = "/api/v1/catalog/voice-to-product"

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
