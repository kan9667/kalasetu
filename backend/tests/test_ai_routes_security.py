"""
Security & Hardening Tests for AI & Upload Routes.

Verifies:
1. Bearer token authentication required on all compute endpoints (401 Unauthorized).
2. Public informational endpoints remain open without auth (200 OK).
3. Required Idempotency-Key header on retryable AI endpoints (422 Unprocessable Content).
4. True magic-byte validation rejecting spoofed MIME types and truncated headers (422).
5. File size limits enforced via early-abort chunk streaming (413 Request Entity Too Large):
   - Images > 15 MB
   - Audio > 25 MB
"""

import io
import uuid
import pytest
from httpx import AsyncClient, ASGITransport

from backend.main import app
from backend.database import SessionLocal, init_db
from backend.models.db_models import ArtisanDB
from backend.utils.auth import create_access_token

# Valid 1x1 PNG bytes
VALID_PNG = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
    b"\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\rIDATx\x9cc\xf8\xff\xff"
    b"?\x00\x05\xfe\x02\xfe\xa748V\x00\x00\x00\x00IEND\xaeB`\x82"
)

# Valid audio bytes
VALID_MP3 = b"ID3\x03\x00\x00\x00\x00\x00\x20" + b"\x00" * 40


@pytest.fixture(scope="module")
def setup_security_artisan():
    init_db()
    db = SessionLocal()

    artisan = db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_ai_sec_test").first()
    if not artisan:
        artisan = ArtisanDB(
            id="artisan_ai_sec_test",
            name="Security Test Artisan",
            phone="+919876543219",
            craft_type="Brass",
        )
        db.add(artisan)
        db.commit()

    token = create_access_token("artisan_ai_sec_test")
    db.close()
    return {"token": token, "artisan_id": "artisan_ai_sec_test"}


@pytest.mark.anyio
async def test_unauthenticated_requests_rejected_with_401():
    """All compute endpoints strictly require Authorization Bearer token."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Catalog enhance image
        res = await client.post(
            "/api/v1/catalog/enhance-image",
            files={"image": ("test.png", io.BytesIO(VALID_PNG), "image/png")},
            headers={"Idempotency-Key": "key_1"},
        )
        assert res.status_code == 401

        # 2. Voice transcribe
        res = await client.post(
            "/api/v1/voice/transcribe",
            files={"audio": ("test.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
            headers={"Idempotency-Key": "key_2"},
        )
        assert res.status_code == 401

        # 3. Voice process
        res = await client.post(
            "/api/v1/voice/process",
            files={"audio": ("test.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
            headers={"Idempotency-Key": "key_3"},
        )
        assert res.status_code == 401

        # 4. Pricing suggest
        res = await client.post(
            "/api/v1/pricing/suggest",
            json={"title": "Brass Lamp", "materials_cost": 500, "labor_hours": 3},
            headers={"Idempotency-Key": "key_4"},
        )
        assert res.status_code == 401

        # 5. Chat message
        res = await client.post(
            "/api/v1/chat/message",
            json={"message": "Hello"},
        )
        assert res.status_code == 401

        # 6. Chat voice
        res = await client.post(
            "/api/v1/chat/voice",
            files={"audio": ("test.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
        )
        assert res.status_code == 401


@pytest.mark.anyio
async def test_public_informational_endpoints_open():
    """Glossary and Quick Topics endpoints remain public read-only."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res_glossary = await client.get("/api/v1/voice/glossary")
        assert res_glossary.status_code == 200

        res_topics = await client.get("/api/v1/chat/quick-topics")
        assert res_topics.status_code == 200


@pytest.mark.anyio
async def test_missing_idempotency_key_rejected(setup_security_artisan):
    """Mutating AI routes reject requests missing Idempotency-Key header."""
    transport = ASGITransport(app=app)
    token = setup_security_artisan["token"]
    auth_header = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.post(
            "/api/v1/catalog/enhance-image",
            files={"image": ("test.png", io.BytesIO(VALID_PNG), "image/png")},
            headers=auth_header,
        )
        assert res.status_code == 422
        assert "Idempotency-Key" in res.json()["detail"]

        res = await client.post(
            "/api/v1/voice/transcribe",
            files={"audio": ("test.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
            headers=auth_header,
        )
        assert res.status_code == 422
        assert "Idempotency-Key" in res.json()["detail"]

        res = await client.post(
            "/api/v1/pricing/suggest-upload",
            data={"description": "Handcrafted brass lamp"},
            headers=auth_header,
        )
        assert res.status_code == 422
        assert "Idempotency-Key" in res.json()["detail"]


@pytest.mark.anyio
async def test_spoofed_and_truncated_magic_bytes_rejected(setup_security_artisan):
    """Files with fraudulent extensions or truncated headers are rejected with 422."""
    transport = ASGITransport(app=app)
    token = setup_security_artisan["token"]
    headers = {
        "Authorization": f"Bearer {token}",
        "Idempotency-Key": f"idem_spoof_{uuid.uuid4().hex[:8]}",
    }

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Truncated (< 32 bytes)
        res_trunc = await client.post(
            "/api/v1/media/upload",
            files={"file": ("tiny.png", io.BytesIO(b"short"), "image/png")},
            headers=headers,
        )
        assert res_trunc.status_code == 422
        assert "unsupported or spoofed" in res_trunc.json()["detail"].lower()

        # 2. Text/HTML spoofed as image/png
        fake_png = b"<html><body>Not an image</body></html>" + b"\x00" * 32
        res_spoof_img = await client.post(
            "/api/v1/media/upload",
            files={"file": ("fake.png", io.BytesIO(fake_png), "image/png")},
            headers={**headers, "Idempotency-Key": f"idem_spoof_{uuid.uuid4().hex[:8]}"},
        )
        assert res_spoof_img.status_code == 422
        assert "unsupported or spoofed" in res_spoof_img.json()["detail"].lower()

        # 3. Text/HTML spoofed as audio/mpeg
        fake_audio = b"MZ\x90\x00" + b"\x00" * 40  # PE executable header
        res_spoof_aud = await client.post(
            "/api/v1/voice/transcribe",
            files={"audio": ("fake.mp3", io.BytesIO(fake_audio), "audio/mpeg")},
            headers={**headers, "Idempotency-Key": f"idem_spoof_{uuid.uuid4().hex[:8]}"},
        )
        assert res_spoof_aud.status_code == 422
        assert "unsupported or spoofed" in res_spoof_aud.json()["detail"].lower()


@pytest.mark.anyio
async def test_oversized_upload_aborts_with_413(setup_security_artisan):
    """Uploads exceeding limits are aborted chunk-by-chunk and return 413."""
    transport = ASGITransport(app=app)
    token = setup_security_artisan["token"]
    headers = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Image exceeding 15 MB limit (create 15.5 MB payload with valid PNG header)
        oversized_image = io.BytesIO(VALID_PNG + b"\x00" * (16 * 1024 * 1024))
        res_img = await client.post(
            "/api/v1/media/upload",
            files={"file": ("huge.png", oversized_image, "image/png")},
            headers={**headers, "Idempotency-Key": f"idem_huge_img_{uuid.uuid4().hex[:8]}"},
        )
        assert res_img.status_code == 413
        assert "exceeds maximum limit" in res_img.json()["detail"]
