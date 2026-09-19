"""
Media Asset Ingestion & Access Router.

Enforces:
- Required Idempotency-Key for all uploads.
- Atomic idempotent replay returning original media_id without duplicate file creation.
- Magic-byte inspection, SHA-256 byte checksum, 15MB limit.
- Authenticated tenant-only access for private drafts: GET /api/v1/media/{id}.
- Gatekept public access authorized strictly against approved published revisions: GET /api/v1/media/{id}/public.
"""

import hashlib
import json
import uuid
from pathlib import Path
from fastapi import APIRouter, Depends, File, HTTPException, Request, Response, UploadFile, status
from fastapi.responses import FileResponse, JSONResponse
from sqlalchemy.orm import Session

from ..config import get_settings
from ..database import get_db
from ..models.db_models import ArtisanDB, MediaAssetDB, ProductDB, ProductRevisionDB, ProductStatus
from ..services.streaming_ingest import (
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

settings = get_settings()
router = APIRouter(prefix="/api/v1/media", tags=["Media"])


@router.post("/upload", status_code=status.HTTP_201_CREATED)
async def upload_media(
    request: Request,
    file: UploadFile = File(...),
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    Upload and validate product image.
    Enforces idempotency, magic-byte inspection, SHA-256 checksumming,
    and returns server-owned MediaAsset with status='ready'.
    """
    idempotency_key = require_idempotency_key(request)
    endpoint = "/api/v1/media/upload"

    # Single-pass streaming ingestion & validation
    staged = await stream_and_validate_upload(
        file=file,
        max_bytes=IMAGE_MAX_BYTES,
        allowed_categories={"image"},
    )
    request_hash = compute_request_fingerprint("POST", endpoint, staged.sha256_checksum)

    # Claim idempotency key
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

    upload_dir = Path(settings.upload_dir) / "private"
    upload_dir.mkdir(parents=True, exist_ok=True)
    dest_path = None
    asset = None
    try:
        existing_asset = get_existing_media_asset(
            db=db,
            artisan_id=artisan.id,
            sha256_checksum=staged.sha256_checksum,
            processing_provenance="artisan_direct_upload",
        )
        if existing_asset:
            staged.cleanup()
            asset = existing_asset
        else:
            ext = ".jpg" if staged.mime_type == "image/jpeg" else (".png" if staged.mime_type == "image/png" else ".webp")
            asset_id = f"med_{uuid.uuid4().hex[:12]}"
            dest_path = upload_dir / f"{asset_id}{ext}"
            staged.promote_to(dest_path)
            asset = register_media_asset(
                db=db,
                artisan_id=artisan.id,
                file_path=str(dest_path),
                mime_type=staged.mime_type,
                byte_size=staged.byte_size,
                sha256_checksum=staged.sha256_checksum,
                processing_provenance="artisan_direct_upload",
                status_str="ready",
            )

        res_dict = {
            "media_id": asset.id,
            "file_url": asset.file_url,
            "mime_type": asset.mime_type,
            "byte_size": asset.byte_size,
            "sha256_checksum": asset.sha256_checksum,
            "status": asset.status,
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
        if dest_path and dest_path.exists():
            dest_path.unlink(missing_ok=True)
        raise


@router.get("/{media_id}")
async def get_private_media(
    media_id: str,
    artisan: ArtisanDB = Depends(get_current_artisan),
    db: Session = Depends(get_db),
):
    """
    Authenticated tenant media retrieval.
    Enforces that only the artisan who owns the draft/media can retrieve it.
    """
    asset = db.query(MediaAssetDB).filter(MediaAssetDB.id == media_id).first()
    if not asset:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Media asset not found",
        )

    if asset.artisan_id != artisan.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access forbidden: This media belongs to another artisan.",
        )

    file_path = Path(asset.file_path)
    if not file_path.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Media file not found on disk",
        )

    return FileResponse(str(file_path), media_type=asset.mime_type)


@router.get("/{media_id}/public")
async def get_public_media(
    media_id: str,
    db: Session = Depends(get_db),
):
    """
    Public media retrieval endpoint for marketplace shoppers.
    Authorized STRICTLY against an approved, currently published revision snapshot in ProductRevisionDB.
    Unapproved drafts and other private media return HTTP 404.
    """
    published_rev = (
        db.query(ProductRevisionDB)
        .join(ProductDB, ProductDB.id == ProductRevisionDB.product_id)
        .filter(
            ProductRevisionDB.media_id == media_id,
            ProductDB.status == ProductStatus.PUBLISHED.value,
            ProductDB.is_deleted == False,
            ProductDB.approved_revision == ProductRevisionDB.revision,
        )
        .first()
    )

    if not published_rev:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Public media asset not found or listing not published.",
        )

    asset = db.query(MediaAssetDB).filter(MediaAssetDB.id == media_id).first()
    if not asset or not Path(asset.file_path).exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Media file not found on disk.",
        )

    return FileResponse(str(asset.file_path), media_type=asset.mime_type)
