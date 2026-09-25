"""
Single-Pass Streaming Ingestion and True Magic-Byte Inspection Service.

Guarantees:
- Single-pass chunked streaming into staging file (bounded memory usage).
- Concurrent size check (aborting immediately with HTTP 413 if limit exceeded).
- Concurrent SHA-256 calculation on the fly without secondary file read.
- True magic-byte inspection (JPEG, PNG, WebP, MP3, WAV, M4A/AAC, OGG, FLAC) rejecting spoofed extensions with HTTP 422.
- Automatic cleanup of staged files upon validation or transaction error.
- Lineage-aware media asset registration (never collapsing derived/degraded records into raw source records).
"""

import hashlib
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Set, Tuple

import aiofiles
from fastapi import HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from ..config import get_settings
from ..models.db_models import MediaAssetDB

settings = get_settings()

IMAGE_MAX_BYTES = 15 * 1024 * 1024  # 15 MB
AUDIO_MAX_BYTES = 25 * 1024 * 1024  # 25 MB


def inspect_media_magic_bytes(header: bytes, allowed_categories: Set[str]) -> Tuple[str, str]:
    """
    Inspect initial magic bytes to determine true MIME type and media category.
    Raises HTTP 422 if unsupported or mismatched.
    """
    if len(header) < 4:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Uploaded file is too small or truncated.",
        )

    # 1. Images
    if "image" in allowed_categories:
        if header.startswith(b"\x89PNG\r\n\x1a\n"):
            return ("image/png", "image")
        if header.startswith(b"\xff\xd8\xff"):
            return ("image/jpeg", "image")
        if len(header) >= 12 and header.startswith(b"RIFF") and header[8:12] == b"WEBP":
            return ("image/webp", "image")

    # 2. Audio
    if "audio" in allowed_categories:
        if len(header) >= 12 and header.startswith(b"RIFF") and header[8:12] == b"WAVE":
            return ("audio/wav", "audio")
        if len(header) >= 8 and header[4:8] == b"ftyp":
            return ("audio/mp4", "audio")
        # Check raw ADTS AAC BEFORE MP3 syncword check because (0xF0 & 0xE0) == 0xE0
        # ADTS syncword is 12 bits 0xFFF with layer bits (bits 2..1) == 00
        if len(header) >= 2 and header[0] == 0xFF and (header[1] & 0xF6) == 0xF0:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Raw AAC streams without container are unsupported. Please provide containerized audio (M4A, WAV, MP3, FLAC, OGG).",
            )
        if header.startswith(b"ID3") or (
            len(header) >= 2
            and header[0] == 0xFF
            and (header[1] & 0xE0) == 0xE0
            and (header[1] & 0x06) != 0x00
        ):
            return ("audio/mpeg", "audio")
        if header.startswith(b"OggS"):
            return ("audio/ogg", "audio")
        if header.startswith(b"fLaC"):
            return ("audio/flac", "audio")

    allowed_desc = " / ".join(sorted(allowed_categories))
    raise HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        detail=f"Unsupported or spoofed media format. Allowed format category: {allowed_desc}.",
    )


@dataclass
class StagedUpload:
    staged_path: Path
    byte_size: int
    sha256_checksum: str
    mime_type: str
    category: str

    @property
    def file_path(self) -> Path:
        return self.staged_path

    def cleanup(self) -> None:
        try:
            self.staged_path.unlink(missing_ok=True)
        except Exception:
            pass

    def promote_to(self, dest_path: Path) -> Path:
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        self.staged_path.replace(dest_path)
        return dest_path


