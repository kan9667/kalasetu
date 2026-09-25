"""
Media Validation and Ingestion Service.

Enforces:
- Magic-byte inspection (JPEG, PNG, WebP) to prevent MIME spoofing.
- 15 MB file size limit.
- Deterministic SHA-256 byte checksum calculation.
- Rejection of phone-local file paths and unvalidated uploads.
- Persistence to private storage and registration in media_assets with status='ready'.
"""

import hashlib
import uuid
from pathlib import Path
from typing import Tuple

import aiofiles
from fastapi import HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from ..config import get_settings
from ..models.db_models import MediaAssetDB

settings = get_settings()

ALLOWED_MIME_TYPES = {
    "image/jpeg": [b"\xff\xd8\xff"],
    "image/png": [b"\x89PNG\r\n\x1a\n"],
    "image/webp": [b"RIFF"],  # also checks bytes 8:12 == b"WEBP"
}

MAX_FILE_BYTES = 15 * 1024 * 1024  # 15 MB


from .streaming_ingest import (
    IMAGE_MAX_BYTES,
    AUDIO_MAX_BYTES,
    inspect_media_magic_bytes,
    stream_and_validate_upload,
    get_existing_media_asset,
    register_media_asset,
)


def inspect_magic_bytes(content: bytes) -> str:
    """
    Inspect initial magic bytes to determine true image MIME type.
    Raises 422 if unrecognized or unsupported.
    """
    mime_type, _ = inspect_media_magic_bytes(content[:32], {"image"})
    return mime_type


async def validate_and_store_media(
    db: Session,
    file: UploadFile,
    artisan_id: str,
    provenance: str = "raw_upload",
    source_media_id: Optional[str] = None,
    is_degraded: bool = False,
    degraded_reason: Optional[str] = None,
) -> MediaAssetDB:
    """
    Validate, hash, securely persist, and record a server-owned media asset
    via single-pass streaming ingestion.
    """
    staged = await stream_and_validate_upload(
        file=file,
        max_bytes=IMAGE_MAX_BYTES,
        allowed_categories={"image"},
    )

    upload_dir = Path(settings.upload_dir) / "private"
    upload_dir.mkdir(parents=True, exist_ok=True)

    dest_path = None
    try:
        # Check lineage-aware deduplication
        existing_asset = get_existing_media_asset(
            db=db,
            artisan_id=artisan_id,
            sha256_checksum=staged.sha256_checksum,
            processing_provenance=provenance,
            source_media_id=source_media_id,
            is_degraded=is_degraded,
        )
        if existing_asset:
            staged.cleanup()
            return existing_asset

        ext = ".jpg" if staged.mime_type == "image/jpeg" else (".png" if staged.mime_type == "image/png" else ".webp")
        asset_id = f"med_{uuid.uuid4().hex[:12]}"
        dest_path = upload_dir / f"{asset_id}{ext}"

        # Atomically move staged file to private storage
        staged.promote_to(dest_path)

        asset = register_media_asset(
            db=db,
            artisan_id=artisan_id,
            file_path=str(dest_path),
            mime_type=staged.mime_type,
            byte_size=staged.byte_size,
            sha256_checksum=staged.sha256_checksum,
            processing_provenance=provenance,
            source_media_id=source_media_id,
            is_degraded=is_degraded,
            degraded_reason=degraded_reason,
            status_str="ready",
        )
        return asset
    except Exception:
        staged.cleanup()
        if dest_path and dest_path.exists():
            dest_path.unlink(missing_ok=True)
        raise
