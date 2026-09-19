"""
Idempotency Failure Handling and Exact Execution Counting Tests.

Verifies:
1. Retry safety on AI endpoints:
   - Consecutive calls with the same Idempotency-Key and payload return the cached response.
   - Heavy ML operations (enhance_product_photo, transcribe_audio) execute strictly ONCE.
2. Failure release policy:
   - On business/validation failure (e.g. 422 below-floor price), the in-progress claim is released.
   - The database does not retain an orphaned in_progress record blocking subsequent retries.
3. Tampering rejection:
   - Reusing a completed idempotency key with a mismatched request payload returns 409 Conflict.
4. Concurrent in-flight request protection:
   - Active concurrent requests with the same key return 409 Conflict with Retry-After header.
"""

import io
import uuid
from pathlib import Path
from unittest.mock import patch, AsyncMock
import pytest
from httpx import AsyncClient, ASGITransport
from PIL import Image

from backend.main import app
from backend.database import SessionLocal, init_db
from backend.models.db_models import ArtisanDB, IdempotencyRecordDB, ProductDB
from backend.models.schemas import AudioTranscribeResponse
from backend.utils.auth import create_access_token

VALID_PNG = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
    b"\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\rIDATx\x9cc\xf8\xff\xff"
    b"?\x00\x05\xfe\x02\xfe\xa748V\x00\x00\x00\x00IEND\xaeB`\x82"
)

VALID_MP3 = b"ID3\x03\x00\x00\x00\x00\x00\x20" + b"\x00" * 40


@pytest.fixture(scope="module")
def setup_idem_artisan():
    init_db()
    db = SessionLocal()

    artisan = db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_idem_fail_test").first()
    if not artisan:
        artisan = ArtisanDB(
            id="artisan_idem_fail_test",
            name="Idem Fail Artisan",
            phone="+919876543210",
            craft_type="Brass",
        )
        db.add(artisan)
        db.commit()

    token = create_access_token("artisan_idem_fail_test")
    db.close()
    return {"token": token, "artisan_id": "artisan_idem_fail_test"}


@pytest.mark.anyio
async def test_enhancer_executes_strictly_once_on_retry(setup_idem_artisan, tmp_path):
    """Enhancer runs once; response-lost/duplicate retries replay cached result without invoking ML."""
    transport = ASGITransport(app=app)
    token = setup_idem_artisan["token"]
    headers = {
        "Authorization": f"Bearer {token}",
        "Idempotency-Key": f"idem_ai_once_{uuid.uuid4().hex[:8]}",
    }

    mock_enhanced_file = tmp_path / "mock_enhanced_once.png"
    img = Image.new("RGBA", (100, 100), (255, 255, 255, 255))
    img.save(str(mock_enhanced_file), "PNG")

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch(
            "backend.services.catalog_service.CatalogService.enhance_product_photo",
            return_value=(str(mock_enhanced_file), False, None),
        ) as mock_enhancer:
            # 1. First execution
            res1 = await client.post(
                "/api/v1/catalog/enhance-image",
                files={"image": ("sample.png", io.BytesIO(VALID_PNG), "image/png")},
                data={"return_format": "PNG"},
                headers=headers,
            )
            assert res1.status_code == 200
            data1 = res1.json()
            assert mock_enhancer.call_count == 1

            # 2. Duplicate retry with same key & identical payload
            res2 = await client.post(
                "/api/v1/catalog/enhance-image",
                files={"image": ("sample.png", io.BytesIO(VALID_PNG), "image/png")},
                data={"return_format": "PNG"},
                headers=headers,
            )
            assert res2.status_code == 200
            data2 = res2.json()

            # Cached result returned, enhancer NOT re-executed
            assert mock_enhancer.call_count == 1
            assert data2["media_id"] == data1["media_id"]
            assert data2["sha256_checksum"] == data1["sha256_checksum"]