async def stream_and_validate_upload(
    file: UploadFile,
    max_bytes: int,
    allowed_categories: Set[str],
    staging_dir: Optional[Path] = None,
) -> StagedUpload:
    """
    Stream an uploaded file to a staging area in 64 KB chunks, calculating SHA-256
    and checking size limit on the fly. Inspects magic bytes from initial chunk.
    Aborts immediately and cleans up if size or magic-byte limits are violated.
    """
    if staging_dir is None:
        staging_dir = Path(settings.upload_dir) / "staging"
    staging_dir.mkdir(parents=True, exist_ok=True)

    stage_id = f"stage_{uuid.uuid4().hex}"
    staged_path = staging_dir / f"{stage_id}.tmp"

    hasher = hashlib.sha256()
    bytes_read = 0
    header_bytes = bytearray()
    chunk_size = 65536  # 64 KB

    try:
        async with aiofiles.open(staged_path, "wb") as out_f:
            while True:
                chunk = await file.read(chunk_size)
                if not chunk:
                    break
                bytes_read += len(chunk)
                if bytes_read > max_bytes:
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail=f"Upload size ({bytes_read} bytes) exceeds maximum limit of {max_bytes} bytes ({max_bytes // (1024 * 1024)} MB).",
                    )
                if len(header_bytes) < 32:
                    needed = 32 - len(header_bytes)
                    header_bytes.extend(chunk[:needed])
                hasher.update(chunk)
                await out_f.write(chunk)

        if bytes_read == 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Empty file uploaded.",
            )

        mime_type, category = inspect_media_magic_bytes(bytes(header_bytes), allowed_categories)
        sha256_checksum = hasher.hexdigest()

        return StagedUpload(
            staged_path=staged_path,
            byte_size=bytes_read,
            sha256_checksum=sha256_checksum,
            mime_type=mime_type,
            category=category,
        )
    except Exception:
        staged_path.unlink(missing_ok=True)
        raise


def get_existing_media_asset(
    db: Session,
    artisan_id: str,
    sha256_checksum: str,
    processing_provenance: str,
    source_media_id: Optional[str] = None,
    is_degraded: bool = False,
) -> Optional[MediaAssetDB]:
    """
    Deduplicate media assets while strictly preserving lineage.
    Never collapses derived or degraded assets into raw source records.
    """
    query = db.query(MediaAssetDB).filter(
        MediaAssetDB.artisan_id == artisan_id,
        MediaAssetDB.sha256_checksum == sha256_checksum,
        MediaAssetDB.status == "ready",
        MediaAssetDB.processing_provenance == processing_provenance,
        MediaAssetDB.is_degraded == is_degraded,
    )
    if source_media_id is not None:
        query = query.filter(MediaAssetDB.source_media_id == source_media_id)
    else:
        query = query.filter(MediaAssetDB.source_media_id.is_(None))

    asset = query.first()
    if asset and Path(asset.file_path).exists():
        return asset
    return None


def register_media_asset(
    db: Session,
    artisan_id: str,
    file_path: str,
    mime_type: str,
    byte_size: int,
    sha256_checksum: str,
    processing_provenance: str = "artisan_direct_upload",
    source_media_id: Optional[str] = None,
    is_degraded: bool = False,
    degraded_reason: Optional[str] = None,
    status_str: str = "ready",
) -> MediaAssetDB:
    """
    Record a verified MediaAssetDB record transactionally.
    """
    # Check lineage-aware deduplication
    existing = get_existing_media_asset(
        db=db,
        artisan_id=artisan_id,
        sha256_checksum=sha256_checksum,
        processing_provenance=processing_provenance,
        source_media_id=source_media_id,
        is_degraded=is_degraded,
    )
    if existing:
        return existing

    asset_id = f"med_{uuid.uuid4().hex[:12]}"
    file_url = f"/api/v1/media/{asset_id}"

    asset = MediaAssetDB(
        id=asset_id,
        artisan_id=artisan_id,
        file_path=file_path,
        file_url=file_url,
        mime_type=mime_type,
        byte_size=byte_size,
        sha256_checksum=sha256_checksum,
        processing_provenance=processing_provenance,
        source_media_id=source_media_id,
        is_degraded=is_degraded,
        degraded_reason=degraded_reason,
        status=status_str,
    )
    db.add(asset)
    db.flush()
    return asset
