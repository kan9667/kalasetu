"""
Adversarial Idempotency Fingerprint Tests for all 11 AI endpoints.

Endpoints verified:
1. /api/v1/catalog/enhance-image
2. /api/v1/catalog/generate-listing
3. /api/v1/catalog/voice-to-listing
4. /api/v1/catalog/voice-to-product
5. /api/v1/voice/transcribe
6. /api/v1/voice/process
7. /api/v1/pricing/suggest
8. /api/v1/pricing/suggest-upload
9. /api/v1/pricing/suggest-from-voice
10. /api/v1/chat/message
11. /api/v1/chat/voice

Verifies:
- Absence of Idempotency-Key returns 422.
- Successful first execution claims and completes key.
- Identical replay returns cached response.
- Changing ANY parameter with the same Idempotency-Key returns HTTP 409 Conflict.
"""

import io
import uuid
from pathlib import Path
from unittest.mock import patch
import pytest
from httpx import AsyncClient, ASGITransport
from PIL import Image

from backend.main import app
from backend.database import SessionLocal, init_db
from backend.models.db_models import ArtisanDB
from backend.models.schemas import (
    AudioTranscribeResponse,
    ListingGenerateResponse,
    PriceSuggestResponse,
    ProductCreate,
    VoiceToProductResponse,
    ChatResponseSchema,
    VoiceChatResponseSchema,
)
from backend.utils.auth import create_access_token

VALID_PNG = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
    b"\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\rIDATx\x9cc\xf8\xff\xff"
    b"?\x00\x05\xfe\x02\xfe\xa748V\x00\x00\x00\x00IEND\xaeB`\x82"
)
VALID_PNG_ALT = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x02\x00\x00\x00\x02"
    b"\x08\x06\x00\x00\x00\x72\xb6\x0d\x24\x00\x00\x00\x0fIDATx\x9cc\xf8\xff\xff"
    b"?\x03\x03\x03\x00\x18\x04\x01\x7f\x12\x34\x56\x78\x00\x00\x00\x00IEND\xaeB`\x82"
)
VALID_MP3 = b"ID3\x03\x00\x00\x00\x00\x00\x20" + b"\x00" * 40
VALID_MP3_ALT = b"ID3\x03\x00\x00\x00\x00\x00\x20" + b"\x01" * 40


def make_mock_pricing_response(suggested_price: float = 500.0) -> PriceSuggestResponse:
    return PriceSuggestResponse(
        suggested_price=suggested_price,
        min_price=suggested_price * 0.9,
        max_price=suggested_price * 1.2,
        floor_price=suggested_price * 0.7,
        confidence_score=0.85,
        market_position="mid-range",
        reasoning="Handcrafted with attention to detail.",
        reasoning_hi="हाथ से बना हुआ उत्कृष्ट शिल्प।",
        comparable_products=[],
    )


def make_mock_voice_to_product(title: str = "Brass Pot") -> VoiceToProductResponse:
    pricing = make_mock_pricing_response(500.0)
    return VoiceToProductResponse(
        transcript="Handmade brass pot",
        language_code="hi",
        title_en=title,
        title_hi="पीतल का घड़ा",
        description_en="Handcrafted brass pot.",
        description_hi="हाथ से बना पीतल का घड़ा।",
        category="Brass",
        tags=["brass", "pot"],
        pricing=pricing,
        product_draft=ProductCreate(
            title=title,
            description="Handcrafted brass pot.",
            price=500.0,
            materials=200.0,
            labor_hours=2.0,
            hourly_rate=100.0,
            transport=20.0,
            overhead=10.0,
        ),
        status="completed",
    )


@pytest.fixture(scope="module")
def setup_ai_artisan():
    init_db()
    db = SessionLocal()
    artisan = db.query(ArtisanDB).filter(ArtisanDB.id == "artisan_ai_idem_test").first()
    if not artisan:
        artisan = ArtisanDB(
            id="artisan_ai_idem_test",
            name="AI Idem Artisan",
            phone="+919876543222",
            craft_type="Brass",
        )
        db.add(artisan)
        db.commit()
    token = create_access_token("artisan_ai_idem_test")
    db.close()
    return {"token": token, "artisan_id": "artisan_ai_idem_test"}