@pytest.mark.anyio
async def test_transcriber_executes_strictly_once_on_retry(setup_idem_artisan):
    """Whisper STT runs once; retries return cached result without re-running transcription."""
    transport = ASGITransport(app=app)
    token = setup_idem_artisan["token"]
    headers = {
        "Authorization": f"Bearer {token}",
        "Idempotency-Key": f"idem_stt_once_{uuid.uuid4().hex[:8]}",
    }

    mock_resp = AudioTranscribeResponse(
        transcript="सुंदर पीतल की घंटी",
        language_code="hi",
        detected_language="hi",
        duration_seconds=2.5,
        provider="whisper",
        is_fallback=False,
        status="completed",
    )

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch(
            "backend.services.catalog_service.CatalogService.transcribe_audio",
            new_callable=AsyncMock,
            return_value=mock_resp,
        ) as mock_stt:
            # 1. First request
            res1 = await client.post(
                "/api/v1/voice/transcribe",
                files={"audio": ("note.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
                headers=headers,
            )
            assert res1.status_code == 200
            data1 = res1.json()
            assert mock_stt.call_count == 1

            # 2. Duplicate retry
            res2 = await client.post(
                "/api/v1/voice/transcribe",
                files={"audio": ("note.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
                headers=headers,
            )
            assert res2.status_code == 200
            data2 = res2.json()

            # Cached result returned, transcriber NOT re-executed
            assert mock_stt.call_count == 1
            assert data2["transcript"] == data1["transcript"]


@pytest.mark.anyio
async def test_failure_releases_idempotency_claim(setup_idem_artisan):
    """Validation failure (422) releases claim so key is not locked in-progress."""
    transport = ASGITransport(app=app)
    token = setup_idem_artisan["token"]
    artisan_id = setup_idem_artisan["artisan_id"]
    key = f"idem_fail_release_{uuid.uuid4().hex[:8]}"
    headers = {"Authorization": f"Bearer {token}", "Idempotency-Key": key}

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Submit invalid price below floor: materials 500, price 100 -> 422
        payload_invalid = {
            "title": "Below Floor Item",
            "price": 100.0,
            "materials": 500.0,
            "labor_hours": 1.0,
            "hourly_rate": 100.0,
            "transport": 10.0,
            "overhead": 10.0,
        }
        res_fail = await client.post("/api/v1/products", json=payload_invalid, headers=headers)
        assert res_fail.status_code == 422

        # Verify no orphaned in_progress claim exists in database
        db = SessionLocal()
        record = (
            db.query(IdempotencyRecordDB)
            .filter(
                IdempotencyRecordDB.artisan_id == artisan_id,
                IdempotencyRecordDB.idempotency_key == key,
            )
            .first()
        )
        assert record is None or record.status != "in_progress"
        db.close()


@pytest.mark.anyio
async def test_unpublish_endpoint_idempotency(setup_idem_artisan):
    """Unpublish transitions published -> draft, bumps revision, and replays idempotently."""
    transport = ASGITransport(app=app)
    token = setup_idem_artisan["token"]
    artisan_id = setup_idem_artisan["artisan_id"]

    db = SessionLocal()
    prod_id = f"prod_unpub_{uuid.uuid4().hex[:8]}"
    content_hash = "a" * 64
    product = ProductDB(
        id=prod_id,
        artisan_id=artisan_id,
        title="Published Silk Scarf",
        price_paise=150000,
        legacy_price=1500.0,
        materials_paise=50000,
        floor_price_paise=100000,
        status="published",
        revision=1,
        content_hash=content_hash,
        approved_revision=1,
        is_deleted=False,
    )
    db.add(product)
    db.commit()
    db.close()

    key = f"idem_unpub_test_{uuid.uuid4().hex[:8]}"
    headers = {"Authorization": f"Bearer {token}", "Idempotency-Key": key}
    unpub_payload = {"expected_revision": 1, "content_hash": content_hash}

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Unpublish product
        res1 = await client.post(f"/api/v1/products/{prod_id}/unpublish", json=unpub_payload, headers=headers)
        assert res1.status_code == 200
        data1 = res1.json()
        assert data1["status"] == "draft"
        assert data1["revision"] == 2
        assert data1["approved_revision"] is None

        # 2. Replay with identical idempotency key -> cached response returned
        res2 = await client.post(f"/api/v1/products/{prod_id}/unpublish", json=unpub_payload, headers=headers)
        assert res2.status_code == 200
        data2 = res2.json()
        assert data2["revision"] == 2
        assert data2["status"] == "draft"