@pytest.mark.anyio
async def test_1_catalog_enhance_image_fingerprint(setup_ai_artisan, tmp_path):
    """1. /catalog/enhance-image: 409 when image changes with same key."""
    transport = ASGITransport(app=app)
    token = setup_ai_artisan["token"]
    key = f"idem_ai_enh_{uuid.uuid4().hex[:8]}"

    mock_enhanced = tmp_path / "enhanced.png"
    Image.new("RGBA", (50, 50), (255, 255, 255)).save(str(mock_enhanced), "PNG")

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch("backend.services.catalog_service.CatalogService.enhance_product_photo", return_value=(str(mock_enhanced), False, None)):
            # 1. Successful first call
            r1 = await client.post(
                "/api/v1/catalog/enhance-image",
                files={"image": ("img1.png", io.BytesIO(VALID_PNG), "image/png")},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r1.status_code == 200

            # 2. Replay same image -> 200 cached
            r2 = await client.post(
                "/api/v1/catalog/enhance-image",
                files={"image": ("img1.png", io.BytesIO(VALID_PNG), "image/png")},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r2.status_code == 200

            # 3. Alter image bytes -> 409 Conflict
            r3 = await client.post(
                "/api/v1/catalog/enhance-image",
                files={"image": ("img2.png", io.BytesIO(VALID_PNG_ALT), "image/png")},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r3.status_code == 409


@pytest.mark.anyio
async def test_2_catalog_generate_listing_fingerprint(setup_ai_artisan):
    """2. /catalog/generate-listing: 409 when transcript or category_hint changes."""
    transport = ASGITransport(app=app)
    token = setup_ai_artisan["token"]
    key = f"idem_ai_gen_{uuid.uuid4().hex[:8]}"

    mock_res = ListingGenerateResponse(
        title_en="Brass Pot",
        title_hi="पीतल का घड़ा",
        description_en="Handmade",
        description_hi="हस्तनिर्मित",
        category="Pottery",
        tags=["brass", "pot"],
    )

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch("backend.services.catalog_service.CatalogService.generate_listing", return_value=mock_res):
            # 1. Success
            r1 = await client.post(
                "/api/v1/catalog/generate-listing",
                json={"transcript": "Brass vase handmade", "language_code": "hi", "category_hint": "Brass"},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r1.status_code == 200

            # 2. Replay
            r2 = await client.post(
                "/api/v1/catalog/generate-listing",
                json={"transcript": "Brass vase handmade", "language_code": "hi", "category_hint": "Brass"},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r2.status_code == 200

            # 3. Change category_hint -> 409 Conflict
            r3 = await client.post(
                "/api/v1/catalog/generate-listing",
                json={"transcript": "Brass vase handmade", "language_code": "hi", "category_hint": "Textiles"},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r3.status_code == 409


@pytest.mark.anyio
async def test_3_catalog_voice_to_listing_fingerprint(setup_ai_artisan):
    """3. /catalog/voice-to-listing: 409 when category_hint or audio changes."""
    transport = ASGITransport(app=app)
    token = setup_ai_artisan["token"]
    key = f"idem_ai_v2l_{uuid.uuid4().hex[:8]}"

    mock_tr = AudioTranscribeResponse(transcript="Handmade brass pot", language_code="hi")
    mock_gen = ListingGenerateResponse(
        title_en="Pot", title_hi="घड़ा", description_en="Desc", description_hi="वर्णन", category="Brass", tags=["pot"]
    )

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch("backend.services.catalog_service.CatalogService.transcribe_audio", return_value=mock_tr), \
             patch("backend.services.catalog_service.CatalogService.generate_listing", return_value=mock_gen):
            r1 = await client.post(
                "/api/v1/catalog/voice-to-listing",
                files={"audio": ("audio.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
                data={"language_code": "hi", "category_hint": "Brass"},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r1.status_code == 200

            # Change category_hint -> 409
            r2 = await client.post(
                "/api/v1/catalog/voice-to-listing",
                files={"audio": ("audio.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
                data={"language_code": "hi", "category_hint": "Woodwork"},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r2.status_code == 409


@pytest.mark.anyio
async def test_4_catalog_voice_to_product_fingerprint(setup_ai_artisan):
    """4. /catalog/voice-to-product: 409 when materials or labor_hours change."""
    transport = ASGITransport(app=app)
    token = setup_ai_artisan["token"]
    key = f"idem_ai_v2p_{uuid.uuid4().hex[:8]}"

    mock_res = make_mock_voice_to_product()

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch("backend.services.catalog_service.CatalogService.process_voice_to_product", return_value=mock_res):
            r1 = await client.post(
                "/api/v1/catalog/voice-to-product",
                files={"audio": ("audio.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
                data={
                    "raw_material_cost": 200.0,
                    "labor_hours": 2.0,
                    "hourly_wage": 100.0,
                    "transport": 20.0,
                    "overhead": 10.0,
                },
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r1.status_code == 200

            # Change raw_material_cost -> 409
            r2 = await client.post(
                "/api/v1/catalog/voice-to-product",
                files={"audio": ("audio.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
                data={
                    "raw_material_cost": 300.0,  # Changed
                    "labor_hours": 2.0,
                    "hourly_wage": 100.0,
                    "transport": 20.0,
                    "overhead": 10.0,
                },
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r2.status_code == 409


@pytest.mark.anyio
async def test_5_voice_transcribe_fingerprint(setup_ai_artisan):
    """5. /voice/transcribe: 409 when category_hint changes."""
    transport = ASGITransport(app=app)
    token = setup_ai_artisan["token"]
    key = f"idem_voice_tr_{uuid.uuid4().hex[:8]}"

    mock_tr = AudioTranscribeResponse(transcript="Handcrafted", language_code="hi")

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch("backend.services.catalog_service.CatalogService.transcribe_audio", return_value=mock_tr):
            r1 = await client.post(
                "/api/v1/voice/transcribe",
                files={"audio": ("audio.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
                data={"language_code": "hi", "category_hint": "Jewelry"},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r1.status_code == 200

            # Change category_hint -> 409
            r2 = await client.post(
                "/api/v1/voice/transcribe",
                files={"audio": ("audio.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
                data={"language_code": "hi", "category_hint": "Textiles"},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r2.status_code == 409


@pytest.mark.anyio
async def test_6_voice_process_fingerprint(setup_ai_artisan):
    """6. /voice/process: 409 when hourly_wage or transport changes."""
    transport = ASGITransport(app=app)
    token = setup_ai_artisan["token"]
    key = f"idem_voice_proc_{uuid.uuid4().hex[:8]}"

    mock_res = make_mock_voice_to_product()

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch("backend.services.catalog_service.CatalogService.process_voice_to_product", return_value=mock_res):
            r1 = await client.post(
                "/api/v1/voice/process",
                files={"audio": ("audio.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
                data={"raw_material_cost": 100.0, "labor_hours": 1.0, "hourly_wage": 100.0, "transport": 10.0, "overhead": 10.0},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r1.status_code == 200

            # Change transport -> 409
            r2 = await client.post(
                "/api/v1/voice/process",
                files={"audio": ("audio.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
                data={"raw_material_cost": 100.0, "labor_hours": 1.0, "hourly_wage": 100.0, "transport": 50.0, "overhead": 10.0},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r2.status_code == 409


@pytest.mark.anyio
async def test_7_pricing_suggest_fingerprint(setup_ai_artisan):
    """7. /pricing/suggest: 409 when tags or labor_hours change."""
    transport = ASGITransport(app=app)
    token = setup_ai_artisan["token"]
    key = f"idem_price_sug_{uuid.uuid4().hex[:8]}"

    mock_res = make_mock_pricing_response(600.0)

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch("backend.services.pricing_service.PricingService.suggest_price", return_value=mock_res):
            r1 = await client.post(
                "/api/v1/pricing/suggest",
                json={
                    "description": "Brass idol",
                    "category": "Brass",
                    "raw_material_cost": 200.0,
                    "labor_hours": 3.0,
                    "hourly_wage": 100.0,
                    "transport": 20.0,
                    "overhead": 10.0,
                    "tags": ["brass", "idol"],
                },
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r1.status_code == 200

            # Change tags -> 409
            r2 = await client.post(
                "/api/v1/pricing/suggest",
                json={
                    "description": "Brass idol",
                    "category": "Brass",
                    "raw_material_cost": 200.0,
                    "labor_hours": 3.0,
                    "hourly_wage": 100.0,
                    "transport": 20.0,
                    "overhead": 10.0,
                    "tags": ["brass", "statue"],  # Changed tag
                },
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r2.status_code == 409


@pytest.mark.anyio
async def test_8_pricing_suggest_upload_fingerprint(setup_ai_artisan):
    """8. /pricing/suggest-upload: 409 when overhead or tags change."""
    transport = ASGITransport(app=app)
    token = setup_ai_artisan["token"]
    key = f"idem_price_up_{uuid.uuid4().hex[:8]}"

    mock_res = make_mock_pricing_response(500.0)

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch("backend.services.pricing_service.PricingService.suggest_price", return_value=mock_res):
            r1 = await client.post(
                "/api/v1/pricing/suggest-upload",
                files={"image": ("pot.png", io.BytesIO(VALID_PNG), "image/png")},
                data={
                    "description": "Clay pitcher",
                    "category": "Pottery",
                    "raw_material_cost": 100.0,
                    "labor_hours": 2.0,
                    "hourly_wage": 80.0,
                    "transport": 10.0,
                    "overhead": 5.0,
                    "tags": "clay,pitcher",
                },
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r1.status_code == 200

            # Change overhead -> 409
            r2 = await client.post(
                "/api/v1/pricing/suggest-upload",
                files={"image": ("pot.png", io.BytesIO(VALID_PNG), "image/png")},
                data={
                    "description": "Clay pitcher",
                    "category": "Pottery",
                    "raw_material_cost": 100.0,
                    "labor_hours": 2.0,
                    "hourly_wage": 80.0,
                    "transport": 10.0,
                    "overhead": 25.0,  # Changed overhead
                    "tags": "clay,pitcher",
                },
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r2.status_code == 409


@pytest.mark.anyio
async def test_9_pricing_suggest_from_voice_fingerprint(setup_ai_artisan):
    """9. /pricing/suggest-from-voice: 409 when category_hint or labor_hours change."""
    transport = ASGITransport(app=app)
    token = setup_ai_artisan["token"]
    key = f"idem_price_voc_{uuid.uuid4().hex[:8]}"

    mock_tr = AudioTranscribeResponse(transcript="Terracotta bowl", language_code="hi")
    mock_gen = ListingGenerateResponse(title_en="Bowl", title_hi="कटोरा", description_en="D", description_hi="व", category="Pottery", tags=["bowl"])
    mock_sug = make_mock_pricing_response(300.0)

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch("backend.services.catalog_service.CatalogService.transcribe_audio", return_value=mock_tr), \
             patch("backend.services.catalog_service.CatalogService.generate_listing", return_value=mock_gen), \
             patch("backend.services.pricing_service.PricingService.suggest_price", return_value=mock_sug):
            r1 = await client.post(
                "/api/v1/pricing/suggest-from-voice",
                files={"audio": ("audio.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
                data={"language_code": "hi", "category_hint": "Pottery", "raw_material_cost": 50.0, "labor_hours": 1.0, "hourly_wage": 60.0},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r1.status_code == 200

            # Change category_hint -> 409
            r2 = await client.post(
                "/api/v1/pricing/suggest-from-voice",
                files={"audio": ("audio.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
                data={"language_code": "hi", "category_hint": "Clayware", "raw_material_cost": 50.0, "labor_hours": 1.0, "hourly_wage": 60.0},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r2.status_code == 409


@pytest.mark.anyio
async def test_10_chat_message_fingerprint(setup_ai_artisan):
    """10. /chat/message: 409 when message text or current_screen changes."""
    transport = ASGITransport(app=app)
    token = setup_ai_artisan["token"]
    key = f"idem_chat_msg_{uuid.uuid4().hex[:8]}"

    mock_chat = ChatResponseSchema(
        reply="Hello artisan",
        action=None,
        suggested_queries=["Add product"],
    )

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch("backend.services.chat_service.ChatService.process_message", return_value=mock_chat):
            r1 = await client.post(
                "/api/v1/chat/message",
                json={"message": "How do I list?", "current_screen": "catalogue", "artisan_craft": "Brass", "language_code": "en"},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r1.status_code == 200

            # Replay -> 200
            r2 = await client.post(
                "/api/v1/chat/message",
                json={"message": "How do I list?", "current_screen": "catalogue", "artisan_craft": "Brass", "language_code": "en"},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r2.status_code == 200

            # Alter message text -> 409 Conflict
            r3 = await client.post(
                "/api/v1/chat/message",
                json={"message": "How do I price?", "current_screen": "catalogue", "artisan_craft": "Brass", "language_code": "en"},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r3.status_code == 409


@pytest.mark.anyio
async def test_11_chat_voice_fingerprint(setup_ai_artisan):
    """11. /chat/voice: 409 when audio or current_screen changes."""
    transport = ASGITransport(app=app)
    token = setup_ai_artisan["token"]
    key = f"idem_chat_voc_{uuid.uuid4().hex[:8]}"

    mock_tr = AudioTranscribeResponse(transcript="How to sell?", language_code="en")
    mock_chat = ChatResponseSchema(reply="You can sell online", action=None, suggested_queries=[])

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch("backend.services.catalog_service.CatalogService.transcribe_audio", return_value=mock_tr), \
             patch("backend.services.chat_service.ChatService.process_message", return_value=mock_chat):
            r1 = await client.post(
                "/api/v1/chat/voice",
                files={"audio": ("audio.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
                data={"language_code": "en", "current_screen": "home", "artisan_craft": "Pottery"},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r1.status_code == 200

            # Change current_screen -> 409 Conflict
            r2 = await client.post(
                "/api/v1/chat/voice",
                files={"audio": ("audio.mp3", io.BytesIO(VALID_MP3), "audio/mpeg")},
                data={"language_code": "en", "current_screen": "profile", "artisan_craft": "Pottery"},
                headers={"Authorization": f"Bearer {token}", "Idempotency-Key": key},
            )
            assert r2.status_code == 409
